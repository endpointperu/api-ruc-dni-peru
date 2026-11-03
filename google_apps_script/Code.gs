/**
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Google Sheets.
 *
 * Instalación:
 *   1. En tu hoja: Extensiones → Apps Script. Borra el contenido y pega este archivo. Guarda.
 *   2. Configuración del proyecto (engranaje) → Propiedades del script → Agregar propiedad:
 *      ENDPOINT_API_KEY = ep_live_...   (crea la tuya gratis en https://app.endpoint.pe/panel/api-keys)
 *   3. Vuelve a la hoja y usa las fórmulas:
 *        =CONSULTAR_RUC(A2)                       → razón social
 *        =CONSULTAR_RUC(A2; "estado")             → ACTIVO
 *        =CONSULTAR_RUC(A2:A50)                   → una columna completa de una sola vez
 *        =CONSULTAR_DNI(B2)                       → nombre completo
 *        =TIPO_CAMBIO_SUNAT("venta")              → 3.457
 *        =UBIGEO_NOMBRE("150101"; "distrito")     → LIMA
 *        =BUSCAR_RUC("superintendencia aduanas")  → RUC de la primera coincidencia
 *
 * Las respuestas se guardan en caché 6 horas para no repetir consultas al recalcular.
 * Documentación: https://endpoint.pe/docs
 */

const BASE_URL = 'https://api.endpoint.pe/v1';
const CACHE_SEGUNDOS = 6 * 60 * 60;

/**
 * Ficha del contribuyente (SUNAT).
 * @param {string|string[][]} ruc RUC de 11 dígitos, o un rango de celdas.
 * @param {string} [campo] razon_social (por defecto), estado, condicion, direccion_completa, tipo_contribuyente, departamento, provincia, distrito, ubigeo, cantidad_trabajadores…
 * @return {string|number} El valor del campo, o el texto del error.
 * @customfunction
 */
function CONSULTAR_RUC(ruc, campo) {
  if (Array.isArray(ruc)) return ruc.map((fila) => fila.map((celda) => CONSULTAR_RUC(celda, campo)));
  return valor_('/ruc/' + encodeURIComponent(soloDigitos_(ruc)), campo || 'razon_social');
}

/**
 * Nombres y apellidos del titular (RENIEC).
 * @param {string|string[][]} dni DNI de 8 dígitos, o un rango de celdas.
 * @param {string} [campo] nombre_completo (por defecto), nombres, apellido_paterno, apellido_materno, ruc, digito_verificador.
 * @return {string} El valor del campo, o el texto del error.
 * @customfunction
 */
function CONSULTAR_DNI(dni, campo) {
  if (Array.isArray(dni)) return dni.map((fila) => fila.map((celda) => CONSULTAR_DNI(celda, campo)));
  const numero = ('00000000' + soloDigitos_(dni)).slice(-8);
  return valor_('/dni/' + numero, campo || 'nombre_completo');
}

/**
 * Tipo de cambio del dólar publicado por SUNAT (el más reciente).
 * @param {string} [campo] venta (por defecto), compra o fecha.
 * @return {number|string}
 * @customfunction
 */
function TIPO_CAMBIO_SUNAT(campo) {
  return valor_('/tipo-cambio', campo || 'venta');
}

/**
 * Departamento, provincia o distrito de un código de ubigeo.
 * @param {string|string[][]} codigo Ubigeo de 6 dígitos, o un rango de celdas.
 * @param {string} [campo] distrito (por defecto), provincia, departamento o ubigeo_reniec.
 * @return {string}
 * @customfunction
 */
function UBIGEO_NOMBRE(codigo, campo) {
  if (Array.isArray(codigo)) return codigo.map((fila) => fila.map((celda) => UBIGEO_NOMBRE(celda, campo)));
  const numero = ('000000' + soloDigitos_(codigo)).slice(-6);
  return valor_('/ubigeo/' + numero, campo || 'distrito');
}

/**
 * RUC de la primera empresa que coincide con la razón social buscada.
 * @param {string} razonSocial Nombre o parte del nombre de la empresa (mínimo 3 caracteres).
 * @return {string}
 * @customfunction
 */
function BUSCAR_RUC(razonSocial) {
  const { status, cuerpo } = consultar_('/empresas?q=' + encodeURIComponent(String(razonSocial).trim()));
  if (status !== 200 || !cuerpo.success) return textoError_(status, cuerpo);
  const primero = cuerpo.data.resultados[0];
  return primero ? primero.ruc : '';
}

// --- Para usar desde tus propios scripts ---

/** Devuelve el objeto `data` completo de una consulta (por ejemplo consultarRuc('20131312955').razon_social). */
function consultarRuc(ruc) { return datos_('/ruc/' + encodeURIComponent(soloDigitos_(ruc))); }
function consultarDni(dni) { return datos_('/dni/' + ('00000000' + soloDigitos_(dni)).slice(-8)); }
function tipoCambio() { return datos_('/tipo-cambio'); }
function consultarUbigeo(codigo) { return datos_('/ubigeo/' + ('000000' + soloDigitos_(codigo)).slice(-6)); }
function buscarEmpresas(texto) { return datos_('/empresas?q=' + encodeURIComponent(String(texto).trim())); }
function anexos(ruc) { return datos_('/ruc/' + encodeURIComponent(soloDigitos_(ruc)) + '/anexos'); }
function representantes(ruc) { return datos_('/ruc/' + encodeURIComponent(soloDigitos_(ruc)) + '/representantes'); }
function trabajadores(ruc) { return datos_('/ruc/' + encodeURIComponent(soloDigitos_(ruc)) + '/trabajadores'); }

// --- Internos ---

function apiKey_() {
  const clave = PropertiesService.getScriptProperties().getProperty('ENDPOINT_API_KEY');
  if (!clave) throw new Error('Falta la API key: agrega ENDPOINT_API_KEY en Propiedades del script.');
  return clave;
}

/** Hace la petición (con caché) y devuelve {status, cuerpo}. */
function consultar_(ruta) {
  const cache = CacheService.getScriptCache();
  const guardado = cache.get(ruta);
  if (guardado) return JSON.parse(guardado);

  const respuesta = UrlFetchApp.fetch(BASE_URL + ruta, {
    headers: { Authorization: 'Bearer ' + apiKey_(), Accept: 'application/json' },
    muteHttpExceptions: true,
  });
  const status = respuesta.getResponseCode();
  let cuerpo;
  try {
    cuerpo = JSON.parse(respuesta.getContentText());
  } catch (e) {
    cuerpo = {};
  }
  const resultado = { status, cuerpo };
  if (status === 200) {
    try {
      cache.put(ruta, JSON.stringify(resultado), CACHE_SEGUNDOS);
    } catch (e) {
      // respuestas muy grandes (más de 100 KB) no entran en la caché; no pasa nada
    }
  }
  return resultado;
}

/** Objeto `data` de la respuesta, o lanza un error con el código y el mensaje de la API. */
function datos_(ruta) {
  const { status, cuerpo } = consultar_(ruta);
  if (status !== 200 || !cuerpo.success) throw new Error(textoError_(status, cuerpo));
  return cuerpo.data;
}

/** Un campo de `data`, o el texto del error para mostrarlo en la celda. */
function valor_(ruta, campo) {
  const { status, cuerpo } = consultar_(ruta);
  if (status !== 200 || !cuerpo.success) return textoError_(status, cuerpo);
  const valor = cuerpo.data[campo];
  return valor === null || valor === undefined ? '' : valor;
}

function textoError_(status, cuerpo) {
  // error: no_encontrado, validacion, sin_creditos… (ver https://endpoint.pe/docs/errores)
  return 'Error ' + status + ' (' + (cuerpo.error || 'error') + '): ' + (cuerpo.message || 'sin respuesta');
}

function soloDigitos_(valor) {
  return String(valor === null || valor === undefined ? '' : valor).replace(/\D/g, '');
}
