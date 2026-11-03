/*
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde C.
 *
 * Dependencia: libcurl (en Debian/Ubuntu: sudo apt install libcurl4-openssl-dev).
 * Compilar:    gcc consulta.c -o consulta -lcurl
 *
 * Uso:
 *   export ENDPOINT_API_KEY=ep_live_...
 *   ./consulta ruc 20131312955
 *   ./consulta dni 45871236
 *   ./consulta tipo-cambio
 *   ./consulta ubigeo 150101
 *   ./consulta empresas "superintendencia aduanas"
 *   ./consulta anexos 20131312955
 *   ./consulta representantes 20131312955
 *   ./consulta trabajadores 20131312955
 *
 * El programa imprime el JSON de la respuesta tal cual llega. Para leer los campos desde C
 * usa una biblioteca como cJSON o Jansson (ver README); aquí solo se extraen `error` y
 * `message` para informar los fallos.
 *
 * Documentación: https://endpoint.pe/docs
 */

#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BASE_URL_POR_DEFECTO "https://api.endpoint.pe/v1"
#define TIMEOUT_SEGUNDOS 15L

struct buffer {
    char *datos;
    size_t tam;
};

static size_t escribir(void *contenido, size_t tam, size_t n, void *destino)
{
    size_t total = tam * n;
    struct buffer *b = destino;
    char *nuevo = realloc(b->datos, b->tam + total + 1);
    if (nuevo == NULL) {
        return 0;
    }
    b->datos = nuevo;
    memcpy(b->datos + b->tam, contenido, total);
    b->tam += total;
    b->datos[b->tam] = '\0';
    return total;
}

static const char *base_url(void)
{
    const char *v = getenv("ENDPOINT_BASE_URL");
    return (v != NULL && v[0] != '\0') ? v : BASE_URL_POR_DEFECTO;
}

/*
 * GET a `ruta` (por ejemplo "/ruc/20131312955"). Si `q` no es NULL se agrega codificado como
 * ?q=... Devuelve el código HTTP (0 si falló la conexión) y deja el cuerpo en *cuerpo, que el
 * llamador debe liberar con free().
 */
static long consultar(const char *api_key, const char *ruta, const char *q, char **cuerpo)
{
    CURL *curl = curl_easy_init();
    if (curl == NULL) {
        return 0;
    }

    char url[1024];
    if (q != NULL) {
        char *codificado = curl_easy_escape(curl, q, 0);
        snprintf(url, sizeof url, "%s%s?q=%s", base_url(), ruta, codificado ? codificado : "");
        curl_free(codificado);
    } else {
        snprintf(url, sizeof url, "%s%s", base_url(), ruta);
    }

    char autorizacion[256];
    snprintf(autorizacion, sizeof autorizacion, "Authorization: Bearer %s", api_key);
    struct curl_slist *cabeceras = NULL;
    cabeceras = curl_slist_append(cabeceras, autorizacion);
    cabeceras = curl_slist_append(cabeceras, "Accept: application/json");

    struct buffer b = {NULL, 0};
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, cabeceras);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "endpoint-pe-ejemplos/c");
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, TIMEOUT_SEGUNDOS);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, escribir);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &b);

    long status = 0;
    CURLcode rc = curl_easy_perform(curl);
    if (rc == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    } else {
        fprintf(stderr, "No se pudo conectar con la API: %s\n", curl_easy_strerror(rc));
    }

    curl_slist_free_all(cabeceras);
    curl_easy_cleanup(curl);
    *cuerpo = b.datos;
    return status;
}

/*
 * Copia en `salida` el valor de texto de un campo de primer nivel ("error", "message").
 * Devuelve 1 si lo encontró. No resuelve secuencias de escape: es solo para mostrar mensajes.
 */
static int campo(const char *json, const char *nombre, char *salida, size_t tam)
{
    char clave[64];
    snprintf(clave, sizeof clave, "\"%s\"", nombre);
    const char *p = json ? strstr(json, clave) : NULL;
    if (p == NULL) {
        return 0;
    }
    p = strchr(p + strlen(clave), ':');
    if (p == NULL) {
        return 0;
    }
    p++;
    while (*p == ' ') {
        p++;
    }
    if (*p != '"') {
        return 0;
    }
    p++;
    size_t i = 0;
    while (*p != '\0' && *p != '"' && i + 1 < tam) {
        if (*p == '\\' && p[1] != '\0') {
            p++;
        }
        salida[i++] = *p++;
    }
    salida[i] = '\0';
    return 1;
}

static void uso(FILE *f)
{
    fputs("Uso: ./consulta <comando> [dato]\n\n"
          "  ruc <ruc>              Ficha del contribuyente (SUNAT)\n"
          "  dni <dni>              Nombres y apellidos del titular (RENIEC)\n"
          "  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)\n"
          "  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo\n"
          "  empresas <texto>       Buscar el RUC de una empresa por su razón social\n"
          "  anexos <ruc>           Establecimientos anexos de un RUC\n"
          "  representantes <ruc>   Representantes legales de un RUC\n"
          "  trabajadores <ruc>     Trabajadores declarados por periodo\n\n"
          "La API key se lee de la variable de entorno ENDPOINT_API_KEY.\n"
          "Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys\n",
          f);
}

int main(int argc, char **argv)
{
    const char *comando = argc > 1 ? argv[1] : "";
    const char *dato = argc > 2 ? argv[2] : "";
    if (comando[0] == '\0' || strcmp(comando, "-h") == 0 || strcmp(comando, "--help") == 0 || strcmp(comando, "ayuda") == 0) {
        uso(stdout);
        return 0;
    }

    const char *api_key = getenv("ENDPOINT_API_KEY");
    if (api_key == NULL || api_key[0] == '\0') {
        fputs("Falta la API key: export ENDPOINT_API_KEY=ep_live_...\n", stderr);
        return 2;
    }

    /* comando -> plantilla de ruta (%s = dato). NULL en plantilla = usa ?q= */
    static const struct {
        const char *nombre;
        const char *plantilla;
        int necesita_dato;
    } comandos[] = {
        {"ruc", "/ruc/%s", 1},
        {"dni", "/dni/%s", 1},
        {"tipo-cambio", "/tipo-cambio", 0},
        {"ubigeo", "/ubigeo/%s", 1},
        {"empresas", "/empresas", 1},
        {"anexos", "/ruc/%s/anexos", 1},
        {"representantes", "/ruc/%s/representantes", 1},
        {"trabajadores", "/ruc/%s/trabajadores", 1},
    };
    size_t total = sizeof comandos / sizeof comandos[0];
    size_t k;
    for (k = 0; k < total; k++) {
        if (strcmp(comando, comandos[k].nombre) == 0) {
            break;
        }
    }
    if (k == total) {
        fprintf(stderr, "Comando desconocido: %s\n\n", comando);
        uso(stderr);
        return 2;
    }
    if (comandos[k].necesita_dato && dato[0] == '\0') {
        fprintf(stderr, "El comando '%s' necesita un dato.\n", comando);
        return 2;
    }
    /* El dato de la ruta solo admite dígitos (RUC, DNI, ubigeo); evita inyectar otros caracteres. */
    if (strcmp(comando, "empresas") != 0) {
        for (const char *c = dato; *c != '\0'; c++) {
            if (*c < '0' || *c > '9') {
                fprintf(stderr, "El dato debe contener solo dígitos.\n");
                return 2;
            }
        }
    }

    curl_global_init(CURL_GLOBAL_DEFAULT);

    char ruta[256];
    long status;
    char *cuerpo = NULL;
    if (strcmp(comando, "empresas") == 0) {
        status = consultar(api_key, "/empresas", dato, &cuerpo);
    } else {
        snprintf(ruta, sizeof ruta, comandos[k].plantilla, dato);
        status = consultar(api_key, ruta, NULL, &cuerpo);
    }

    int salida = 0;
    if (status == 200) {
        puts(cuerpo);
    } else {
        char error[64] = "error", mensaje[256] = "Respuesta inesperada";
        campo(cuerpo, "error", error, sizeof error);
        campo(cuerpo, "message", mensaje, sizeof mensaje);
        if (status != 0) {
            fprintf(stderr, "Error HTTP %ld (%s): %s\n", status, error, mensaje);
        }
        salida = 1;
    }

    free(cuerpo);
    curl_global_cleanup();
    return salida;
}
