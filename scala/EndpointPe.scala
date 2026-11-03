//> using scala 3.3
//> using dep com.lihaoyi::ujson:4.0.2

// endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Scala 3.
//
// HTTP con java.net.http (JDK 11+) y JSON con uJson. Se ejecuta con Scala CLI, sin proyecto sbt.
//
// Uso desde la terminal:
//   export ENDPOINT_API_KEY=ep_live_...
//   scala-cli run EndpointPe.scala -- ruc 20131312955
//   scala-cli run EndpointPe.scala -- dni 45871236
//   scala-cli run EndpointPe.scala -- tipo-cambio
//   scala-cli run EndpointPe.scala -- ubigeo 150101
//   scala-cli run EndpointPe.scala -- empresas "superintendencia aduanas"
//   scala-cli run EndpointPe.scala -- anexos 20131312955
//   scala-cli run EndpointPe.scala -- representantes 20131312955
//   scala-cli run EndpointPe.scala -- trabajadores 20131312955
//
// Uso desde tu código:
//   val api = EndpointPe()                          // lee ENDPOINT_API_KEY del entorno
//   val ficha = api.ruc("20131312955")              // ujson.Value con el objeto `data`
//   println(s"${ficha("razon_social").str} ${api.creditosDisponibles}")
//
// Documentación: https://endpoint.pe/docs

import java.net.{URI, URLEncoder}
import java.net.http.{HttpClient, HttpRequest, HttpResponse}
import java.nio.charset.StandardCharsets
import java.time.Duration
import scala.util.{Failure, Success, Try}

/** La API respondió con success=false. `error` es el código estable para comparar en tu
  * código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
  */
final case class EndpointError(status: Int, error: String, mensaje: String, detalles: Map[String, String] = Map.empty)
    extends Exception(s"HTTP $status · $error: $mensaje")

/** Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta. */
final class EndpointPe(
    apiKey: String = sys.env.getOrElse("ENDPOINT_API_KEY", ""),
    baseUrl: String = sys.env.getOrElse("ENDPOINT_BASE_URL", "https://api.endpoint.pe/v1"),
) {
  require(apiKey.nonEmpty, "Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.")

  private val Timeout = Duration.ofSeconds(15)
  private val Reintentos = 3 // solo ante errores de red o 5xx; nunca ante 404 o 422
  private val base = baseUrl.stripSuffix("/")
  private val http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build()

  /** Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta. */
  var creditosDisponibles: Option[Long] = None

  // Empresas (SUNAT)
  def ruc(ruc: String): ujson.Value = get(s"/ruc/${codificar(ruc)}")
  def anexos(ruc: String): ujson.Value = get(s"/ruc/${codificar(ruc)}/anexos")
  def representantes(ruc: String): ujson.Value = get(s"/ruc/${codificar(ruc)}/representantes")
  def trabajadores(ruc: String): ujson.Value = get(s"/ruc/${codificar(ruc)}/trabajadores")
  def empresas(texto: String): ujson.Value = get(s"/empresas?q=${codificar(texto)}")
  // Identidad (RENIEC)
  def dni(dni: String): ujson.Value = get(s"/dni/${codificar(dni)}")
  // Finanzas y ubicación
  def tipoCambio(): ujson.Value = get("/tipo-cambio")
  def ubigeo(codigo: String): ujson.Value = get(s"/ubigeo/${codificar(codigo)}")

  private def get(ruta: String): ujson.Value = {
    val peticion = HttpRequest
      .newBuilder(URI.create(base + ruta))
      .timeout(Timeout)
      .header("Authorization", s"Bearer $apiKey")
      .header("Accept", "application/json")
      .header("User-Agent", "endpoint-pe-ejemplos/scala")
      .GET()
      .build()

    @annotation.tailrec
    def intentar(intento: Int): ujson.Value =
      Try(http.send(peticion, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))) match {
        case Failure(_) if intento < Reintentos =>
          Thread.sleep(1000L << (intento - 1))
          intentar(intento + 1)
        case Failure(e) =>
          throw EndpointError(0, "red", s"No se pudo conectar con la API: ${e.getMessage}")
        case Success(res) if res.statusCode() >= 500 && intento < Reintentos =>
          Thread.sleep(1000L << (intento - 1))
          intentar(intento + 1)
        case Success(res) =>
          res.headers().firstValue("x-credits-remaining").ifPresent(v => creditosDisponibles = v.trim.toLongOption)
          val cuerpo = Try(ujson.read(res.body())).toOption.flatMap(_.objOpt).getOrElse(ujson.Obj().obj)
          val exito = cuerpo.get("success").flatMap(_.boolOpt).getOrElse(false)
          if (res.statusCode() != 200 || !exito || !cuerpo.contains("data")) {
            val detalles = cuerpo
              .get("detalles")
              .flatMap(_.objOpt)
              .map(_.map { case (k, v) => k -> v.strOpt.getOrElse("") }.toMap)
              .getOrElse(Map.empty)
            throw EndpointError(
              res.statusCode(),
              cuerpo.get("error").flatMap(_.strOpt).getOrElse("error"),
              cuerpo.get("message").flatMap(_.strOpt).getOrElse(s"Respuesta inesperada (HTTP ${res.statusCode()})"),
              detalles,
            )
          }
          cuerpo("data")
      }

    intentar(1)
  }

  private def codificar(valor: String): String = URLEncoder.encode(valor, StandardCharsets.UTF_8)
}

// --- Uso desde la terminal ---

val Uso = """Uso: scala-cli run EndpointPe.scala -- <comando> [dato]
            |
            |  ruc <ruc>              Ficha del contribuyente (SUNAT)
            |  dni <dni>              Nombres y apellidos del titular (RENIEC)
            |  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
            |  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
            |  empresas <texto>       Buscar el RUC de una empresa por su razón social
            |  anexos <ruc>           Establecimientos anexos de un RUC
            |  representantes <ruc>   Representantes legales de un RUC
            |  trabajadores <ruc>     Trabajadores declarados por periodo
            |
            |La API key se lee de la variable de entorno ENDPOINT_API_KEY.
            |Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys""".stripMargin

@main def consulta(args: String*): Unit = {
  val comando = args.headOption.getOrElse("")
  val dato = args.lift(1).getOrElse("")
  if (comando.isEmpty || Set("-h", "--help", "ayuda").contains(comando)) {
    println(Uso)
    sys.exit(0)
  }

  val necesitaDato = Map(
    "ruc" -> true, "dni" -> true, "tipo-cambio" -> false, "ubigeo" -> true,
    "empresas" -> true, "anexos" -> true, "representantes" -> true, "trabajadores" -> true,
  )
  necesitaDato.get(comando) match {
    case None =>
      System.err.println(s"Comando desconocido: $comando\n\n$Uso")
      sys.exit(2)
    case Some(true) if dato.isEmpty =>
      System.err.println(s"El comando '$comando' necesita un dato.")
      sys.exit(2)
    case _ => ()
  }

  val api =
    try EndpointPe()
    catch {
      case e: IllegalArgumentException =>
        System.err.println(e.getMessage.stripPrefix("requirement failed: "))
        sys.exit(2)
    }

  try {
    val resultado = comando match {
      case "ruc"            => api.ruc(dato)
      case "dni"            => api.dni(dato)
      case "tipo-cambio"    => api.tipoCambio()
      case "ubigeo"         => api.ubigeo(dato)
      case "empresas"       => api.empresas(dato)
      case "anexos"         => api.anexos(dato)
      case "representantes" => api.representantes(dato)
      case _                => api.trabajadores(dato)
    }
    println(ujson.write(resultado, indent = 2))
    api.creditosDisponibles.foreach(c => System.err.println(s"Créditos disponibles: $c"))
  } catch {
    case e: EndpointError =>
      System.err.println(s"Error HTTP ${e.status} (${e.error}): ${e.mensaje}")
      e.detalles.foreach { case (campo, motivo) => System.err.println(s"  $campo: $motivo") }
      sys.exit(1)
  }
}
