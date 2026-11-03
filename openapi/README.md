# OpenAPI

`endpoint-pe-v1.yaml` describe la API v1 de endpoint.pe en formato OpenAPI 3.1: rutas, parámetros, esquemas de cada respuesta, códigos de error y autenticación.

## Para qué sirve

- **Generar un cliente** en tu lenguaje con [OpenAPI Generator](https://openapi-generator.tech/): `openapi-generator-cli generate -i openapi/endpoint-pe-v1.yaml -g typescript-fetch -o cliente/` (también `python`, `php`, `java`, `csharp`, `go`, `kotlin`, `swift5`, `dart`, `ruby`, `rust`…).
- **Probarla desde el navegador** importándola en [Swagger Editor](https://editor.swagger.io/), Insomnia, Bruno o Postman (Importar → archivo).
- **Validar tus integraciones** con herramientas como Prism (mock server) o Schemathesis.
- **Darle contexto a un asistente de IA** (Copilot, Cursor, ChatGPT): pégale el archivo y pídele el cliente que necesites.

La referencia completa, con explicaciones y guías, está en https://endpoint.pe/docs.
