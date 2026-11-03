# Java

Cliente mínimo de la API de endpoint.pe con `java.net.http`, sin Maven ni dependencias. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Java 11 o superior (JDK). Con Java 11+ el archivo se ejecuta directamente, sin compilar.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

java EndpointPe.java ruc 20131312955
java EndpointPe.java dni 45871236
java EndpointPe.java tipo-cambio
java EndpointPe.java ubigeo 150101
java EndpointPe.java empresas "superintendencia aduanas"
java EndpointPe.java anexos 20131312955
java EndpointPe.java representantes 20131312955
java EndpointPe.java trabajadores 20131312955
```

O compílalo como siempre: `javac EndpointPe.java && java EndpointPe ruc 20131312955`.

## Usar en tu proyecto

Los métodos devuelven el objeto `data` como texto JSON. El ejemplo incluye `campo()` para leer un valor de primer nivel sin bibliotecas; en un proyecto real conviene convertirlo a objetos con Jackson o Gson:

```java
EndpointPe api = new EndpointPe(); // lee ENDPOINT_API_KEY; también acepta new EndpointPe("ep_live_...")

try {
    String json = api.ruc("20131312955");
    System.out.println(EndpointPe.campo(json, "razon_social") + " · " + EndpointPe.campo(json, "estado"));

    // Con Jackson:
    // ObjectMapper mapper = new ObjectMapper().configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
    // Ruc ficha = mapper.readValue(json, Ruc.class);
} catch (EndpointPe.EndpointException e) {
    if ("no_encontrado".equals(e.error)) {
        System.out.println("RUC no inscrito");
    } else {
        System.out.println(e.status + " " + e.error + " " + e.mensaje);
    }
}
System.out.println("Créditos disponibles: " + api.creditosDisponibles());
```

Los errores (404, 422, 402…) llegan como `EndpointException` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Spring Boot

Declara el cliente como `@Bean` para reutilizar la conexión, y lee la clave de una propiedad (`endpoint.api-key=${ENDPOINT_API_KEY}`). Si prefieres `RestTemplate` o `WebClient`, basta con enviar la cabecera `Authorization: Bearer …` y mapear el envoltorio `{success, message, data, meta}`; usa `@JsonIgnoreProperties(ignoreUnknown = true)` para que campos nuevos no rompan tu integración.
