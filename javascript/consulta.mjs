#!/usr/bin/env node
/**
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde JavaScript.
 *
 * Sin dependencias: usa `fetch`, incluido en Node.js 18+, Bun y Deno.
 *
 * Uso desde la terminal:
 *   export ENDPOINT_API_KEY=ep_live_...
 *   node consulta.mjs ruc 20131312955
 *   node consulta.mjs dni 45871236
 *   node consulta.mjs tipo-cambio
 *   node consulta.mjs ubigeo 150101
 *   node consulta.mjs empresas "superintendencia aduanas"
 *   node consulta.mjs anexos 20131312955
 *   node consulta.mjs representantes 20131312955
 *   node consulta.mjs trabajadores 20131312955
 *
 * Uso desde tu código:
 *   import { EndpointPe, EndpointError } from './consulta.mjs';
 *   const api = new EndpointPe();            // lee ENDPOINT_API_KEY del entorno
 *   const ficha = await api.ruc('20131312955');
 *   console.log(ficha.razon_social, ficha.estado, api.creditosDisponibles);
 *
 * Documentación: https://endpoint.pe/docs
 */

import { pathToFileURL } from 'node:url';

const BASE_URL = process.env.ENDPOINT_BASE_URL ?? 'https://api.endpoint.pe/v1';
const TIMEOUT_MS = 15_000;
const REINTENTOS = 3; // solo ante errores de red o 5xx; nunca ante 404 o 422

/**
 * La API respondió con success=false. `error` es el código estable para comparar en tu
 * código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
 */
export class EndpointError extends Error {
  constructor(status, error, mensaje, detalles = {}) {
    super(`HTTP ${status} · ${error}: ${mensaje}`);
    this.name = 'EndpointError';
    this.status = status;
    this.error = error;
    this.mensaje = mensaje;
    this.detalles = detalles;
  }
}

/** Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta. */
export class EndpointPe {
  #apiKey;
  #baseUrl;
  /** Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta. */
  creditosDisponibles = null;

  constructor(apiKey = process.env.ENDPOINT_API_KEY, baseUrl = BASE_URL) {
    if (!apiKey) {
      throw new Error('Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.');
    }
    this.#apiKey = apiKey;
    this.#baseUrl = baseUrl.replace(/\/$/, '');
  }

  // --- Empresas (SUNAT) ---

  /** Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones. */
  ruc(ruc) {
    return this.#get(`/ruc/${encodeURIComponent(ruc)}`);
  }

  /** Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC. */
  anexos(ruc) {
    return this.#get(`/ruc/${encodeURIComponent(ruc)}/anexos`);
  }

  /** Representantes legales con documento, cargo y fecha de nombramiento. */
  representantes(ruc) {
    return this.#get(`/ruc/${encodeURIComponent(ruc)}/representantes`);
  }

  /** Trabajadores, pensionistas y prestadores de servicio declarados por periodo. */
  trabajadores(ruc) {
    return this.#get(`/ruc/${encodeURIComponent(ruc)}/trabajadores`);
  }

  /** Busca el RUC de una empresa por su razón social (hasta 20 coincidencias). */
  empresas(texto) {
    return this.#get('/empresas', { q: texto });
  }

  // --- Identidad (RENIEC) ---

  /** Nombres y apellidos del titular, dígito verificador y RUC de persona natural. */
  dni(dni) {
    return this.#get(`/dni/${encodeURIComponent(dni)}`);
  }

  // --- Finanzas y ubicación ---

  /** Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT. */
  tipoCambio() {
    return this.#get('/tipo-cambio');
  }

  /** Departamento, provincia y distrito de un código de ubigeo de 6 dígitos. */
  ubigeo(codigo) {
    return this.#get(`/ubigeo/${encodeURIComponent(codigo)}`);
  }

  /** Lista departamentos, provincias o distritos, o arma el código a partir de los nombres. */
  ubigeoPorNombres({ departamento, provincia, distrito } = {}) {
    return this.#get('/ubigeo', { departamento, provincia, distrito });
  }

  // --- Petición HTTP ---

  async #get(path, params) {
    const url = new URL(this.#baseUrl + path);
    for (const [clave, valor] of Object.entries(params ?? {})) {
      if (valor != null) url.searchParams.set(clave, valor);
    }

    for (let intento = 1; ; intento++) {
      let res;
      try {
        res = await fetch(url, {
          headers: {
            Authorization: `Bearer ${this.#apiKey}`,
            Accept: 'application/json',
            'User-Agent': 'endpoint-pe-ejemplos/javascript',
          },
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
      } catch (err) {
        if (intento < REINTENTOS) {
          await esperar(intento);
          continue;
        }
        throw new EndpointError(0, 'red', `No se pudo conectar con la API: ${err.message}`);
      }

      if (res.status >= 500 && intento < REINTENTOS) {
        await esperar(intento);
        continue;
      }

      const cuerpo = await res.json().catch(() => ({}));
      const restantes = res.headers.get('x-credits-remaining');
      if (restantes !== null) this.creditosDisponibles = Number(restantes);

      if (!res.ok || !cuerpo.success) {
        throw new EndpointError(
          res.status,
          cuerpo.error ?? 'error',
          cuerpo.message ?? `Respuesta inesperada (HTTP ${res.status})`,
          cuerpo.detalles,
        );
      }
      return cuerpo.data;
    }
  }
}

/** Valida el formato de un RUC antes de consultar: 11 dígitos, prefijo 10/15/16/17/20 y dígito verificador. */
export function esRucValido(ruc) {
  if (!/^(10|15|16|17|20)\d{9}$/.test(ruc)) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const suma = pesos.reduce((acc, peso, i) => acc + Number(ruc[i]) * peso, 0);
  const resto = 11 - (suma % 11);
  const verificador = resto === 10 ? 0 : resto === 11 ? 1 : resto;
  return verificador === Number(ruc[10]);
}

const esperar = (intento) => new Promise((r) => setTimeout(r, 1000 * 2 ** (intento - 1)));

// --- Uso desde la terminal ---

const USO = `Uso: node consulta.mjs <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys`;

async function main(argv) {
  const [comando, dato = ''] = argv;
  if (!comando || ['-h', '--help', 'ayuda'].includes(comando)) {
    console.log(USO);
    return 0;
  }

  let api;
  try {
    api = new EndpointPe();
  } catch (err) {
    console.error(err.message);
    return 2;
  }

  // comando -> [función, necesita dato]
  const comandos = {
    ruc: [(d) => api.ruc(d), true],
    dni: [(d) => api.dni(d), true],
    'tipo-cambio': [() => api.tipoCambio(), false],
    ubigeo: [(d) => api.ubigeo(d), true],
    empresas: [(d) => api.empresas(d), true],
    anexos: [(d) => api.anexos(d), true],
    representantes: [(d) => api.representantes(d), true],
    trabajadores: [(d) => api.trabajadores(d), true],
  };
  if (!comandos[comando]) {
    console.error(`Comando desconocido: ${comando}\n\n${USO}`);
    return 2;
  }
  const [funcion, necesitaDato] = comandos[comando];
  if (necesitaDato && !dato) {
    console.error(`El comando '${comando}' necesita un dato.`);
    return 2;
  }

  try {
    const resultado = await funcion(dato);
    console.log(JSON.stringify(resultado, null, 2));
    if (api.creditosDisponibles !== null) {
      console.error(`Créditos disponibles: ${api.creditosDisponibles}`);
    }
    return 0;
  } catch (err) {
    if (err instanceof EndpointError) {
      console.error(`Error HTTP ${err.status} (${err.error}): ${err.mensaje}`);
      for (const [campo, motivo] of Object.entries(err.detalles ?? {})) {
        console.error(`  ${campo}: ${motivo}`);
      }
      return 1;
    }
    throw err;
  }
}

const esPrincipal = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (esPrincipal) {
  process.exitCode = await main(process.argv.slice(2));
}
