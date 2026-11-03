# C

Consulta la API de endpoint.pe desde C con libcurl. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Un compilador C99 (gcc, clang o MSVC) y libcurl con soporte TLS.
  - Debian/Ubuntu: `sudo apt install build-essential libcurl4-openssl-dev`
  - macOS: libcurl viene con el sistema (`xcode-select --install`).
  - Windows: [vcpkg](https://vcpkg.io/) `vcpkg install curl`, o MSYS2 `pacman -S mingw-w64-x86_64-curl`.

## Compilar y ejecutar

```bash
gcc consulta.c -o consulta -lcurl

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

El programa imprime el JSON completo (`{"success": true, "message": "...", "data": {...}, "meta": {...}}`) y devuelve 0 si la API respondió 200. Ante un error muestra el código HTTP, el campo `error` y el `message`, y devuelve 1.

## Leer los campos

Para trabajar con la respuesta en C usa una biblioteca JSON. Con [cJSON](https://github.com/DaveGamble/cJSON):

```c
cJSON *raiz = cJSON_Parse(cuerpo);
cJSON *data = cJSON_GetObjectItemCaseSensitive(raiz, "data");
cJSON *razon = cJSON_GetObjectItemCaseSensitive(data, "razon_social");
if (cJSON_IsString(razon)) {
    printf("%s\n", razon->valuestring);
}
cJSON_Delete(raiz);
```

Recuerda que `null` en el JSON significa "sin dato" (por ejemplo `nombre_comercial` en muchos RUC), así que comprueba el tipo antes de leer cada campo.
