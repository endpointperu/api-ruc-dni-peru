// endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde C#.
//
// Sin paquetes NuGet: usa HttpClient y System.Text.Json (.NET 6 o superior).
//
// Uso desde la terminal:
//   export ENDPOINT_API_KEY=ep_live_...        (en Windows: set ENDPOINT_API_KEY=ep_live_...)
//   dotnet run -- ruc 20131312955
//   dotnet run -- dni 45871236
//   dotnet run -- tipo-cambio
//   dotnet run -- ubigeo 150101
//   dotnet run -- empresas "superintendencia aduanas"
//   dotnet run -- anexos 20131312955
//   dotnet run -- representantes 20131312955
//   dotnet run -- trabajadores 20131312955
//
// Uso desde tu código:
//   var api = new EndpointPe();                       // lee ENDPOINT_API_KEY del entorno
//   var ficha = await api.RucAsync("20131312955");    // JsonNode con el objeto `data`
//   Console.WriteLine($"{ficha["razon_social"]} {ficha["estado"]} {api.CreditosDisponibles}");
//
// Documentación: https://endpoint.pe/docs

using System.Net.Http.Headers;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

// --- Uso desde la terminal ---

const string Uso = """
Uso: dotnet run -- <comando> [dato]

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
""";

var comando = args.Length > 0 ? args[0] : "";
var dato = args.Length > 1 ? args[1] : "";
if (comando is "" or "-h" or "--help" or "ayuda")
{
    Console.WriteLine(Uso);
    return 0;
}

EndpointPe api;
try
{
    api = new EndpointPe();
}
catch (ArgumentException e)
{
    Console.Error.WriteLine(e.Message);
    return 2;
}

// comando -> (función, necesita dato)
var comandos = new Dictionary<string, (Func<string, Task<JsonNode>> Funcion, bool NecesitaDato)>
{
    ["ruc"] = (d => api.RucAsync(d), true),
    ["dni"] = (d => api.DniAsync(d), true),
    ["tipo-cambio"] = (_ => api.TipoCambioAsync(), false),
    ["ubigeo"] = (d => api.UbigeoAsync(d), true),
    ["empresas"] = (d => api.EmpresasAsync(d), true),
    ["anexos"] = (d => api.AnexosAsync(d), true),
    ["representantes"] = (d => api.RepresentantesAsync(d), true),
    ["trabajadores"] = (d => api.TrabajadoresAsync(d), true),
};
if (!comandos.TryGetValue(comando, out var entrada))
{
    Console.Error.WriteLine($"Comando desconocido: {comando}\n\n{Uso}");
    return 2;
}
if (entrada.NecesitaDato && dato == "")
{
    Console.Error.WriteLine($"El comando '{comando}' necesita un dato.");
    return 2;
}

try
{
    var resultado = await entrada.Funcion(dato);
    Console.WriteLine(resultado.ToJsonString(EndpointPe.Bonito));
    if (api.CreditosDisponibles is int restantes)
    {
        Console.Error.WriteLine($"Créditos disponibles: {restantes}");
    }
    return 0;
}
catch (EndpointException e)
{
    Console.Error.WriteLine($"Error HTTP {e.Status} ({e.Error}): {e.Mensaje}");
    foreach (var (campo, motivo) in e.Detalles)
    {
        Console.Error.WriteLine($"  {campo}: {motivo}");
    }
    return 1;
}

/// <summary>
/// La API respondió con success=false. <c>Error</c> es el código estable para comparar en tu
/// código (no_encontrado, validacion, sin_creditos…); <c>Mensaje</c> es texto en español.
/// </summary>
public sealed class EndpointException : Exception
{
    public int Status { get; }
    public string Error { get; }
    public string Mensaje { get; }
    public IReadOnlyDictionary<string, string> Detalles { get; }

    public EndpointException(int status, string error, string mensaje, IReadOnlyDictionary<string, string>? detalles = null)
        : base($"HTTP {status} · {error}: {mensaje}")
    {
        Status = status;
        Error = error;
        Mensaje = mensaje;
        Detalles = detalles ?? new Dictionary<string, string>();
    }
}

/// <summary>Cliente de la API v1. Cada método devuelve el objeto <c>data</c> de la respuesta.</summary>
public sealed class EndpointPe
{
    public const string BaseUrlPorDefecto = "https://api.endpoint.pe/v1";
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(15);
    private const int Reintentos = 3; // solo ante errores de red o 5xx; nunca ante 404 o 422

    /// <summary>Opciones para imprimir JSON con sangría y tildes sin escapar.</summary>
    public static readonly JsonSerializerOptions Bonito = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly HttpClient _http;

    /// <summary>Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.</summary>
    public int? CreditosDisponibles { get; private set; }

    public EndpointPe(string? apiKey = null, string? baseUrl = null, HttpClient? http = null)
    {
        apiKey ??= Environment.GetEnvironmentVariable("ENDPOINT_API_KEY");
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new ArgumentException("Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.");
        }
        baseUrl ??= Environment.GetEnvironmentVariable("ENDPOINT_BASE_URL");
        if (string.IsNullOrWhiteSpace(baseUrl)) baseUrl = BaseUrlPorDefecto;

        _http = http ?? new HttpClient();
        _http.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
        _http.Timeout = Timeout;
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        _http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("endpoint-pe-ejemplos/csharp");
    }

    // Empresas (SUNAT)

    /// <summary>Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.</summary>
    public Task<JsonNode> RucAsync(string ruc) => GetAsync($"ruc/{Uri.EscapeDataString(ruc)}");

    /// <summary>Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.</summary>
    public Task<JsonNode> AnexosAsync(string ruc) => GetAsync($"ruc/{Uri.EscapeDataString(ruc)}/anexos");

    /// <summary>Representantes legales con documento, cargo y fecha de nombramiento.</summary>
    public Task<JsonNode> RepresentantesAsync(string ruc) => GetAsync($"ruc/{Uri.EscapeDataString(ruc)}/representantes");

    /// <summary>Trabajadores, pensionistas y prestadores de servicio declarados por periodo.</summary>
    public Task<JsonNode> TrabajadoresAsync(string ruc) => GetAsync($"ruc/{Uri.EscapeDataString(ruc)}/trabajadores");

    /// <summary>Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).</summary>
    public Task<JsonNode> EmpresasAsync(string texto) => GetAsync($"empresas?q={Uri.EscapeDataString(texto)}");

    // Identidad (RENIEC)

    /// <summary>Nombres y apellidos del titular, dígito verificador y RUC de persona natural.</summary>
    public Task<JsonNode> DniAsync(string dni) => GetAsync($"dni/{Uri.EscapeDataString(dni)}");

    // Finanzas y ubicación

    /// <summary>Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.</summary>
    public Task<JsonNode> TipoCambioAsync() => GetAsync("tipo-cambio");

    /// <summary>Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.</summary>
    public Task<JsonNode> UbigeoAsync(string codigo) => GetAsync($"ubigeo/{Uri.EscapeDataString(codigo)}");

    private async Task<JsonNode> GetAsync(string ruta)
    {
        for (var intento = 1; ; intento++)
        {
            HttpResponseMessage respuesta;
            try
            {
                respuesta = await _http.GetAsync(ruta);
            }
            catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
            {
                if (intento < Reintentos)
                {
                    await Task.Delay(TimeSpan.FromSeconds(1 << (intento - 1)));
                    continue;
                }
                throw new EndpointException(0, "red", $"No se pudo conectar con la API: {e.Message}");
            }

            using (respuesta)
            {
                var status = (int)respuesta.StatusCode;
                if (status >= 500 && intento < Reintentos)
                {
                    await Task.Delay(TimeSpan.FromSeconds(1 << (intento - 1)));
                    continue;
                }

                if (respuesta.Headers.TryGetValues("X-Credits-Remaining", out var valores)
                    && int.TryParse(valores.FirstOrDefault(), out var restantes))
                {
                    CreditosDisponibles = restantes;
                }

                var texto = await respuesta.Content.ReadAsStringAsync();
                JsonNode? cuerpo = null;
                try { cuerpo = JsonNode.Parse(texto); } catch (JsonException) { /* cuerpo no JSON */ }

                if (status != 200 || cuerpo?["success"]?.GetValue<bool>() != true || cuerpo["data"] is null)
                {
                    var detalles = cuerpo?["detalles"]?.AsObject()
                        .ToDictionary(p => p.Key, p => p.Value?.ToString() ?? "");
                    throw new EndpointException(
                        status,
                        cuerpo?["error"]?.ToString() ?? "error",
                        cuerpo?["message"]?.ToString() ?? $"Respuesta inesperada (HTTP {status})",
                        detalles);
                }
                return cuerpo["data"]!;
            }
        }
    }
}
