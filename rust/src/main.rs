//! endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Rust.
//!
//! Dependencias: `ureq` (HTTP, síncrono y ligero) y `serde_json`.
//!
//! Uso desde la terminal:
//!   export ENDPOINT_API_KEY=ep_live_...
//!   cargo run -- ruc 20131312955
//!   cargo run -- dni 45871236
//!   cargo run -- tipo-cambio
//!   cargo run -- ubigeo 150101
//!   cargo run -- empresas "superintendencia aduanas"
//!   cargo run -- anexos 20131312955
//!   cargo run -- representantes 20131312955
//!   cargo run -- trabajadores 20131312955
//!
//! Uso desde tu código:
//!   let mut api = EndpointPe::nuevo()?;              // lee ENDPOINT_API_KEY del entorno
//!   let ficha = api.ruc("20131312955")?;             // serde_json::Value con el objeto `data`
//!   println!("{} {}", ficha["razon_social"], api.creditos_disponibles.unwrap_or(0));
//!
//! Documentación: https://endpoint.pe/docs

use std::collections::BTreeMap;
use std::fmt;
use std::time::Duration;
use std::{env, process, thread};

use serde_json::Value;

const BASE_URL_POR_DEFECTO: &str = "https://api.endpoint.pe/v1";
const TIMEOUT: Duration = Duration::from_secs(15);
const REINTENTOS: u32 = 3; // solo ante errores de red o 5xx; nunca ante 404 o 422

/// La API respondió con success=false. `error` es el código estable para comparar en tu
/// código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
#[derive(Debug)]
pub struct EndpointError {
    pub status: u16,
    pub error: String,
    pub mensaje: String,
    pub detalles: BTreeMap<String, String>,
}

impl fmt::Display for EndpointError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "HTTP {} · {}: {}", self.status, self.error, self.mensaje)
    }
}

impl std::error::Error for EndpointError {}

/// Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta.
pub struct EndpointPe {
    api_key: String,
    base_url: String,
    agente: ureq::Agent,
    /// Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.
    pub creditos_disponibles: Option<u64>,
}

impl EndpointPe {
    /// Crea el cliente con la API key de `ENDPOINT_API_KEY`.
    pub fn nuevo() -> Result<Self, String> {
        let api_key = env::var("ENDPOINT_API_KEY").ok().filter(|k| !k.is_empty());
        Self::con_clave(api_key.ok_or("Falta la API key: define ENDPOINT_API_KEY o usa con_clave().")?)
    }

    /// Crea el cliente con una API key explícita.
    pub fn con_clave(api_key: impl Into<String>) -> Result<Self, String> {
        let base_url = env::var("ENDPOINT_BASE_URL")
            .ok()
            .filter(|u| !u.is_empty())
            .unwrap_or_else(|| BASE_URL_POR_DEFECTO.to_string());
        Ok(Self {
            api_key: api_key.into(),
            base_url: base_url.trim_end_matches('/').to_string(),
            agente: ureq::AgentBuilder::new().timeout(TIMEOUT).build(),
            creditos_disponibles: None,
        })
    }

    // Empresas (SUNAT)

    /// Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.
    pub fn ruc(&mut self, ruc: &str) -> Result<Value, EndpointError> {
        self.get(&format!("/ruc/{}", codificar(ruc)), &[])
    }

    /// Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.
    pub fn anexos(&mut self, ruc: &str) -> Result<Value, EndpointError> {
        self.get(&format!("/ruc/{}/anexos", codificar(ruc)), &[])
    }

    /// Representantes legales con documento, cargo y fecha de nombramiento.
    pub fn representantes(&mut self, ruc: &str) -> Result<Value, EndpointError> {
        self.get(&format!("/ruc/{}/representantes", codificar(ruc)), &[])
    }

    /// Trabajadores, pensionistas y prestadores de servicio declarados por periodo.
    pub fn trabajadores(&mut self, ruc: &str) -> Result<Value, EndpointError> {
        self.get(&format!("/ruc/{}/trabajadores", codificar(ruc)), &[])
    }

    /// Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).
    pub fn empresas(&mut self, texto: &str) -> Result<Value, EndpointError> {
        self.get("/empresas", &[("q", texto)])
    }

    // Identidad (RENIEC)

    /// Nombres y apellidos del titular, dígito verificador y RUC de persona natural.
    pub fn dni(&mut self, dni: &str) -> Result<Value, EndpointError> {
        self.get(&format!("/dni/{}", codificar(dni)), &[])
    }

    // Finanzas y ubicación

    /// Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.
    pub fn tipo_cambio(&mut self) -> Result<Value, EndpointError> {
        self.get("/tipo-cambio", &[])
    }

    /// Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.
    pub fn ubigeo(&mut self, codigo: &str) -> Result<Value, EndpointError> {
        self.get(&format!("/ubigeo/{}", codificar(codigo)), &[])
    }

    fn get(&mut self, ruta: &str, params: &[(&str, &str)]) -> Result<Value, EndpointError> {
        let url = format!("{}{}", self.base_url, ruta);

        for intento in 1..=REINTENTOS {
            let mut peticion = self
                .agente
                .get(&url)
                .set("Authorization", &format!("Bearer {}", self.api_key))
                .set("Accept", "application/json")
                .set("User-Agent", "endpoint-pe-ejemplos/rust");
            for (clave, valor) in params {
                peticion = peticion.query(clave, valor);
            }

            let (status, respuesta) = match peticion.call() {
                Ok(res) => (200u16, res),
                Err(ureq::Error::Status(codigo, res)) => (codigo, res),
                Err(ureq::Error::Transport(t)) => {
                    if intento < REINTENTOS {
                        esperar(intento);
                        continue;
                    }
                    return Err(EndpointError {
                        status: 0,
                        error: "red".into(),
                        mensaje: format!("No se pudo conectar con la API: {t}"),
                        detalles: BTreeMap::new(),
                    });
                }
            };

            if status >= 500 && intento < REINTENTOS {
                esperar(intento);
                continue;
            }
            if let Some(restantes) = respuesta.header("x-credits-remaining").and_then(|v| v.trim().parse().ok()) {
                self.creditos_disponibles = Some(restantes);
            }

            let mut cuerpo: Value = respuesta.into_json().unwrap_or(Value::Null);
            if status != 200 || cuerpo["success"] != Value::Bool(true) || cuerpo["data"].is_null() {
                let detalles = cuerpo["detalles"]
                    .as_object()
                    .map(|o| o.iter().map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string())).collect())
                    .unwrap_or_default();
                return Err(EndpointError {
                    status,
                    error: cuerpo["error"].as_str().unwrap_or("error").to_string(),
                    mensaje: cuerpo["message"]
                        .as_str()
                        .map(str::to_string)
                        .unwrap_or_else(|| format!("Respuesta inesperada (HTTP {status})")),
                    detalles,
                });
            }
            return Ok(cuerpo["data"].take());
        }
        unreachable!("el bucle siempre devuelve o reintenta")
    }
}

/// Codifica un valor para usarlo como segmento de la ruta.
fn codificar(valor: &str) -> String {
    let mut salida = String::with_capacity(valor.len());
    for byte in valor.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => salida.push(byte as char),
            _ => salida.push_str(&format!("%{byte:02X}")),
        }
    }
    salida
}

fn esperar(intento: u32) {
    thread::sleep(Duration::from_secs(1 << (intento - 1)));
}

// --- Uso desde la terminal ---

const USO: &str = "Uso: cargo run -- <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys";

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let comando = args.first().map(String::as_str).unwrap_or("");
    let dato = args.get(1).map(String::as_str).unwrap_or("");
    if comando.is_empty() || matches!(comando, "-h" | "--help" | "ayuda") {
        println!("{USO}");
        return;
    }

    let mut api = match EndpointPe::nuevo() {
        Ok(api) => api,
        Err(motivo) => {
            eprintln!("{motivo}");
            process::exit(2);
        }
    };

    let necesita_dato = match comando {
        "ruc" | "dni" | "ubigeo" | "empresas" | "anexos" | "representantes" | "trabajadores" => true,
        "tipo-cambio" => false,
        _ => {
            eprintln!("Comando desconocido: {comando}\n\n{USO}");
            process::exit(2);
        }
    };
    if necesita_dato && dato.is_empty() {
        eprintln!("El comando '{comando}' necesita un dato.");
        process::exit(2);
    }

    let resultado = match comando {
        "ruc" => api.ruc(dato),
        "dni" => api.dni(dato),
        "tipo-cambio" => api.tipo_cambio(),
        "ubigeo" => api.ubigeo(dato),
        "empresas" => api.empresas(dato),
        "anexos" => api.anexos(dato),
        "representantes" => api.representantes(dato),
        _ => api.trabajadores(dato),
    };

    match resultado {
        Ok(data) => {
            println!("{}", serde_json::to_string_pretty(&data).unwrap_or_default());
            if let Some(restantes) = api.creditos_disponibles {
                eprintln!("Créditos disponibles: {restantes}");
            }
        }
        Err(e) => {
            eprintln!("Error HTTP {} ({}): {}", e.status, e.error, e.mensaje);
            for (campo, motivo) in &e.detalles {
                eprintln!("  {campo}: {motivo}");
            }
            process::exit(1);
        }
    }
}
