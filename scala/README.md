# Scala 3

Cliente mínimo de la API de endpoint.pe con `java.net.http` y [uJson](https://com-lihaoyi.github.io/upickle/), ejecutable con [Scala CLI](https://scala-cli.virtuslab.org/) sin crear un proyecto sbt. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Scala CLI (`scala-cli`) y JDK 11 o superior. Las dependencias se resuelven solas desde las directivas `//> using` del archivo.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

scala-cli run EndpointPe.scala -- ruc 20131312955
scala-cli run EndpointPe.scala -- dni 45871236
scala-cli run EndpointPe.scala -- tipo-cambio
scala-cli run EndpointPe.scala -- ubigeo 150101
scala-cli run EndpointPe.scala -- empresas "superintendencia aduanas"
scala-cli run EndpointPe.scala -- anexos 20131312955
scala-cli run EndpointPe.scala -- representantes 20131312955
scala-cli run EndpointPe.scala -- trabajadores 20131312955
```

## Usar en tu proyecto

En sbt agrega `libraryDependencies += "com.lihaoyi" %% "ujson" % "4.0.2"` y copia la clase `EndpointPe` (y `EndpointError`):

```scala
val api = EndpointPe() // lee ENDPOINT_API_KEY; también acepta EndpointPe("ep_live_...")

try {
  val ficha = api.ruc("20131312955")
  println(s"${ficha("razon_social").str} · ${ficha("estado").str} · ${ficha("condicion").str}")
} catch {
  case e: EndpointError if e.error == "no_encontrado" => println("RUC no inscrito")
}

val tc = api.tipoCambio()
println(s"${tc("fecha").str} compra ${tc("compra").num} venta ${tc("venta").num}")
```

Los métodos devuelven el objeto `data` como `ujson.Value`; si prefieres case classes, usa uPickle (`read[Ruc](ficha)`) con `null` mapeado a `Option`. Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

Si tu proyecto usa Akka HTTP, Play WS o sttp, basta con la cabecera `Authorization: Bearer …` y leer `success`, `data` y `error` del JSON.
