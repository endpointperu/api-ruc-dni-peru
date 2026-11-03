#!/usr/bin/env node
/**
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde TypeScript.
 *
 * Sin dependencias: usa `fetch` (Node.js 18+, Bun, Deno) y declara el tipo de cada respuesta.
 *
 * Uso desde la terminal:
 *   export ENDPOINT_API_KEY=ep_live_...
 *   npx tsx consulta.ts ruc 20131312955        # o: node consulta.ts ruc 20131312955 (Node 22.6+)
 *   npx tsx consulta.ts dni 45871236
 *   npx tsx consulta.ts tipo-cambio
 *   npx tsx consulta.ts ubigeo 150101
 *   npx tsx consulta.ts empresas "superintendencia aduanas"
 *   npx tsx consulta.ts anexos 20131312955
 *   npx tsx consulta.ts representantes 20131312955
 *   npx tsx consulta.ts trabajadores 20131312955
 *
 * Uso desde tu código:
 *   import { EndpointPe, EndpointError } from './consulta';
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

// --- Tipos de las respuestas (campos de `data`) ---

export interface Meta {
  fuente?: string;
  consultado_en: string;
  creditos_cobrados?: number;
  creditos_disponibles?: number;
}

export interface Envoltorio<T> {
  success: boolean;
  message: string;
  data: T | null;
  error?: string;
  detalles?: Record<string, string>;
  meta: Meta;
}

/** GET /v1/ruc/{ruc} */
export interface Ruc {
  ruc: string;
  razon_social: string;
  nombre_comercial: string | null;
  tipo_contribuyente: string | null;
  estado: string;
  condicion: string;
  fecha_inscripcion: string | null;
  fecha_inicio_actividades: string | null;
  direccion: string | null;
  direccion_completa: string | null;
  departamento: string | null;
  provincia: string | null;
  distrito: string | null;
  ubigeo: string | null;
  ubigeo_reniec: string | null;
  es_agente_de_retencion: boolean | null;
  es_agente_de_percepcion: boolean | null;
  es_agente_de_percepcion_combustible: boolean | null;
  es_buen_contribuyente: boolean | null;
  cantidad_trabajadores: number | null;
  cantidad_establecimientos: number;
  cantidad_representantes: number;
}

/** GET /v1/dni/{dni} */
export interface Dni {
  dni: string;
  digito_verificador: string;
  nombres: string;
  apellido_paterno: string;
  apellido_materno: string;
  nombre_completo: string;
  ruc: string | null;
}

/** GET /v1/tipo-cambio */
export interface TipoCambio {
  fecha: string;
  moneda: 'USD';
  compra: number;
  venta: number;
  fuente: 'SUNAT';
}

/** GET /v1/ubigeo/{codigo} */
export interface Ubigeo {
  ubigeo: string;
  ubigeo_reniec: string | null;
  departamento: string;
  provincia: string;
  distrito: string;
  codigos: { departamento: string; provincia: string; distrito: string };
  vigente: boolean;
}

/** GET /v1/ubigeo?departamento=&provincia=&distrito= (listas por nivel o el código completo) */
export type UbigeoPorNombres =
  | Ubigeo
  | { nivel: 'departamentos' | 'provincias' | 'distritos'; [clave: string]: unknown };

/** GET /v1/empresas?q= */
export interface Empresas {
  consulta: string;
  modo: 'texto' | 'prefijo';
  cantidad: number;
  resultados: {
    ruc: string;
    razon_social: string;
    estado: string;
    condicion: string;
    ubigeo: string | null;
  }[];
}

/** GET /v1/ruc/{ruc}/anexos */
export interface Anexos {
  ruc: string;
  razon_social: string;
  cantidad: number;
  establecimientos: {
    codigo: string;
    tipo: string;
    tipo_codigo: string;
    direccion: string;
    actividad_economica: string | null;
  }[];
}

/** GET /v1/ruc/{ruc}/representantes */
export interface Representantes {
  ruc: string;
  razon_social: string;
  cantidad: number;
  representantes: {
    tipo_documento: string;
    numero_documento: string;
    nombre: string;
    cargo: string;
    desde: string | null;
  }[];
}

export interface Periodo {
  periodo: string;
  trabajadores: number;
  pensionistas: number;
  prestadores_servicio: number;
}

/** GET /v1/ruc/{ruc}/trabajadores */
export interface Trabajadores {
  ruc: string;
  razon_social: string;
  ultimo_periodo: Periodo | null;
  cantidad_periodos: number;
  periodos: Periodo[];
}

// --- Cliente ---

/**
 * La API respondió con success=false. `error` es el código estable para comparar en tu
 * código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
 */
export class EndpointError extends Error {
  readonly status: number;
  readonly error: string;
  readonly mensaje: string;
  readonly detalles: Record<string, string>;

  constructor(status: number, error: string, mensaje: string, detalles: Record<string, string> = {}) {
    super(`HTTP ${status} · ${error}: ${mensaje}`);
    this.name = 'EndpointError';
    this.status = status;
    this.error = error;
    this.mensaje = mensaje;
    this.detalles = detalles;
  }
}

/** Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta, tipado. */
export class EndpointPe {
  readonly #apiKey: string;
  readonly #baseUrl: string;
  /** Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta. */
  creditosDisponibles: number | null = null;

  constructor(apiKey: string | undefined = process.env.ENDPOINT_API_KEY, baseUrl: string = BASE_URL) {
    if (!apiKey) {
      throw new Error('Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.');
    }
    this.#apiKey = apiKey;
    this.#baseUrl = baseUrl.replace(/\/$/, '');
  }

  // Empresas (SUNAT)
  ruc(ruc: string): Promise<Ruc> {
    return this.#get<Ruc>(`/ruc/${encodeURIComponent(ruc)}`);
  }
  anexos(ruc: string): Promise<Anexos> {
    return this.#get<Anexos>(`/ruc/${encodeURIComponent(ruc)}/anexos`);
  }
  representantes(ruc: string): Promise<Representantes> {
    return this.#get<Representantes>(`/ruc/${encodeURIComponent(ruc)}/representantes`);
  }
  trabajadores(ruc: string): Promise<Trabajadores> {
    return this.#get<Trabajadores>(`/ruc/${encodeURIComponent(ruc)}/trabajadores`);
  }
  empresas(texto: string): Promise<Empresas> {
    return this.#get<Empresas>('/empresas', { q: texto });
  }

  // Identidad (RENIEC)
  dni(dni: string): Promise<Dni> {
    return this.#get<Dni>(`/dni/${encodeURIComponent(dni)}`);
  }

  // Finanzas y ubicación
  tipoCambio(): Promise<TipoCambio> {
    return this.#get<TipoCambio>('/tipo-cambio');
  }
  ubigeo(codigo: string): Promise<Ubigeo> {
    return this.#get<Ubigeo>(`/ubigeo/${encodeURIComponent(codigo)}`);
  }
  ubigeoPorNombres(filtro: { departamento?: string; provincia?: string; distrito?: string } = {}): Promise<UbigeoPorNombres> {
    return this.#get<UbigeoPorNombres>('/ubigeo', filtro);
  }

  async #get<T>(path: string, params?: Record<string, string | undefined>): Promise<T> {
    const url = new URL(this.#baseUrl + path);
    for (const [clave, valor] of Object.entries(params ?? {})) {
      if (valor != null) url.searchParams.set(clave, valor);
    }

    for (let intento = 1; ; intento++) {
      let res: Response;
      try {
        res = await fetch(url, {
          headers: {
            Authorization: `Bearer ${this.#apiKey}`,
            Accept: 'application/json',
            'User-Agent': 'endpoint-pe-ejemplos/typescript',
          },
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
      } catch (err) {
        if (intento < REINTENTOS) {
          await esperar(intento);
          continue;
        }
        const motivo = err instanceof Error ? err.message : String(err);
        throw new EndpointError(0, 'red', `No se pudo conectar con la API: ${motivo}`);
      }

      if (res.status >= 500 && intento < REINTENTOS) {
        await esperar(intento);
        continue;
      }

      const cuerpo = (await res.json().catch(() => ({}))) as Partial<Envoltorio<T>>;
      const restantes = res.headers.get('x-credits-remaining');
      if (restantes !== null) this.creditosDisponibles = Number(restantes);

      if (!res.ok || !cuerpo.success || cuerpo.data == null) {
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
export function esRucValido(ruc: string): boolean {
  if (!/^(10|15|16|17|20)\d{9}$/.test(ruc)) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const suma = pesos.reduce((acc, peso, i) => acc + Number(ruc[i]) * peso, 0);
  const resto = 11 - (suma % 11);
  const verificador = resto === 10 ? 0 : resto === 11 ? 1 : resto;
  return verificador === Number(ruc[10]);
}

const esperar = (intento: number) => new Promise<void>((r) => setTimeout(r, 1000 * 2 ** (intento - 1)));

// --- Uso desde la terminal ---

const USO = `Uso: npx tsx consulta.ts <comando> [dato]

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

async function main(argv: string[]): Promise<number> {
  const [comando, dato = ''] = argv;
  if (!comando || ['-h', '--help', 'ayuda'].includes(comando)) {
    console.log(USO);
    return 0;
  }

  let api: EndpointPe;
  try {
    api = new EndpointPe();
  } catch (err) {
    console.error(err instanceof Error ? err.message : err);
    return 2;
  }

  const comandos: Record<string, [(dato: string) => Promise<unknown>, boolean]> = {
    ruc: [(d) => api.ruc(d), true],
    dni: [(d) => api.dni(d), true],
    'tipo-cambio': [() => api.tipoCambio(), false],
    ubigeo: [(d) => api.ubigeo(d), true],
    empresas: [(d) => api.empresas(d), true],
    anexos: [(d) => api.anexos(d), true],
    representantes: [(d) => api.representantes(d), true],
    trabajadores: [(d) => api.trabajadores(d), true],
  };
  const entrada = comandos[comando];
  if (!entrada) {
    console.error(`Comando desconocido: ${comando}\n\n${USO}`);
    return 2;
  }
  const [funcion, necesitaDato] = entrada;
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
      for (const [campo, motivo] of Object.entries(err.detalles)) {
        console.error(`  ${campo}: ${motivo}`);
      }
      return 1;
    }
    throw err;
  }
}

const esPrincipal = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (esPrincipal) {
  process.exitCode = await main(process.argv.slice(2));
}
