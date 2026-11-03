// endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde C++.
//
// Dependencia: libcurl (en Debian/Ubuntu: sudo apt install libcurl4-openssl-dev).
// Compilar:    g++ -std=c++17 consulta.cpp -o consulta -lcurl
//
// Uso:
//   export ENDPOINT_API_KEY=ep_live_...
//   ./consulta ruc 20131312955
//   ./consulta dni 45871236
//   ./consulta tipo-cambio
//   ./consulta ubigeo 150101
//   ./consulta empresas "superintendencia aduanas"
//   ./consulta anexos 20131312955
//   ./consulta representantes 20131312955
//   ./consulta trabajadores 20131312955
//
// El programa imprime el JSON de la respuesta tal cual llega. Para convertirlo a objetos usa
// nlohmann/json (ver README); aquí solo se extraen `error` y `message` para informar fallos.
//
// Documentación: https://endpoint.pe/docs

#include <curl/curl.h>

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

constexpr long kTimeoutSegundos = 15;
constexpr int kReintentos = 3;  // solo ante errores de red o 5xx; nunca ante 404 o 422

// Respuesta cruda de la API.
struct Respuesta {
    long status = 0;        // código HTTP, 0 si falló la conexión
    std::string cuerpo;     // JSON completo
    std::string error;      // campo `error` cuando status != 200
    std::string mensaje;    // campo `message` cuando status != 200
    long creditosDisponibles = -1;
};

size_t escribir(void* contenido, size_t tam, size_t n, void* destino) {
    static_cast<std::string*>(destino)->append(static_cast<char*>(contenido), tam * n);
    return tam * n;
}

size_t leerCabecera(char* linea, size_t tam, size_t n, void* destino) {
    std::string l(linea, tam * n);
    const std::string clave = "x-credits-remaining:";
    if (l.size() > clave.size()) {
        std::string inicio = l.substr(0, clave.size());
        for (auto& c : inicio) c = static_cast<char>(std::tolower(c));
        if (inicio == clave) {
            *static_cast<long*>(destino) = std::strtol(l.c_str() + clave.size(), nullptr, 10);
        }
    }
    return tam * n;
}

// Valor de texto de un campo de primer nivel ("error", "message"). Solo para mensajes.
std::string campo(const std::string& json, const std::string& nombre) {
    auto p = json.find("\"" + nombre + "\"");
    if (p == std::string::npos) return "";
    p = json.find(':', p);
    if (p == std::string::npos) return "";
    p = json.find_first_not_of(" \t", p + 1);
    if (p == std::string::npos || json[p] != '"') return "";
    std::string valor;
    for (++p; p < json.size() && json[p] != '"'; ++p) {
        if (json[p] == '\\' && p + 1 < json.size()) ++p;
        valor += json[p];
    }
    return valor;
}

}  // namespace

/// Cliente de la API v1. Cada método devuelve la respuesta cruda (JSON completo en `cuerpo`).
class EndpointPe {
public:
    explicit EndpointPe(std::string apiKey = valorEntorno("ENDPOINT_API_KEY", ""),
                        std::string baseUrl = valorEntorno("ENDPOINT_BASE_URL", "https://api.endpoint.pe/v1"))
        : apiKey_(std::move(apiKey)), baseUrl_(std::move(baseUrl)) {
        if (apiKey_.empty()) {
            throw std::invalid_argument("Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.");
        }
        while (!baseUrl_.empty() && baseUrl_.back() == '/') baseUrl_.pop_back();
    }

    // Empresas (SUNAT)
    Respuesta ruc(const std::string& ruc) { return get("/ruc/" + codificar(ruc)); }
    Respuesta anexos(const std::string& ruc) { return get("/ruc/" + codificar(ruc) + "/anexos"); }
    Respuesta representantes(const std::string& ruc) { return get("/ruc/" + codificar(ruc) + "/representantes"); }
    Respuesta trabajadores(const std::string& ruc) { return get("/ruc/" + codificar(ruc) + "/trabajadores"); }
    Respuesta empresas(const std::string& texto) { return get("/empresas?q=" + codificar(texto)); }
    // Identidad (RENIEC)
    Respuesta dni(const std::string& dni) { return get("/dni/" + codificar(dni)); }
    // Finanzas y ubicación
    Respuesta tipoCambio() { return get("/tipo-cambio"); }
    Respuesta ubigeo(const std::string& codigo) { return get("/ubigeo/" + codificar(codigo)); }

private:
    std::string apiKey_;
    std::string baseUrl_;

    static std::string valorEntorno(const char* nombre, const char* porDefecto = "") {
        const char* v = std::getenv(nombre);
        return (v != nullptr && v[0] != '\0') ? v : porDefecto;
    }

    static std::string codificar(const std::string& valor) {
        CURL* curl = curl_easy_init();
        char* c = curl_easy_escape(curl, valor.c_str(), static_cast<int>(valor.size()));
        std::string salida = c ? c : "";
        curl_free(c);
        curl_easy_cleanup(curl);
        return salida;
    }

    Respuesta get(const std::string& ruta) {
        for (int intento = 1;; ++intento) {
            Respuesta r = peticion(ruta);
            if ((r.status == 0 || r.status >= 500) && intento < kReintentos) {
                std::this_thread::sleep_for(std::chrono::seconds(1 << (intento - 1)));
                continue;
            }
            if (r.status != 200) {
                r.error = campo(r.cuerpo, "error");
                r.mensaje = campo(r.cuerpo, "message");
                if (r.error.empty()) r.error = r.status == 0 ? "red" : "error";
                if (r.mensaje.empty()) r.mensaje = r.status == 0 ? "No se pudo conectar con la API." : "Respuesta inesperada";
            }
            return r;
        }
    }

    Respuesta peticion(const std::string& ruta) {
        Respuesta r;
        CURL* curl = curl_easy_init();
        if (curl == nullptr) return r;

        const std::string url = baseUrl_ + ruta;
        const std::string autorizacion = "Authorization: Bearer " + apiKey_;
        curl_slist* cabeceras = nullptr;
        cabeceras = curl_slist_append(cabeceras, autorizacion.c_str());
        cabeceras = curl_slist_append(cabeceras, "Accept: application/json");

        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, cabeceras);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "endpoint-pe-ejemplos/cpp");
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, kTimeoutSegundos);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, escribir);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &r.cuerpo);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, leerCabecera);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &r.creditosDisponibles);

        CURLcode rc = curl_easy_perform(curl);
        if (rc == CURLE_OK) {
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &r.status);
        } else {
            r.cuerpo.clear();
            r.mensaje = curl_easy_strerror(rc);
        }
        curl_slist_free_all(cabeceras);
        curl_easy_cleanup(curl);
        return r;
    }
};

// --- Uso desde la terminal ---

namespace {

const char* kUso =
    "Uso: ./consulta <comando> [dato]\n\n"
    "  ruc <ruc>              Ficha del contribuyente (SUNAT)\n"
    "  dni <dni>              Nombres y apellidos del titular (RENIEC)\n"
    "  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)\n"
    "  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo\n"
    "  empresas <texto>       Buscar el RUC de una empresa por su razón social\n"
    "  anexos <ruc>           Establecimientos anexos de un RUC\n"
    "  representantes <ruc>   Representantes legales de un RUC\n"
    "  trabajadores <ruc>     Trabajadores declarados por periodo\n\n"
    "La API key se lee de la variable de entorno ENDPOINT_API_KEY.\n"
    "Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys\n";

}  // namespace

int main(int argc, char** argv) {
    const std::string comando = argc > 1 ? argv[1] : "";
    const std::string dato = argc > 2 ? argv[2] : "";
    if (comando.empty() || comando == "-h" || comando == "--help" || comando == "ayuda") {
        std::cout << kUso;
        return 0;
    }

    const std::map<std::string, bool> necesitaDato = {
        {"ruc", true}, {"dni", true}, {"tipo-cambio", false}, {"ubigeo", true},
        {"empresas", true}, {"anexos", true}, {"representantes", true}, {"trabajadores", true},
    };
    auto it = necesitaDato.find(comando);
    if (it == necesitaDato.end()) {
        std::cerr << "Comando desconocido: " << comando << "\n\n" << kUso;
        return 2;
    }
    if (it->second && dato.empty()) {
        std::cerr << "El comando '" << comando << "' necesita un dato.\n";
        return 2;
    }

    curl_global_init(CURL_GLOBAL_DEFAULT);
    int salida = 0;
    try {
        EndpointPe api;
        Respuesta r;
        if (comando == "ruc") r = api.ruc(dato);
        else if (comando == "dni") r = api.dni(dato);
        else if (comando == "tipo-cambio") r = api.tipoCambio();
        else if (comando == "ubigeo") r = api.ubigeo(dato);
        else if (comando == "empresas") r = api.empresas(dato);
        else if (comando == "anexos") r = api.anexos(dato);
        else if (comando == "representantes") r = api.representantes(dato);
        else r = api.trabajadores(dato);

        if (r.status == 200) {
            std::cout << r.cuerpo << '\n';
            if (r.creditosDisponibles >= 0) std::cerr << "Créditos disponibles: " << r.creditosDisponibles << '\n';
        } else {
            std::cerr << "Error HTTP " << r.status << " (" << r.error << "): " << r.mensaje << '\n';
            salida = 1;
        }
    } catch (const std::invalid_argument& e) {
        std::cerr << e.what() << '\n';
        salida = 2;
    }
    curl_global_cleanup();
    return salida;
}
