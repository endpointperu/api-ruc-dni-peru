# Postman

Colección lista para probar todas las consultas de la API de endpoint.pe sin escribir código. También se importa en Insomnia, Bruno y Hoppscotch.

## Importar

1. En Postman: **Import** → arrastra `endpoint-pe.postman_collection.json` y `endpoint-pe.postman_environment.json`.
2. Selecciona el entorno **endpoint.pe** (arriba a la derecha) y pega tu API key en la variable `api_key`. Créala gratis en https://app.endpoint.pe/panel/api-keys.
3. Abre cualquier petición y pulsa **Send**. La autenticación `Bearer {{api_key}}` ya está configurada en la colección.

## Qué incluye

| Carpeta | Peticiones |
|---|---|
| Empresas (SUNAT) | Consulta RUC, establecimientos anexos, representantes legales, trabajadores por periodo, buscar RUC por razón social |
| Identidad (RENIEC) | Consulta DNI |
| Finanzas y ubicación | Tipo de cambio SUNAT, ubigeo por código, listar departamentos, provincias y distritos, ubigeo por nombres |

Las variables `ruc`, `dni` y `ubigeo` del entorno traen valores de ejemplo; cámbialos por los tuyos. Cada petición incluye una prueba que verifica el envoltorio `{success, message, data, meta}` y escribe en la consola los créditos que quedan (`X-Credits-Remaining`).

Para generar código en tu lenguaje desde Postman: abre la petición → **Code** (`</>`) a la derecha → elige el lenguaje. O usa directamente los ejemplos de este repositorio.
