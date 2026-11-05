<div align="center">

<a href="https://endpoint.pe">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-oscuro.png">
    <img src="assets/logo-claro.png" alt="endpoint.pe" width="269">
  </picture>
</a>

# API de consulta RUC, DNI y tipo de cambio del Perú

**Ejemplos oficiales de [endpoint.pe](https://endpoint.pe) en 26 lenguajes para consultar SUNAT, RENIEC, tipo de cambio y ubigeo desde tu sistema.**

[![Sitio web](https://img.shields.io/badge/endpoint.pe-sitio_web-533AFD?style=for-the-badge)](https://endpoint.pe)
[![Documentación](https://img.shields.io/badge/documentaci%C3%B3n-endpoint.pe%2Fdocs-533AFD?style=for-the-badge)](https://endpoint.pe/docs)
[![Cuenta gratis](https://img.shields.io/badge/cuenta_gratis-150_consultas_al_mes-0f172a?style=for-the-badge)](https://app.endpoint.pe/registro)
[![Lenguajes](https://img.shields.io/badge/lenguajes-26-0f172a?style=for-the-badge)](#ejemplos-por-lenguaje)
[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-0f172a?style=for-the-badge)](LICENSE)


</div>

Una sola API REST en JSON para **consultar RUC** (ficha SUNAT, anexos, representantes legales, trabajadores y búsqueda por razón social), **consultar DNI** (nombres y apellidos de RENIEC), **tipo de cambio SUNAT** del día y **ubigeo** (departamento, provincia y distrito). Cada carpeta de este repositorio contiene un cliente completo y probado, listo para copiar a tu proyecto.

## Contenido

- [¿Qué puedes consultar?](#qué-puedes-consultar)
- [Empieza en 3 pasos](#empieza-en-3-pasos)
- [Cómo responde la API](#cómo-responde-la-api)
- [Ejemplos por lenguaje](#ejemplos-por-lenguaje)
- [Sin programar: Excel, Google Sheets, Postman y OpenAPI](#sin-programar-excel-google-sheets-postman-y-openapi)
- [Errores](#errores)
- [Créditos y precios](#créditos-y-precios)
- [Casos de uso](#casos-de-uso)
- [Buenas prácticas](#buenas-prácticas)
- [Preguntas frecuentes](#preguntas-frecuentes)
- [Recursos](#recursos)
- [Contribuir](#contribuir)

## ¿Qué puedes consultar?

| API | Qué devuelve | Fuente | Endpoint |
|---|---|---|---|
| [Consulta RUC](https://endpoint.pe/docs/apis/ruc) | Razón social, nombre comercial, tipo de contribuyente, estado, condición, domicilio fiscal con ubigeo, padrones (retención, percepción, buen contribuyente) y cantidad de trabajadores, locales y representantes | SUNAT | `GET /v1/ruc/{ruc}` |
| [Consulta DNI](https://endpoint.pe/docs/apis/dni) | Nombres, apellidos, dígito verificador y RUC de persona natural. Solo identidad: no devuelve domicilio ni fecha de nacimiento | RENIEC | `GET /v1/dni/{dni}` |
| [Tipo de cambio](https://endpoint.pe/docs/apis/tipo-cambio) | Compra y venta del dólar más recientes publicadas por SUNAT, con su fecha | SUNAT | `GET /v1/tipo-cambio` |
| [Ubigeo](https://endpoint.pe/docs/apis/ubicacion) | Departamento, provincia y distrito de un código, o listas por nivel para formularios de dirección | INEI | `GET /v1/ubigeo/{codigo}` · `GET /v1/ubigeo?departamento=…` |
| [Razón social](https://endpoint.pe/docs/apis/razon-social) | Hasta 20 empresas que coinciden con un nombre, con RUC, estado y condición | SUNAT | `GET /v1/empresas?q={texto}` |
| [Establecimientos anexos](https://endpoint.pe/docs/apis/establecimientos) | Sucursales, depósitos y oficinas registradas, con dirección y actividad | SUNAT | `GET /v1/ruc/{ruc}/anexos` |
| [Representantes legales](https://endpoint.pe/docs/apis/representantes-legales) | Documento, nombre, cargo y fecha de nombramiento | SUNAT | `GET /v1/ruc/{ruc}/representantes` |
| [Trabajadores](https://endpoint.pe/docs/apis/trabajadores) | Trabajadores, pensionistas y prestadores de servicio declarados, por periodo mensual | SUNAT | `GET /v1/ruc/{ruc}/trabajadores` |
| [Carnet de extranjería](https://endpoint.pe/docs/apis/carnet-extranjeria) | Nombres y apellidos del titular (próximamente) | Migraciones | `GET /v1/ce/{numero}` |

El padrón de SUNAT se actualiza todos los días. Todas las consultas cuestan lo mismo: **1 crédito** cuando hay resultado, **0** cuando no lo hay.

## Empieza en 3 pasos

1. **Crea tu cuenta gratis** en [app.endpoint.pe/registro](https://app.endpoint.pe/registro). Incluye 150 consultas al mes que se renuevan solas, sin tarjeta.
2. **Genera una API key** en [API keys](https://app.endpoint.pe/panel/api-keys). Tiene la forma `ep_live_` + 40 caracteres y se muestra una sola vez.
3. **Haz tus primeras consultas** (reemplaza `ep_live_...` por tu clave).

### Consulta RUC

Ficha del contribuyente en SUNAT a partir del RUC:

```bash
curl https://api.endpoint.pe/v1/ruc/20131312955 \
  -H "Authorization: Bearer ep_live_..."
```

```json
{
  "success": true,
  "message": "Consulta exitosa",
  "data": {
    "ruc": "20131312955",
    "razon_social": "SUPERINTENDENCIA NACIONAL DE ADUANAS Y DE ADMINISTRACION TRIBUTARIA - SUNAT",
    "nombre_comercial": null,
    "tipo_contribuyente": "INSTITUCIONES PUBLICAS",
    "estado": "ACTIVO",
    "condicion": "HABIDO",
    "fecha_inscripcion": "1993-05-04",
    "fecha_inicio_actividades": "1988-06-09",
    "direccion": "AV. GARCILASO DE LA VEGA NRO. 1472",
    "direccion_completa": "AV. GARCILASO DE LA VEGA NRO. 1472, LIMA - LIMA - LIMA",
    "departamento": "LIMA",
    "provincia": "LIMA",
    "distrito": "LIMA",
    "ubigeo": "150101",
    "ubigeo_reniec": "140101",
    "es_agente_de_retencion": true,
    "es_agente_de_percepcion": false,
    "es_agente_de_percepcion_combustible": false,
    "es_buen_contribuyente": false,
    "cantidad_trabajadores": 12577,
    "cantidad_establecimientos": 349,
    "cantidad_representantes": 6
  },
  "meta": {
    "fuente": "SUNAT",
    "consultado_en": "2026-10-12T07:40:12Z",
    "creditos_cobrados": 1,
    "creditos_disponibles": 14621
  }
}
```

### Consulta DNI

Nombres y apellidos del titular a partir del DNI, con el mismo envoltorio (los datos de la respuesta son de ejemplo):

```bash
curl https://api.endpoint.pe/v1/dni/45871236 \
  -H "Authorization: Bearer ep_live_..."
```

```json
{
  "success": true,
  "message": "Consulta exitosa",
  "data": {
    "dni": "45871236",
    "digito_verificador": "6",
    "nombres": "MARÍA ELENA",
    "apellido_paterno": "QUISPE",
    "apellido_materno": "HUAMÁN",
    "nombre_completo": "MARÍA ELENA QUISPE HUAMÁN",
    "ruc": "10458712366"
  },
  "meta": {
    "fuente": "RENIEC",
    "consultado_en": "2026-10-12T07:40:12Z",
    "creditos_cobrados": 1,
    "creditos_disponibles": 14620
  }
}
```

### Las demás consultas

Tipo de cambio, ubigeo, razón social, anexos, representantes y trabajadores responden con el mismo envoltorio; cada una está descrita, con su ejemplo, en su [página de la documentación](https://endpoint.pe/docs).

¿Quieres verla funcionar antes de registrarte? En la portada de [endpoint.pe](https://endpoint.pe/#prueba) puedes consultar un RUC o un DNI en vivo. Y desde el panel, el [Playground](https://app.endpoint.pe/panel/playground) te muestra la respuesta, las cabeceras y el `curl` equivalente de cualquier consulta.

## Cómo responde la API

Toda respuesta de `/v1`, con éxito o con error, tiene la misma forma. Tu código solo necesita mirar `success` y, según el caso, `data` o `error`:

| Campo | Contenido |
|---|---|
| `success` | `true` si hubo resultado, `false` si no. |
| `message` | Texto en español que puedes mostrar tal cual. |
| `data` | El resultado (los campos dependen de cada API). `null` en los errores. |
| `error` | Solo en errores: código estable para tu programa (`no_encontrado`, `validacion`, `sin_creditos`…). |
| `meta` | `fuente`, `consultado_en` (UTC), `creditos_cobrados` y `creditos_disponibles`. |

Las cabeceras `X-Credits-Charged` y `X-Credits-Remaining` repiten los créditos de `meta` para que los leas sin parsear el cuerpo. Los textos llegan en UTF-8 y en mayúsculas, tal como los publican SUNAT y RENIEC; los números de documento y los códigos son cadenas (conservan los ceros a la izquierda) y `null` significa "sin dato". Detalle completo en [Formato de respuesta](https://endpoint.pe/docs/respuestas).

## Ejemplos por lenguaje

Todos los ejemplos siguen el mismo contrato, así puedes pasar de un lenguaje a otro sin sorpresas:

- Cubren las **ocho consultas** con la misma interfaz: `<comando> [dato]` (`ruc`, `dni`, `tipo-cambio`, `ubigeo`, `empresas`, `anexos`, `representantes`, `trabajadores`).
- Leen la clave de la variable de entorno **`ENDPOINT_API_KEY`**. Nada que editar en el código.
- Manejan la respuesta completa: `success`, `data`, `error`, `message` y `detalles`, con el código HTTP.
- Tienen **timeout** y **reintentos** solo ante errores de red o 5xx (nunca ante 404 o 422).
- **Sin dependencias** cuando el lenguaje lo permite. Cada carpeta tiene su `README.md` con requisitos, instalación y cómo integrarlo en tu proyecto (Laravel, Django, Spring, Rails, Next.js, Flutter…).
- Probados contra `https://api.endpoint.pe`.

| Lenguaje | Carpeta | Requisitos | Ejecutar |
|---|---|---|---|
| Bash y cURL | [`bash/`](bash) | bash 4+, curl | `./consulta.sh ruc 20131312955` |
| PowerShell | [`powershell/`](powershell) | PowerShell 5.1 o 7+ | `.\consulta.ps1 ruc 20131312955` |
| JavaScript (Node.js, Bun, Deno) | [`javascript/`](javascript) | Node.js 18+ | `node consulta.mjs ruc 20131312955` |
| TypeScript | [`typescript/`](typescript) | Node.js 18+ (`tsx`) o 22.6+ | `npx tsx consulta.ts ruc 20131312955` |
| Python | [`python/`](python) | Python 3.8+ | `python consulta.py ruc 20131312955` |
| PHP y Laravel | [`php/`](php) | PHP 7.4+ con cURL | `php consulta.php ruc 20131312955` |
| Java | [`java/`](java) | Java 11+ | `java EndpointPe.java ruc 20131312955` |
| Kotlin | [`kotlin/`](kotlin) | Kotlin 1.6+, JDK 11+ | `java -jar consulta.jar ruc 20131312955` |
| C# (.NET) | [`csharp/`](csharp) | .NET 6+ | `dotnet run -- ruc 20131312955` |
| VB.NET | [`vbnet/`](vbnet) | .NET 6+ | `dotnet run -- ruc 20131312955` |
| Go | [`go/`](go) | Go 1.21+ | `go run . ruc 20131312955` |
| Rust | [`rust/`](rust) | Rust 1.70+ | `cargo run -- ruc 20131312955` |
| Ruby y Rails | [`ruby/`](ruby) | Ruby 2.7+ | `ruby consulta.rb ruc 20131312955` |
| Swift | [`swift/`](swift) | Swift 5.7+ | `swift EndpointPe.swift ruc 20131312955` |
| Dart y Flutter | [`dart/`](dart) | Dart 3+ | `dart run consulta.dart ruc 20131312955` |
| C | [`c/`](c) | C99, libcurl | `./consulta ruc 20131312955` |
| C++ | [`cpp/`](cpp) | C++17, libcurl | `./consulta ruc 20131312955` |
| Visual FoxPro 9 | [`visual_foxpro/`](visual_foxpro) | VFP 9, Windows con TLS 1.2 | `DO consulta WITH "ruc", "20131312955"` |
| Delphi (Object Pascal) | [`delphi/`](delphi) | Delphi 10.3+ | `EndpointPe ruc 20131312955` |
| Excel (VBA) | [`vba/`](vba) | Excel 2010+ en Windows | `=CONSULTAR_RUC(A2)` |
| Google Sheets (Apps Script) | [`google_apps_script/`](google_apps_script) | Cuenta de Google | `=CONSULTAR_RUC(A2)` |
| R | [`r/`](r) | R 4.1+, httr2 | `Rscript consulta.R ruc 20131312955` |
| Perl | [`perl/`](perl) | Perl 5.14+ | `perl consulta.pl ruc 20131312955` |
| Lua | [`lua/`](lua) | Lua 5.1+, luasec, dkjson | `lua consulta.lua ruc 20131312955` |
| Scala 3 | [`scala/`](scala) | Scala CLI, JDK 11+ | `scala-cli run EndpointPe.scala -- ruc 20131312955` |
| Elixir y Phoenix | [`elixir/`](elixir) | Elixir 1.14+ | `elixir consulta.exs ruc 20131312955` |

¿Falta tu lenguaje o framework? [Pídelo](../../issues/new?template=nuevo-lenguaje.yml) o [contribuye](CONTRIBUTING.md).

## Sin programar: Excel, Google Sheets, Postman y OpenAPI

- **Excel**: importa el módulo de [`vba/`](vba) y escribe `=CONSULTAR_RUC(A2)` o `=CONSULTAR_DNI(B2)` en cualquier celda. También hay una alternativa con Power Query, sin macros.
- **Google Sheets**: pega el script de [`google_apps_script/`](google_apps_script) y usa las mismas fórmulas, incluso sobre rangos completos (`=CONSULTAR_RUC(A2:A200)`).
- **Postman, Insomnia, Bruno**: importa la colección de [`postman/`](postman) con todas las consultas y la autenticación configurada.
- **OpenAPI 3.1**: [`openapi/endpoint-pe-v1.yaml`](openapi/endpoint-pe-v1.yaml) describe la API completa. Sirve para generar clientes con OpenAPI Generator, probar desde Swagger Editor o darle contexto a tu asistente de IA.

## Errores

Usa el código HTTP para decidir qué hacer y el campo `error` para distinguir el caso. Solo las respuestas 200 descuentan créditos.

| HTTP | `error` | Qué significa |
|---|---|---|
| 200 | — | Consulta con resultado. Descuenta 1 crédito. |
| 401 | `token_invalido` | Falta la API key, no usa `Bearer` o no es válida. |
| 402 | `sin_creditos` | No queda saldo en ninguna bolsa. |
| 403 | `token_inactivo` · `cuenta_suspendida` | La clave está desactivada o revocada, o la cuenta suspendida. |
| 404 | `no_encontrado` | El dato no existe en la fuente (RUC no inscrito, DNI sin registro, búsqueda sin coincidencias). No es un fallo: trátalo como "sin resultado" y no lo reintentes. |
| 422 | `validacion` | Formato incorrecto. `detalles` indica el campo y el motivo. |
| 429 | `demasiadas_peticiones` | Más de 20 peticiones por segundo desde una misma IP. Espera lo que indique `Retry-After`. |
| 501 | `no_disponible` | La fuente de esa API aún no está conectada (hoy, carnet de extranjería). |
| 502 | `error_fuente` | La fuente no respondió. Reintenta con espera creciente. |

Ejemplo de error de validación:

```json
{
  "success": false,
  "message": "Revisa los datos enviados.",
  "error": "validacion",
  "data": null,
  "detalles": {
    "ruc": "RUC inválido: deben ser 11 dígitos con dígito verificador correcto."
  },
  "meta": { "consultado_en": "2026-10-12T08:41:49Z" }
}
```

Guía completa: [Errores](https://endpoint.pe/docs/errores).

## Créditos y precios

Cada consulta con resultado descuenta **1 crédito**, en todas las APIs; las consultas sin resultado y los errores no descuentan nada. Hay dos bolsas: la de tu **plan** (se renueva cada mes, o al año con todos los créditos de una vez) y la **prepago** (paquetes que no vencen).

| Plan | Consultas | Precio mensual (sin IGV) |
|---|---|---|
| Gratis | 150 al mes | S/ 0 |
| Básico | 20 000 al mes | S/ 15 |
| Profesional | 50 000 al mes | S/ 25 |
| Enterprise | 150 000 al mes | S/ 45 |

El plan anual cuesta 10 meses (dos gratis) y entrega los créditos de todo el año sin tope mensual. Paquetes prepago desde S/ 8 por 5 000 consultas. Precios, comparativa y paquetes en [endpoint.pe/pricing](https://endpoint.pe/pricing).

## Casos de uso

- **Facturación electrónica**: valida el RUC, el estado y la condición del cliente antes de emitir el comprobante, y completa la razón social y la dirección sin errores de tipeo. [Checklist para validar un cliente antes de facturar](https://endpoint.pe/blog/checklist-para-validar-un-cliente-antes-de-facturar).
- **Alta de clientes y proveedores en tu ERP o CRM**: ficha SUNAT, representantes legales, locales y tamaño de la empresa para la debida diligencia. [Representantes legales: cómo consultarlos](https://endpoint.pe/blog/representantes-legales-de-una-empresa-como-consultarlos).
- **Formularios que se completan solos**: el usuario escribe su DNI y aparecen sus nombres y apellidos. [Autocompletar nombres con el DNI](https://endpoint.pe/blog/autocompletar-nombres-con-el-dni-en-formularios).
- **Operaciones en dólares**: registra el tipo de cambio SUNAT del día automáticamente en tu sistema contable. [Automatizar el tipo de cambio diario en tu ERP](https://endpoint.pe/blog/automatizar-el-tipo-de-cambio-diario-en-tu-erp).
- **Direcciones consistentes**: selectores de departamento, provincia y distrito con ubigeo INEI y RENIEC. [Formularios de dirección en Perú](https://endpoint.pe/blog/formularios-de-direccion-en-peru-departamento-provincia-distrito).
- **Hojas de cálculo**: contadores y áreas comerciales que validan listas de RUC en Excel o Google Sheets sin programar. [Consultar RUC desde Google Sheets](https://endpoint.pe/blog/consultar-ruc-desde-google-sheets).

## Buenas prácticas

- **Valida antes de consultar.** RUC: 11 dígitos, empieza en 10, 15, 16, 17 o 20 y el último dígito es un verificador (módulo 11). DNI: 8 dígitos. Los ejemplos en Python, JavaScript, TypeScript, PHP, Ruby y Dart incluyen la función de validación. [Cómo validar un RUC con el dígito verificador](https://endpoint.pe/blog/como-validar-un-ruc-digito-verificador).
- **Guarda en caché lo que cambia poco.** Los datos de un RUC o un DNI cambian rara vez; el tipo de cambio es un valor por día; la tabla de ubigeo es estable. Ahorras créditos y tu sistema sigue respondiendo si la API no está al alcance un momento.
- **Reintenta solo lo que tiene sentido.** Errores de red y 5xx, con espera creciente y un máximo de intentos. Nunca un 404 ni un 422: el resultado será el mismo.
- **Consulta desde tu servidor.** La API key nunca debe llegar al navegador ni a una app móvil: cualquiera podría leerla. Una clave por sistema o entorno, guardada en variables de entorno o en tu gestor de secretos.
- **Vigila tu saldo.** Lee `X-Credits-Remaining` y avisa a tu equipo antes de llegar a cero; en el panel ves el consumo por día, por API y por clave.
- **Cuida los datos personales.** La consulta de DNI y la de representantes devuelven nombres de personas. Úsalas con una finalidad legítima, guarda solo lo necesario y protégelo según la Ley N.º 29733. [Guía para desarrolladores](https://endpoint.pe/blog/ley-de-proteccion-de-datos-personales-para-desarrolladores).
- **Prepárate para campos nuevos.** Lee `data` por nombre de campo e ignora los que no conozcas; así una respuesta con campos adicionales no rompe tu integración. La versión de la API va en la ruta (`/v1`).

## Preguntas frecuentes

**¿Cómo consulto un RUC desde mi sistema?**
Con una petición `GET https://api.endpoint.pe/v1/ruc/{ruc}` y la cabecera `Authorization: Bearer <tu API key>`. Elige tu lenguaje en la [tabla de ejemplos](#ejemplos-por-lenguaje), copia el archivo y ejecútalo.

**¿La API de DNI devuelve la dirección o la fecha de nacimiento?**
No. Devuelve solo identidad: nombres, apellidos, dígito verificador y el RUC de persona natural si lo tiene. Es suficiente para validar y autocompletar formularios sin exponer más datos de los necesarios.

**¿Es gratis?**
Sí para empezar: la cuenta gratuita incluye 150 consultas al mes que se renuevan solas, sin tarjeta. Cuando necesites más, hay planes desde S/ 15 al mes y paquetes prepago que no vencen.

**¿De dónde salen los datos?**
Del padrón de SUNAT (contribuyentes, anexos, representantes y trabajadores), que se actualiza todos los días; de RENIEC para la identidad; del tipo de cambio que publica SUNAT; y de la tabla de ubigeo del INEI con su equivalencia RENIEC. Cada respuesta indica la fuente en `meta.fuente`.

**¿Hay límite de peticiones?**
Tu saldo de créditos y un tope de 20 peticiones por segundo por dirección IP, más que suficiente para cualquier integración normal. Si lo superas recibes 429 y la cabecera `Retry-After`.

**¿Puedo usarla desde Excel o Google Sheets sin programar?**
Sí. Importa el módulo de [`vba/`](vba) en Excel o el script de [`google_apps_script/`](google_apps_script) en Google Sheets y usa fórmulas como `=CONSULTAR_RUC(A2)`.

**¿Puedo llamarla desde el navegador o desde una app móvil?**
No es recomendable: la API key quedaría expuesta. Haz la consulta desde tu backend (cualquiera de los ejemplos de servidor) y entrega al cliente solo el resultado.

**¿Qué pasa cuando el RUC o el DNI no existe?**
La API responde 404 con `error: "no_encontrado"` y no descuenta créditos. Trátalo como "sin resultado".

**¿Cómo pruebo sin escribir código?**
En la portada de [endpoint.pe](https://endpoint.pe/#prueba) puedes consultar un RUC o un DNI en vivo, y con tu cuenta tienes el [Playground](https://app.endpoint.pe/panel/playground) del panel y la [colección de Postman](postman).

## Recursos

- [Documentación](https://endpoint.pe/docs): primeros pasos, autenticación, formato de respuesta, errores, créditos y la referencia de cada API.
- [Blog](https://endpoint.pe/blog): guías sobre SUNAT, RENIEC, facturación electrónica, tipo de cambio y ubigeo para desarrolladores.
- [Precios](https://endpoint.pe/pricing) y [registro](https://app.endpoint.pe/registro).
- [Contacto](https://endpoint.pe/contact) · contacto@endpoint.pe

## Contribuir

Las correcciones y los lenguajes nuevos son bienvenidos. Lee [CONTRIBUTING.md](CONTRIBUTING.md) para conocer el contrato que siguen los ejemplos y abre un pull request. Para reportar un problema de seguridad, sigue [SECURITY.md](SECURITY.md); no lo publiques como issue.

## Licencia

Los ejemplos de este repositorio se publican bajo la [licencia MIT](LICENSE): úsalos, modifícalos y distribúyelos libremente. El uso de la API se rige por los [términos del servicio](https://endpoint.pe/terms) de endpoint.pe.

<div align="center">

Hecho en el Perú por [endpoint.pe](https://endpoint.pe) · Si te sirvió, deja una estrella ⭐

</div>
