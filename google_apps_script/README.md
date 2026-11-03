# Google Sheets (Apps Script)

Consulta RUC, DNI, tipo de cambio SUNAT y ubigeo desde las celdas de Google Sheets con fórmulas como `=CONSULTAR_RUC(A2)`. Acepta rangos completos (`=CONSULTAR_RUC(A2:A200)`) y guarda las respuestas en caché para no gastar créditos al recalcular.

## Instalación

1. Abre tu hoja de cálculo y entra a **Extensiones → Apps Script**.
2. Borra el contenido de `Código.gs`, pega el de [`Code.gs`](Code.gs) y guarda.
3. En **Configuración del proyecto** (icono de engranaje) → **Propiedades del script** → **Agregar propiedad**: nombre `ENDPOINT_API_KEY`, valor tu clave `ep_live_…` (créala gratis en https://app.endpoint.pe/panel/api-keys).
4. Vuelve a la hoja. La primera vez que uses una fórmula, Google te pedirá autorizar el script para conectarse a servicios externos.

## Fórmulas

| Fórmula | Devuelve |
|---|---|
| `=CONSULTAR_RUC(A2)` | Razón social |
| `=CONSULTAR_RUC(A2; "estado")` | `ACTIVO`, `BAJA DEFINITIVA`… |
| `=CONSULTAR_RUC(A2; "condicion")` | `HABIDO` o `NO HABIDO` |
| `=CONSULTAR_RUC(A2; "direccion_completa")` | Domicilio fiscal con departamento, provincia y distrito |
| `=CONSULTAR_RUC(A2:A200; "estado")` | El estado de toda la columna, en una sola fórmula |
| `=CONSULTAR_DNI(B2)` | Nombre completo |
| `=CONSULTAR_DNI(B2; "apellido_paterno")` | Apellido paterno (también `apellido_materno`, `nombres`, `ruc`) |
| `=TIPO_CAMBIO_SUNAT("venta")` | Tipo de cambio venta de hoy (también `"compra"` y `"fecha"`) |
| `=UBIGEO_NOMBRE("150101"; "distrito")` | Distrito (también `"provincia"`, `"departamento"`) |
| `=BUSCAR_RUC("superintendencia aduanas")` | RUC de la primera coincidencia |

Cualquier campo de la [referencia de la API](https://endpoint.pe/docs/apis/ruc) sirve como segundo argumento. Si el dato no existe, la celda muestra `Error 404 (no_encontrado): …`; si quedaste sin créditos, `Error 402 (sin_creditos): …`.

## Desde tus propios scripts

Las funciones `consultarRuc()`, `consultarDni()`, `tipoCambio()`, `consultarUbigeo()`, `buscarEmpresas()`, `anexos()`, `representantes()` y `trabajadores()` devuelven el objeto `data` completo, para usarlo en automatizaciones (por ejemplo, un disparador que valide los RUC nuevos de un formulario):

```js
function validarProveedoresNuevos() {
  const hoja = SpreadsheetApp.getActiveSheet();
  const filas = hoja.getRange('A2:C').getValues();
  filas.forEach((fila, i) => {
    if (fila[0] && !fila[1]) {
      try {
        const ficha = consultarRuc(fila[0]);
        hoja.getRange(i + 2, 2, 1, 2).setValues([[ficha.razon_social, ficha.estado]]);
      } catch (e) {
        hoja.getRange(i + 2, 2).setValue(e.message); // Error 404 (no_encontrado): …
      }
    }
  });
}
```

## Consejos

- Cuando termines de validar una lista, convierte las fórmulas en valores (copiar → pegar solo valores). Las fórmulas se recalculan al abrir la hoja y, aunque la caché dura 6 horas, después volverían a consultar.
- Las funciones personalizadas tienen un límite de 30 segundos por celda; para miles de filas usa la función `validarProveedoresNuevos()` de arriba con un disparador.

Guía completa: [Consultar RUC desde Google Sheets](https://endpoint.pe/blog/consultar-ruc-desde-google-sheets).
