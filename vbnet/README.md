# VB.NET

Cliente mínimo de la API de endpoint.pe con `HttpClient` y `System.Text.Json`, sin paquetes NuGet. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- SDK de .NET 8 (también compila en .NET 6 y 7 cambiando `TargetFramework` en el `.vbproj`).

## Ejecutar

```powershell
$env:ENDPOINT_API_KEY = "ep_live_..."   # tu clave, creada en https://app.endpoint.pe/panel/api-keys
# En CMD: set ENDPOINT_API_KEY=ep_live_...   En Linux/macOS: export ENDPOINT_API_KEY=ep_live_...

dotnet run -- ruc 20131312955
dotnet run -- dni 45871236
dotnet run -- tipo-cambio
dotnet run -- ubigeo 150101
dotnet run -- empresas "superintendencia aduanas"
dotnet run -- anexos 20131312955
dotnet run -- representantes 20131312955
dotnet run -- trabajadores 20131312955
```

## Usar en tu proyecto

Copia las clases `EndpointPe` y `EndpointException` de `Program.vb`. Los métodos devuelven el objeto `data` como `JsonNode`:

```vb
Dim api As New EndpointPe() ' lee ENDPOINT_API_KEY; también acepta New EndpointPe("ep_live_...")

Try
    Dim ficha = Await api.RucAsync("20131312955")
    Console.WriteLine($"{ficha("razon_social")} · {ficha("estado")} · {ficha("condicion")}")
Catch e As EndpointException When e.Error = "no_encontrado"
    Console.WriteLine("RUC no inscrito")
End Try

Dim tc = Await api.TipoCambioAsync()
Console.WriteLine($"{tc("fecha")} compra {tc("compra")} venta {tc("venta")}")
```

Los errores (404, 422, 402…) llegan como `EndpointException` con `Status`, `Error`, `Mensaje` y `Detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## .NET Framework 4.x (VB.NET clásico)

Si tu sistema está en .NET Framework 4.6 o superior, `HttpClient` funciona igual; para leer el JSON instala `Newtonsoft.Json` y usa `JObject.Parse(texto)("data")("razon_social")`. Antes de llamar, activa TLS 1.2: `ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12`.
