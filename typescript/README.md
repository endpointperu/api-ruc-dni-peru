# TypeScript

Cliente de la API de endpoint.pe con `fetch` y tipos para cada respuesta (`Ruc`, `Dni`, `TipoCambio`, `Ubigeo`, `Empresas`, `Anexos`, `Representantes`, `Trabajadores`). Sin dependencias en tiempo de ejecución.

## Requisitos

- Node.js 18 o superior. Para ejecutar el `.ts` directamente: Node.js 22.6+ (`node consulta.ts`) o [`tsx`](https://tsx.is/) (`npx tsx consulta.ts`). También funciona con Bun (`bun consulta.ts`) y Deno (`deno run --allow-net --allow-env consulta.ts`).
- TypeScript 4.5 o superior si lo compilas con `tsc`.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

npx tsx consulta.ts ruc 20131312955
npx tsx consulta.ts dni 45871236
npx tsx consulta.ts tipo-cambio
npx tsx consulta.ts ubigeo 150101
npx tsx consulta.ts empresas "superintendencia aduanas"
npx tsx consulta.ts anexos 20131312955
npx tsx consulta.ts representantes 20131312955
npx tsx consulta.ts trabajadores 20131312955
```

Para compilarlo: `npx tsc --strict --target es2022 --module nodenext consulta.ts` genera `consulta.js`.

## Usar en tu proyecto

```ts
import { EndpointPe, EndpointError, type Ruc } from './consulta';

const api = new EndpointPe(); // lee ENDPOINT_API_KEY; también acepta new EndpointPe('ep_live_...')

try {
  const ficha: Ruc = await api.ruc('20131312955');
  console.log(ficha.razon_social, ficha.estado, ficha.condicion);
} catch (err) {
  if (err instanceof EndpointError && err.error === 'no_encontrado') {
    console.log('RUC no inscrito');
  } else {
    throw err;
  }
}

const tc = await api.tipoCambio();
console.log(tc.fecha, tc.compra, tc.venta);
```

Cada método devuelve el objeto `data` tipado y actualiza `creditosDisponibles`. Los errores llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

Los tipos están declarados con `null` donde la fuente puede no tener el dato (por ejemplo `nombre_comercial` o `cantidad_trabajadores`); trata `null` como "sin información".

## Next.js, NestJS y Angular

La consulta debe hacerse en el servidor (route handler, server action, servicio de Nest). En Angular, llama a tu propio backend, que a su vez consulta a endpoint.pe: la API key nunca debe estar en el código que llega al navegador.
