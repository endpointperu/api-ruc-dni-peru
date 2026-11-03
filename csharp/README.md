# C# (.NET)

Cliente mínimo de la API de endpoint.pe con `HttpClient` y `System.Text.Json`, sin paquetes NuGet. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- SDK de .NET 8 (el código también compila en .NET 6 y 7 cambiando `TargetFramework` en el `.csproj`).

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys
# En Windows (CMD): set ENDPOINT_API_KEY=ep_live_...   En PowerShell: $env:ENDPOINT_API_KEY="ep_live_..."

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

Copia la clase `EndpointPe` (y `EndpointException`) de `Program.cs`. Los métodos devuelven el objeto `data` como `JsonNode`; si prefieres clases, deserialízalo con `JsonSerializer.Deserialize<Ruc>(nodo)` y propiedades anotadas con `[JsonPropertyName("razon_social")]`.

```csharp
var api = new EndpointPe(); // lee ENDPOINT_API_KEY; también acepta new EndpointPe("ep_live_...")

try
{
    var ficha = await api.RucAsync("20131312955");
    Console.WriteLine($"{ficha["razon_social"]} · {ficha["estado"]} · {ficha["condicion"]}");
}
catch (EndpointException e) when (e.Error == "no_encontrado")
{
    Console.WriteLine("RUC no inscrito");
}

var tc = await api.TipoCambioAsync();
Console.WriteLine($"{tc["fecha"]} compra {tc["compra"]} venta {tc["venta"]}");
Console.WriteLine($"Créditos disponibles: {api.CreditosDisponibles}");
```

Los errores (404, 422, 402…) llegan como `EndpointException` con `Status`, `Error`, `Mensaje` y `Detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## ASP.NET Core

Registra el cliente una sola vez con `IHttpClientFactory` (`services.AddHttpClient<EndpointPe>()`) y pasa el `HttpClient` al constructor. Lee la clave con `builder.Configuration["ENDPOINT_API_KEY"]` desde variables de entorno o *user secrets*, nunca desde `appsettings.json` versionado. Para WinForms o WPF funciona igual: crea una instancia y llama a los métodos con `await`.
