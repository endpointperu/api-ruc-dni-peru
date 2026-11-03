# C++

Consulta la API de endpoint.pe desde C++17 con libcurl. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores, con timeout y reintentos ante fallos de red o 5xx.

## Requisitos

- Un compilador C++17 (g++ 7+, clang 5+, MSVC 2017+) y libcurl con soporte TLS.
  - Debian/Ubuntu: `sudo apt install build-essential libcurl4-openssl-dev`
  - macOS: libcurl viene con el sistema (`xcode-select --install`).
  - Windows: [vcpkg](https://vcpkg.io/) `vcpkg install curl`.

## Compilar y ejecutar

```bash
g++ -std=c++17 consulta.cpp -o consulta -lcurl

export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

./consulta ruc 20131312955
./consulta dni 45871236
./consulta tipo-cambio
./consulta ubigeo 150101
./consulta empresas "superintendencia aduanas"
./consulta anexos 20131312955
./consulta representantes 20131312955
./consulta trabajadores 20131312955
```

El programa imprime el JSON completo y devuelve 0 si la API respondió 200. Ante un error muestra el código HTTP, el campo `error` y el `message`, y devuelve 1.

## Leer los campos

La clase `EndpointPe` devuelve la respuesta cruda en `Respuesta::cuerpo`. Para convertirla a objetos usa [nlohmann/json](https://github.com/nlohmann/json) (un solo archivo de cabecera):

```cpp
#include <nlohmann/json.hpp>

auto r = api.ruc("20131312955");
if (r.status == 200) {
    auto json = nlohmann::json::parse(r.cuerpo);
    const auto& data = json["data"];
    std::cout << data["razon_social"].get<std::string>() << " · " << data["estado"].get<std::string>() << '\n';
    if (!data["nombre_comercial"].is_null()) {
        std::cout << data["nombre_comercial"].get<std::string>() << '\n';
    }
}
```

Si tu proyecto usa Qt, `QNetworkAccessManager` y `QJsonDocument` cumplen el mismo papel; basta con la cabecera `Authorization: Bearer …`.
