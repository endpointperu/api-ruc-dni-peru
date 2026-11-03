/**
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Kotlin.
 *
 * Sin dependencias: usa java.net.http (JDK 11+). Los métodos devuelven el objeto `data`
 * como texto JSON; para convertirlo a objetos usa kotlinx.serialization, Moshi o Jackson.
 *
 * Compilar y ejecutar:
 *   kotlinc EndpointPe.kt -include-runtime -d consulta.jar
 *   export ENDPOINT_API_KEY=ep_live_...
 *   java -jar consulta.jar ruc 20131312955
 *   java -jar consulta.jar dni 45871236
 *   java -jar consulta.jar tipo-cambio
 *   java -jar consulta.jar ubigeo 150101
 *   java -jar consulta.jar empresas "superintendencia aduanas"
 *   java -jar consulta.jar anexos 20131312955
 *   java -jar consulta.jar representantes 20131312955
 *   java -jar consulta.jar trabajadores 20131312955
 *
 * Documentación: https://endpoint.pe/docs
 */

import java.io.IOException
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.time.Duration
import kotlin.system.exitProcess

private const val TIMEOUT_SEGUNDOS = 15L
private const val REINTENTOS = 3 // solo ante errores de red o 5xx; nunca ante 404 o 422

/**
 * La API respondió con success=false. `error` es el código estable para comparar en tu
 * código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
 */
class EndpointException(val status: Int, val error: String, val mensaje: String, val detalles: String? = null) :
    RuntimeException("HTTP $status · $error: $mensaje")

/** Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta como texto JSON. */
class EndpointPe(
    apiKey: String? = System.getenv("ENDPOINT_API_KEY"),
    baseUrl: String = System.getenv("ENDPOINT_BASE_URL")?.takeIf { it.isNotBlank() } ?: "https://api.endpoint.pe/v1",
) {
    private val apiKey = apiKey?.takeIf { it.isNotBlank() }
        ?: throw IllegalArgumentException("Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.")
    private val baseUrl = baseUrl.trimEnd('/')
    private val http: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build()

    /** Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta. */
    var creditosDisponibles: Int? = null
        private set

    // Empresas (SUNAT)
    fun ruc(ruc: String) = get("/ruc/${codificar(ruc)}")
    fun anexos(ruc: String) = get("/ruc/${codificar(ruc)}/anexos")
    fun representantes(ruc: String) = get("/ruc/${codificar(ruc)}/representantes")
    fun trabajadores(ruc: String) = get("/ruc/${codificar(ruc)}/trabajadores")
    fun empresas(texto: String) = get("/empresas?q=${codificar(texto)}")

    // Identidad (RENIEC)
    fun dni(dni: String) = get("/dni/${codificar(dni)}")

    // Finanzas y ubicación
    fun tipoCambio() = get("/tipo-cambio")
    fun ubigeo(codigo: String) = get("/ubigeo/${codificar(codigo)}")

    private fun get(ruta: String): String {
        val peticion = HttpRequest.newBuilder(URI.create(baseUrl + ruta))
            .timeout(Duration.ofSeconds(TIMEOUT_SEGUNDOS))
            .header("Authorization", "Bearer $apiKey")
            .header("Accept", "application/json")
            .header("User-Agent", "endpoint-pe-ejemplos/kotlin")
            .GET()
            .build()

        var intento = 1
        while (true) {
            val respuesta: HttpResponse<String> = try {
                http.send(peticion, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))
            } catch (e: IOException) {
                if (intento < REINTENTOS) {
                    esperar(intento++)
                    continue
                }
                throw EndpointException(0, "red", "No se pudo conectar con la API: ${e.message}")
            }

            if (respuesta.statusCode() >= 500 && intento < REINTENTOS) {
                esperar(intento++)
                continue
            }

            respuesta.headers().firstValue("x-credits-remaining").ifPresent { creditosDisponibles = it.trim().toInt() }
            val cuerpo = respuesta.body()
            if (respuesta.statusCode() != 200) {
                throw EndpointException(
                    respuesta.statusCode(),
                    campo(cuerpo, "error") ?: "error",
                    campo(cuerpo, "message") ?: "Respuesta inesperada (HTTP ${respuesta.statusCode()})",
                    objeto(cuerpo, "detalles"),
                )
            }
            return objeto(cuerpo, "data") ?: "{}"
        }
    }

    private fun codificar(valor: String) = URLEncoder.encode(valor, StandardCharsets.UTF_8)

    private fun esperar(intento: Int) = Thread.sleep(1000L shl (intento - 1))

    companion object {
        /** Valor de un campo de primer nivel: texto sin comillas, o el literal (número, true, false). null si no existe o es null. */
        fun campo(json: String, nombre: String): String? {
            val regex = Regex("\"${Regex.escape(nombre)}\"\\s*:\\s*(\"((?:[^\"\\\\]|\\\\.)*)\"|[^,}\\]]+)")
            val m = regex.find(json) ?: return null
            m.groups[2]?.let {
                return it.value.replace("\\\"", "\"").replace("\\/", "/").replace("\\n", "\n").replace("\\\\", "\\")
            }
            return m.groups[1]!!.value.trim().takeIf { it != "null" }
        }

        /** El objeto JSON (con sus llaves) de un campo de primer nivel, o null. */
        fun objeto(json: String, nombre: String): String? {
            val i = json.indexOf("\"$nombre\"").takeIf { it >= 0 } ?: return null
            val inicio = json.indexOf('{', i).takeIf { it >= 0 } ?: return null
            var nivel = 0
            var enTexto = false
            var j = inicio
            while (j < json.length) {
                val c = json[j]
                when {
                    enTexto && c == '\\' -> j++
                    enTexto && c == '"' -> enTexto = false
                    enTexto -> {}
                    c == '"' -> enTexto = true
                    c == '{' -> nivel++
                    c == '}' -> if (--nivel == 0) return json.substring(inicio, j + 1)
                }
                j++
            }
            return null
        }

        /** Da formato legible a un JSON compacto (sangría de dos espacios). */
        fun formatear(json: String): String {
            val sb = StringBuilder()
            var nivel = 0
            var enTexto = false
            var i = 0
            while (i < json.length) {
                val c = json[i]
                if (enTexto) {
                    sb.append(c)
                    if (c == '\\') sb.append(json[++i]) else if (c == '"') enTexto = false
                } else when (c) {
                    '"' -> { enTexto = true; sb.append(c) }
                    '{', '[' -> sb.append(c).append('\n').append("  ".repeat(++nivel))
                    '}', ']' -> sb.append('\n').append("  ".repeat(--nivel)).append(c)
                    ',' -> sb.append(c).append('\n').append("  ".repeat(nivel))
                    ':' -> sb.append(": ")
                    ' ', '\n', '\r', '\t' -> {}
                    else -> sb.append(c)
                }
                i++
            }
            return sb.toString()
        }
    }
}

// --- Uso desde la terminal ---

private val USO = """
Uso: java -jar consulta.jar <comando> [dato]

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
""".trimIndent()

fun main(args: Array<String>) {
    val comando = args.getOrNull(0) ?: ""
    val dato = args.getOrNull(1) ?: ""
    if (comando.isEmpty() || comando in listOf("-h", "--help", "ayuda")) {
        println(USO)
        return
    }

    val api = try {
        EndpointPe()
    } catch (e: IllegalArgumentException) {
        System.err.println(e.message)
        exitProcess(2)
    }

    val necesitaDato = mapOf(
        "ruc" to true, "dni" to true, "tipo-cambio" to false, "ubigeo" to true,
        "empresas" to true, "anexos" to true, "representantes" to true, "trabajadores" to true,
    )
    if (comando !in necesitaDato) {
        System.err.println("Comando desconocido: $comando\n\n$USO")
        exitProcess(2)
    }
    if (necesitaDato.getValue(comando) && dato.isEmpty()) {
        System.err.println("El comando '$comando' necesita un dato.")
        exitProcess(2)
    }

    try {
        val resultado = when (comando) {
            "ruc" -> api.ruc(dato)
            "dni" -> api.dni(dato)
            "tipo-cambio" -> api.tipoCambio()
            "ubigeo" -> api.ubigeo(dato)
            "empresas" -> api.empresas(dato)
            "anexos" -> api.anexos(dato)
            "representantes" -> api.representantes(dato)
            else -> api.trabajadores(dato)
        }
        println(EndpointPe.formatear(resultado))
        api.creditosDisponibles?.let { System.err.println("Créditos disponibles: $it") }
    } catch (e: EndpointException) {
        System.err.println("Error HTTP ${e.status} (${e.error}): ${e.mensaje}")
        e.detalles?.let { System.err.println("  $it") }
        exitProcess(1)
    }
}
