// endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Swift.
//
// Sin paquetes: Foundation, URLSession (async/await) y JSONSerialization.
// Funciona en macOS 12+, iOS 15+ (desde tu backend, ver README) y Linux (Swift 5.7+).
//
// Uso desde la terminal:
//   export ENDPOINT_API_KEY=ep_live_...
//   swift EndpointPe.swift ruc 20131312955        # o: swiftc EndpointPe.swift -o consulta
//   swift EndpointPe.swift dni 45871236
//   swift EndpointPe.swift tipo-cambio
//   swift EndpointPe.swift ubigeo 150101
//   swift EndpointPe.swift empresas "superintendencia aduanas"
//   swift EndpointPe.swift anexos 20131312955
//   swift EndpointPe.swift representantes 20131312955
//   swift EndpointPe.swift trabajadores 20131312955
//
// Uso desde tu código:
//   let api = try EndpointPe()                       // lee ENDPOINT_API_KEY del entorno
//   let ficha = try await api.ruc("20131312955")     // [String: Any] con el objeto `data`
//   print(ficha["razon_social"] ?? "", api.creditosDisponibles ?? 0)
//
// Documentación: https://endpoint.pe/docs

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// La API respondió con success=false. `error` es el código estable para comparar en tu
/// código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
struct EndpointError: Error, CustomStringConvertible {
    let status: Int
    let error: String
    let mensaje: String
    let detalles: [String: String]

    var description: String { "HTTP \(status) · \(error): \(mensaje)" }
}

/// Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta.
final class EndpointPe {
    static let baseURLPorDefecto = "https://api.endpoint.pe/v1"
    private static let timeout: TimeInterval = 15
    private static let reintentos = 3 // solo ante errores de red o 5xx; nunca ante 404 o 422

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    /// Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.
    private(set) var creditosDisponibles: Int?

    init(apiKey: String? = ProcessInfo.processInfo.environment["ENDPOINT_API_KEY"],
         baseURL: String? = ProcessInfo.processInfo.environment["ENDPOINT_BASE_URL"]) throws {
        guard let apiKey, !apiKey.isEmpty else {
            throw EndpointError(status: 0, error: "configuracion",
                                mensaje: "Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.", detalles: [:])
        }
        self.apiKey = apiKey
        let url = (baseURL?.isEmpty == false ? baseURL! : Self.baseURLPorDefecto)
        self.baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        let configuracion = URLSessionConfiguration.default
        configuracion.timeoutIntervalForRequest = Self.timeout
        self.session = URLSession(configuration: configuracion)
    }

    // Empresas (SUNAT)

    /// Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.
    func ruc(_ ruc: String) async throws -> [String: Any] { try await get("/ruc/\(codificar(ruc))") }
    /// Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.
    func anexos(_ ruc: String) async throws -> [String: Any] { try await get("/ruc/\(codificar(ruc))/anexos") }
    /// Representantes legales con documento, cargo y fecha de nombramiento.
    func representantes(_ ruc: String) async throws -> [String: Any] { try await get("/ruc/\(codificar(ruc))/representantes") }
    /// Trabajadores, pensionistas y prestadores de servicio declarados por periodo.
    func trabajadores(_ ruc: String) async throws -> [String: Any] { try await get("/ruc/\(codificar(ruc))/trabajadores") }
    /// Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).
    func empresas(_ texto: String) async throws -> [String: Any] { try await get("/empresas", query: [URLQueryItem(name: "q", value: texto)]) }

    // Identidad (RENIEC)

    /// Nombres y apellidos del titular, dígito verificador y RUC de persona natural.
    func dni(_ dni: String) async throws -> [String: Any] { try await get("/dni/\(codificar(dni))") }

    // Finanzas y ubicación

    /// Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.
    func tipoCambio() async throws -> [String: Any] { try await get("/tipo-cambio") }
    /// Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.
    func ubigeo(_ codigo: String) async throws -> [String: Any] { try await get("/ubigeo/\(codificar(codigo))") }

    private func get(_ ruta: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        guard var componentes = URLComponents(string: baseURL + ruta) else {
            throw EndpointError(status: 0, error: "url", mensaje: "Ruta inválida: \(ruta)", detalles: [:])
        }
        if !query.isEmpty { componentes.queryItems = query }
        var peticion = URLRequest(url: componentes.url!)
        peticion.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        peticion.setValue("application/json", forHTTPHeaderField: "Accept")
        peticion.setValue("endpoint-pe-ejemplos/swift", forHTTPHeaderField: "User-Agent")

        for intento in 1...Self.reintentos {
            let datos: Data
            let respuesta: URLResponse
            do {
                (datos, respuesta) = try await session.data(for: peticion)
            } catch {
                if intento < Self.reintentos {
                    try await Task.sleep(nanoseconds: UInt64(1 << (intento - 1)) * 1_000_000_000)
                    continue
                }
                throw EndpointError(status: 0, error: "red",
                                    mensaje: "No se pudo conectar con la API: \(error.localizedDescription)", detalles: [:])
            }
            let http = respuesta as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status >= 500 && intento < Self.reintentos {
                try await Task.sleep(nanoseconds: UInt64(1 << (intento - 1)) * 1_000_000_000)
                continue
            }
            if let restantes = http?.value(forHTTPHeaderField: "X-Credits-Remaining"),
               let numero = Int(restantes.trimmingCharacters(in: .whitespaces)) {
                creditosDisponibles = numero
            }

            let cuerpo = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] ?? [:]
            guard status == 200, cuerpo["success"] as? Bool == true, let data = cuerpo["data"] as? [String: Any] else {
                throw EndpointError(
                    status: status,
                    error: cuerpo["error"] as? String ?? "error",
                    mensaje: cuerpo["message"] as? String ?? "Respuesta inesperada (HTTP \(status))",
                    detalles: cuerpo["detalles"] as? [String: String] ?? [:])
            }
            return data
        }
        fatalError("inalcanzable")
    }

    private func codificar(_ valor: String) -> String {
        valor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? valor
    }
}

// --- Uso desde la terminal ---

let uso = """
Uso: swift EndpointPe.swift <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys
"""

let argumentos = Array(CommandLine.arguments.dropFirst())
let comando = argumentos.first ?? ""
let dato = argumentos.count > 1 ? argumentos[1] : ""

if comando.isEmpty || ["-h", "--help", "ayuda"].contains(comando) {
    print(uso)
    exit(0)
}

let necesitaDato: [String: Bool] = [
    "ruc": true, "dni": true, "tipo-cambio": false, "ubigeo": true,
    "empresas": true, "anexos": true, "representantes": true, "trabajadores": true,
]
guard let requiere = necesitaDato[comando] else {
    FileHandle.standardError.write("Comando desconocido: \(comando)\n\n\(uso)\n".data(using: .utf8)!)
    exit(2)
}
if requiere && dato.isEmpty {
    FileHandle.standardError.write("El comando '\(comando)' necesita un dato.\n".data(using: .utf8)!)
    exit(2)
}

do {
    let api = try EndpointPe()
    let resultado: [String: Any]
    switch comando {
    case "ruc": resultado = try await api.ruc(dato)
    case "dni": resultado = try await api.dni(dato)
    case "tipo-cambio": resultado = try await api.tipoCambio()
    case "ubigeo": resultado = try await api.ubigeo(dato)
    case "empresas": resultado = try await api.empresas(dato)
    case "anexos": resultado = try await api.anexos(dato)
    case "representantes": resultado = try await api.representantes(dato)
    default: resultado = try await api.trabajadores(dato)
    }
    let json = try JSONSerialization.data(withJSONObject: resultado, options: [.prettyPrinted, .withoutEscapingSlashes])
    print(String(decoding: json, as: UTF8.self))
    if let restantes = api.creditosDisponibles {
        FileHandle.standardError.write("Créditos disponibles: \(restantes)\n".data(using: .utf8)!)
    }
} catch let e as EndpointError {
    var texto = "Error HTTP \(e.status) (\(e.error)): \(e.mensaje)\n"
    for (campo, motivo) in e.detalles { texto += "  \(campo): \(motivo)\n" }
    FileHandle.standardError.write(texto.data(using: .utf8)!)
    exit(e.status == 0 && e.error == "configuracion" ? 2 : 1)
}
