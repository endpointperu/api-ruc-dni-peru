# Kotlin

Cliente mínimo de la API de endpoint.pe con `java.net.http`, sin Gradle ni dependencias. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Kotlin 1.6 o superior (`kotlinc`) y JDK 11 o superior.

## Ejecutar

```bash
kotlinc EndpointPe.kt -include-runtime -d consulta.jar

export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

java -jar consulta.jar ruc 20131312955
java -jar consulta.jar dni 45871236
java -jar consulta.jar tipo-cambio
java -jar consulta.jar ubigeo 150101
java -jar consulta.jar empresas "superintendencia aduanas"
java -jar consulta.jar anexos 20131312955
java -jar consulta.jar representantes 20131312955
java -jar consulta.jar trabajadores 20131312955
```

## Usar en tu proyecto

Los métodos devuelven el objeto `data` como texto JSON. El ejemplo incluye `EndpointPe.campo()` para leer un valor de primer nivel sin bibliotecas; en un proyecto real conviene convertirlo con `kotlinx.serialization` (`Json { ignoreUnknownKeys = true }`), Moshi o Jackson.

```kotlin
val api = EndpointPe() // lee ENDPOINT_API_KEY; también acepta EndpointPe("ep_live_...")

try {
    val json = api.ruc("20131312955")
    println("${EndpointPe.campo(json, "razon_social")} · ${EndpointPe.campo(json, "estado")}")
} catch (e: EndpointException) {
    if (e.error == "no_encontrado") println("RUC no inscrito") else println("${e.status} ${e.error} ${e.mensaje}")
}
println("Créditos disponibles: ${api.creditosDisponibles}")
```

## Android

Haz la consulta desde tu backend, no desde la app: una API key dentro de un APK puede extraerse. Si aun así necesitas llamar desde Android (por ejemplo, en una app interna), usa OkHttp o Ktor con la cabecera `Authorization: Bearer …` y ejecuta la llamada fuera del hilo principal (coroutines con `Dispatchers.IO`).
