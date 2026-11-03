' endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde VB.NET.
'
' Sin paquetes NuGet: usa HttpClient y System.Text.Json (.NET 6 o superior).
'
' Uso desde la terminal:
'   set ENDPOINT_API_KEY=ep_live_...           (en Linux/macOS: export ENDPOINT_API_KEY=ep_live_...)
'   dotnet run -- ruc 20131312955
'   dotnet run -- dni 45871236
'   dotnet run -- tipo-cambio
'   dotnet run -- ubigeo 150101
'   dotnet run -- empresas "superintendencia aduanas"
'   dotnet run -- anexos 20131312955
'   dotnet run -- representantes 20131312955
'   dotnet run -- trabajadores 20131312955
'
' Uso desde tu código:
'   Dim api As New EndpointPe()                            ' lee ENDPOINT_API_KEY del entorno
'   Dim ficha = Await api.RucAsync("20131312955")          ' JsonNode con el objeto `data`
'   Console.WriteLine($"{ficha("razon_social")} {ficha("estado")} {api.CreditosDisponibles}")
'
' Documentación: https://endpoint.pe/docs

Imports System.Net.Http
Imports System.Net.Http.Headers
Imports System.Text.Encodings.Web
Imports System.Text.Json
Imports System.Text.Json.Nodes

''' <summary>
''' La API respondió con success=false. Error es el código estable para comparar en tu
''' código (no_encontrado, validacion, sin_creditos…); Mensaje es texto en español.
''' </summary>
Public NotInheritable Class EndpointException
    Inherits Exception

    Public ReadOnly Property Status As Integer
    Public ReadOnly Property Error As String
    Public ReadOnly Property Mensaje As String
    Public ReadOnly Property Detalles As IReadOnlyDictionary(Of String, String)

    Public Sub New(status As Integer, [error] As String, mensaje As String, Optional detalles As IReadOnlyDictionary(Of String, String) = Nothing)
        MyBase.New($"HTTP {status} · {[error]}: {mensaje}")
        Me.Status = status
        Me.Error = [error]
        Me.Mensaje = mensaje
        Me.Detalles = If(detalles, New Dictionary(Of String, String)())
    End Sub
End Class

''' <summary>Cliente de la API v1. Cada método devuelve el objeto data de la respuesta.</summary>
Public NotInheritable Class EndpointPe
    Public Const BaseUrlPorDefecto As String = "https://api.endpoint.pe/v1"
    Private Shared ReadOnly Timeout As TimeSpan = TimeSpan.FromSeconds(15)
    Private Const Reintentos As Integer = 3 ' solo ante errores de red o 5xx; nunca ante 404 o 422

    ''' <summary>Opciones para imprimir JSON con sangría y tildes sin escapar.</summary>
    Public Shared ReadOnly Bonito As New JsonSerializerOptions With {
        .WriteIndented = True,
        .Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    }

    Private ReadOnly _http As HttpClient

    ''' <summary>Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.</summary>
    Public Property CreditosDisponibles As Integer?

    Public Sub New(Optional apiKey As String = Nothing, Optional baseUrl As String = Nothing, Optional http As HttpClient = Nothing)
        If apiKey Is Nothing Then apiKey = Environment.GetEnvironmentVariable("ENDPOINT_API_KEY")
        If String.IsNullOrWhiteSpace(apiKey) Then
            Throw New ArgumentException("Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.")
        End If
        If baseUrl Is Nothing Then baseUrl = Environment.GetEnvironmentVariable("ENDPOINT_BASE_URL")
        If String.IsNullOrWhiteSpace(baseUrl) Then baseUrl = BaseUrlPorDefecto

        _http = If(http, New HttpClient())
        _http.BaseAddress = New Uri(baseUrl.TrimEnd("/"c) & "/")
        _http.Timeout = Timeout
        _http.DefaultRequestHeaders.Authorization = New AuthenticationHeaderValue("Bearer", apiKey)
        _http.DefaultRequestHeaders.Accept.Add(New MediaTypeWithQualityHeaderValue("application/json"))
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("endpoint-pe-ejemplos/vbnet")
    End Sub

    ' Empresas (SUNAT)

    ''' <summary>Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.</summary>
    Public Function RucAsync(ruc As String) As Task(Of JsonNode)
        Return GetAsync($"ruc/{Uri.EscapeDataString(ruc)}")
    End Function

    ''' <summary>Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.</summary>
    Public Function AnexosAsync(ruc As String) As Task(Of JsonNode)
        Return GetAsync($"ruc/{Uri.EscapeDataString(ruc)}/anexos")
    End Function

    ''' <summary>Representantes legales con documento, cargo y fecha de nombramiento.</summary>
    Public Function RepresentantesAsync(ruc As String) As Task(Of JsonNode)
        Return GetAsync($"ruc/{Uri.EscapeDataString(ruc)}/representantes")
    End Function

    ''' <summary>Trabajadores, pensionistas y prestadores de servicio declarados por periodo.</summary>
    Public Function TrabajadoresAsync(ruc As String) As Task(Of JsonNode)
        Return GetAsync($"ruc/{Uri.EscapeDataString(ruc)}/trabajadores")
    End Function

    ''' <summary>Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).</summary>
    Public Function EmpresasAsync(texto As String) As Task(Of JsonNode)
        Return GetAsync($"empresas?q={Uri.EscapeDataString(texto)}")
    End Function

    ' Identidad (RENIEC)

    ''' <summary>Nombres y apellidos del titular, dígito verificador y RUC de persona natural.</summary>
    Public Function DniAsync(dni As String) As Task(Of JsonNode)
        Return GetAsync($"dni/{Uri.EscapeDataString(dni)}")
    End Function

    ' Finanzas y ubicación

    ''' <summary>Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.</summary>
    Public Function TipoCambioAsync() As Task(Of JsonNode)
        Return GetAsync("tipo-cambio")
    End Function

    ''' <summary>Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.</summary>
    Public Function UbigeoAsync(codigo As String) As Task(Of JsonNode)
        Return GetAsync($"ubigeo/{Uri.EscapeDataString(codigo)}")
    End Function

    Private Async Function GetAsync(ruta As String) As Task(Of JsonNode)
        Dim intento As Integer = 1
        Do
            Dim respuesta As HttpResponseMessage
            Try
                respuesta = Await _http.GetAsync(ruta)
            Catch e As Exception When TypeOf e Is HttpRequestException OrElse TypeOf e Is TaskCanceledException
                If intento < Reintentos Then
                    Await Task.Delay(TimeSpan.FromSeconds(1 << (intento - 1)))
                    intento += 1
                    Continue Do
                End If
                Throw New EndpointException(0, "red", $"No se pudo conectar con la API: {e.Message}")
            End Try

            Using respuesta
                Dim status As Integer = CInt(respuesta.StatusCode)
                If status >= 500 AndAlso intento < Reintentos Then
                    Await Task.Delay(TimeSpan.FromSeconds(1 << (intento - 1)))
                    intento += 1
                    Continue Do
                End If

                Dim valores As IEnumerable(Of String) = Nothing
                Dim restantes As Integer
                If respuesta.Headers.TryGetValues("X-Credits-Remaining", valores) AndAlso Integer.TryParse(valores.FirstOrDefault(), restantes) Then
                    CreditosDisponibles = restantes
                End If

                Dim texto As String = Await respuesta.Content.ReadAsStringAsync()
                Dim cuerpo As JsonNode = Nothing
                Try
                    cuerpo = JsonNode.Parse(texto)
                Catch ex As JsonException
                    ' cuerpo no JSON
                End Try

                Dim exito As Boolean = cuerpo IsNot Nothing AndAlso cuerpo("success") IsNot Nothing AndAlso cuerpo("success").GetValue(Of Boolean)()
                If status <> 200 OrElse Not exito OrElse cuerpo("data") Is Nothing Then
                    Dim detalles As Dictionary(Of String, String) = Nothing
                    If cuerpo IsNot Nothing AndAlso cuerpo("detalles") IsNot Nothing Then
                        detalles = cuerpo("detalles").AsObject().ToDictionary(Function(p) p.Key, Function(p) If(p.Value?.ToString(), ""))
                    End If
                    Dim codigo As String = If(cuerpo?("error")?.ToString(), "error")
                    Dim mensaje As String = If(cuerpo?("message")?.ToString(), $"Respuesta inesperada (HTTP {status})")
                    Throw New EndpointException(status, codigo, mensaje, detalles)
                End If
                Return cuerpo("data")
            End Using
        Loop
    End Function
End Class

' --- Uso desde la terminal ---

Module Program
    Private Const Uso As String =
"Uso: dotnet run -- <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys"

    Function Main(args As String()) As Integer
        Return EjecutarAsync(args).GetAwaiter().GetResult()
    End Function

    Private Async Function EjecutarAsync(args As String()) As Task(Of Integer)
        Dim comando As String = If(args.Length > 0, args(0), "")
        Dim dato As String = If(args.Length > 1, args(1), "")
        If comando = "" OrElse comando = "-h" OrElse comando = "--help" OrElse comando = "ayuda" Then
            Console.WriteLine(Uso)
            Return 0
        End If

        Dim api As EndpointPe
        Try
            api = New EndpointPe()
        Catch e As ArgumentException
            Console.Error.WriteLine(e.Message)
            Return 2
        End Try

        Dim necesitaDato As New Dictionary(Of String, Boolean) From {
            {"ruc", True}, {"dni", True}, {"tipo-cambio", False}, {"ubigeo", True},
            {"empresas", True}, {"anexos", True}, {"representantes", True}, {"trabajadores", True}
        }
        If Not necesitaDato.ContainsKey(comando) Then
            Console.Error.WriteLine($"Comando desconocido: {comando}{vbLf}{vbLf}{Uso}")
            Return 2
        End If
        If necesitaDato(comando) AndAlso dato = "" Then
            Console.Error.WriteLine($"El comando '{comando}' necesita un dato.")
            Return 2
        End If

        Try
            Dim resultado As JsonNode
            Select Case comando
                Case "ruc" : resultado = Await api.RucAsync(dato)
                Case "dni" : resultado = Await api.DniAsync(dato)
                Case "tipo-cambio" : resultado = Await api.TipoCambioAsync()
                Case "ubigeo" : resultado = Await api.UbigeoAsync(dato)
                Case "empresas" : resultado = Await api.EmpresasAsync(dato)
                Case "anexos" : resultado = Await api.AnexosAsync(dato)
                Case "representantes" : resultado = Await api.RepresentantesAsync(dato)
                Case Else : resultado = Await api.TrabajadoresAsync(dato)
            End Select
            Console.WriteLine(resultado.ToJsonString(EndpointPe.Bonito))
            If api.CreditosDisponibles.HasValue Then
                Console.Error.WriteLine($"Créditos disponibles: {api.CreditosDisponibles.Value}")
            End If
            Return 0
        Catch e As EndpointException
            Console.Error.WriteLine($"Error HTTP {e.Status} ({e.Error}): {e.Mensaje}")
            For Each par In e.Detalles
                Console.Error.WriteLine($"  {par.Key}: {par.Value}")
            Next
            Return 1
        End Try
    End Function
End Module
