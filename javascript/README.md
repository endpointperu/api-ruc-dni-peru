# JavaScript (Node.js, Bun y Deno)

Cliente mínimo de la API de endpoint.pe con `fetch`, sin dependencias. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Node.js 18 o superior (trae `fetch` y `AbortSignal.timeout`). También funciona con Bun 1+ y Deno 2+.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

node consulta.mjs ruc 20131312955
node consulta.mjs dni 45871236
node consulta.mjs tipo-cambio
node consulta.mjs ubigeo 150101
node consulta.mjs empresas "superintendencia aduanas"
node consulta.mjs anexos 20131312955
node consulta.mjs representantes 20131312955
node consulta.mjs trabajadores 20131312955
```

Con Bun: `bun consulta.mjs ruc 20131312955`. Con Deno: `deno run --allow-net --allow-env consulta.mjs ruc 20131312955`.

## Usar en tu proyecto

```js
import { EndpointPe, EndpointError, esRucValido } from './consulta.mjs';

const api = new EndpointPe(); // lee ENDPOINT_API_KEY; también acepta new EndpointPe('ep_live_...')

if (esRucValido('20131312955')) {           // valida el formato antes de gastar una llamada
  try {
    const ficha = await api.ruc('20131312955');
    console.log(ficha.razon_social, ficha.estado, ficha.condicion);
  } catch (err) {
    if (err instanceof EndpointError && err.error === 'no_encontrado') {
      console.log('RUC no inscrito');
    } else {
      throw err;
    }
  }
}

const tc = await api.tipoCambio();
console.log(tc.fecha, tc.compra, tc.venta);
console.log('Créditos disponibles:', api.creditosDisponibles);
```

Cada método devuelve el objeto `data` de la respuesta y actualiza `creditosDisponibles`. Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Express, Next.js y NestJS

Haz la consulta **en el servidor** (una ruta de API, un server action, un servicio de Nest) y entrega al navegador solo el resultado: la API key nunca debe llegar al frontend. Si varios usuarios consultan los mismos RUC o DNI, guarda los resultados en caché unas horas.

Guía relacionada: [Consultar RUC con Node.js](https://endpoint.pe/blog/consultar-ruc-con-nodejs).
