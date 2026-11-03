# Excel (VBA)

Consulta RUC, DNI, tipo de cambio SUNAT y ubigeo directamente desde las celdas de Excel con fórmulas como `=CONSULTAR_RUC(A2)`. Sin complementos: un módulo VBA que usa `MSXML2.ServerXMLHTTP`. Pensado para contadores, administradores y áreas de ventas que validan clientes y proveedores en hojas de cálculo.

## Requisitos

- Excel 2010 o superior en Windows. (En Excel para Mac no existe MSXML; usa la alternativa con Power Query de abajo).

## Instalación

1. Abre tu libro y pulsa `Alt+F11` para abrir el editor de VBA.
2. Menú **Archivo → Importar archivo…** y elige `EndpointPe.bas`.
3. Guarda el libro como **Libro de Excel habilitado para macros (.xlsm)**.
4. Define tu API key de una de estas dos formas:
   - **Variable de entorno** `ENDPOINT_API_KEY` (Panel de control → Sistema → Variables de entorno). Es la opción recomendada: la clave no viaja con el archivo.
   - O pégala en la constante `API_KEY_LOCAL` al inicio del módulo. Si lo haces, no compartas el archivo.

Crea tu clave gratis en https://app.endpoint.pe/panel/api-keys.

## Fórmulas

| Fórmula | Devuelve |
|---|---|
| `=CONSULTAR_RUC(A2)` | Razón social |
| `=CONSULTAR_RUC(A2; "estado")` | `ACTIVO`, `BAJA DEFINITIVA`… |
| `=CONSULTAR_RUC(A2; "condicion")` | `HABIDO` o `NO HABIDO` |
| `=CONSULTAR_RUC(A2; "direccion_completa")` | Domicilio fiscal con departamento, provincia y distrito |
| `=CONSULTAR_RUC(A2; "cantidad_trabajadores")` | Trabajadores del último periodo declarado |
| `=CONSULTAR_DNI(B2)` | Nombre completo |
| `=CONSULTAR_DNI(B2; "apellido_paterno")` | Apellido paterno (también `apellido_materno`, `nombres`, `ruc`) |
| `=TIPO_CAMBIO_SUNAT("venta")` | Tipo de cambio venta de hoy (también `"compra"` y `"fecha"`) |
| `=UBIGEO_NOMBRE("150101"; "distrito")` | Distrito (también `"provincia"`, `"departamento"`) |
| `=BUSCAR_RUC("superintendencia aduanas")` | RUC de la primera coincidencia |

Cualquier campo de la [referencia de la API](https://endpoint.pe/docs/apis/ruc) sirve como segundo argumento. Si el dato no existe (RUC no inscrito, DNI sin registro) la celda muestra `Error 404 (no_encontrado): …`; si quedaste sin créditos, `Error 402 (sin_creditos): …`.

## Consejos

- Las respuestas se guardan en memoria mientras el libro está abierto, así recalcular la hoja no repite consultas. Para forzar una consulta nueva, cierra y vuelve a abrir el libro.
- Para listas largas, convierte las fórmulas en valores (copiar → pegar valores) cuando termines: cada consulta con resultado descuenta un crédito y no tiene sentido repetirla.
- Desde VBA puedes usar `EndpointGet` y `ValorJson` en tus propias macros, o [VBA-JSON](https://github.com/VBA-tools/VBA-JSON) para recorrer listas (anexos, representantes, periodos).

## Alternativa sin macros: Power Query

Excel 2016+ y Microsoft 365 (Windows y Mac) pueden consultar la API sin VBA. En **Datos → Obtener datos → Desde otras fuentes → Consulta en blanco**, pega en el editor avanzado:

```powerquery
let
    Ruc = "20131312955",
    Respuesta = Json.Document(Web.Contents("https://api.endpoint.pe/v1/ruc/" & Ruc, [Headers = [Authorization = "Bearer ep_live_...", Accept = "application/json"]])),
    Datos = Respuesta[data]
in
    Record.ToTable(Datos)
```

Para validar una columna de RUC, convierte el bloque en una función con parámetro `Ruc` e invócala desde la tabla con **Agregar columna → Invocar función personalizada**.
