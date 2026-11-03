Attribute VB_Name = "EndpointPe"
' endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Excel (VBA).
'
' Instalación: Alt+F11 → Archivo → Importar archivo → EndpointPe.bas. Guarda el libro como .xlsm.
' Clave: variable de entorno ENDPOINT_API_KEY, o pégala en API_KEY_LOCAL (no compartas el archivo).
'
' Fórmulas disponibles en las celdas:
'   =CONSULTAR_RUC(A2)                       → razón social
'   =CONSULTAR_RUC(A2; "estado")             → ACTIVO
'   =CONSULTAR_RUC(A2; "direccion_completa") → domicilio fiscal
'   =CONSULTAR_DNI(B2)                       → nombre completo
'   =CONSULTAR_DNI(B2; "apellido_paterno")
'   =TIPO_CAMBIO_SUNAT("venta")              → 3.457
'   =UBIGEO_NOMBRE("150101"; "distrito")     → LIMA
'   =BUSCAR_RUC("superintendencia aduanas")  → RUC de la primera coincidencia
'
' Requisitos: Excel 2010 o superior en Windows (usa MSXML2.ServerXMLHTTP.6.0).
' Documentación: https://endpoint.pe/docs

Option Explicit

Private Const BASE_URL As String = "https://api.endpoint.pe/v1"
Private Const API_KEY_LOCAL As String = ""
Private Const TIMEOUT_MS As Long = 15000

' Guarda las respuestas de la sesión para no repetir consultas al recalcular la hoja.
Private cache As Object

Private Function ApiKey() As String
    ApiKey = Environ$("ENDPOINT_API_KEY")
    If Len(ApiKey) = 0 Then ApiKey = API_KEY_LOCAL
End Function

' --- Fórmulas para la hoja -------------------------------------------------

' Ficha del contribuyente (SUNAT). campo: razon_social, estado, condicion, direccion_completa,
' tipo_contribuyente, departamento, provincia, distrito, ubigeo, cantidad_trabajadores…
Public Function CONSULTAR_RUC(ByVal ruc As String, Optional ByVal campo As String = "razon_social") As Variant
    CONSULTAR_RUC = Consultar("/ruc/" & SoloDigitos(ruc), campo)
End Function

' Nombres y apellidos (RENIEC). campo: nombre_completo, nombres, apellido_paterno, apellido_materno, ruc.
Public Function CONSULTAR_DNI(ByVal dni As String, Optional ByVal campo As String = "nombre_completo") As Variant
    CONSULTAR_DNI = Consultar("/dni/" & Right$("00000000" & SoloDigitos(dni), 8), campo)
End Function

' Tipo de cambio del dólar publicado por SUNAT. campo: venta, compra, fecha.
Public Function TIPO_CAMBIO_SUNAT(Optional ByVal campo As String = "venta") As Variant
    TIPO_CAMBIO_SUNAT = Consultar("/tipo-cambio", campo)
End Function

' Departamento, provincia o distrito de un código de ubigeo. campo: distrito, provincia, departamento, ubigeo_reniec.
Public Function UBIGEO_NOMBRE(ByVal codigo As String, Optional ByVal campo As String = "distrito") As Variant
    UBIGEO_NOMBRE = Consultar("/ubigeo/" & Right$("000000" & SoloDigitos(codigo), 6), campo)
End Function

' RUC de la primera empresa que coincide con la razón social buscada.
Public Function BUSCAR_RUC(ByVal razonSocial As String) As Variant
    BUSCAR_RUC = Consultar("/empresas?q=" & UrlEncode(Trim$(razonSocial)), "ruc")
End Function

' --- Petición HTTP ---------------------------------------------------------

' Hace la consulta (con caché) y devuelve el valor del campo pedido, o un texto de error.
Private Function Consultar(ByVal ruta As String, ByVal campo As String) As Variant
    Dim json As String, status As Long, valor As String

    If Len(ApiKey()) = 0 Then
        Consultar = "Falta la API key (ENDPOINT_API_KEY)"
        Exit Function
    End If
    If cache Is Nothing Then Set cache = CreateObject("Scripting.Dictionary")

    If cache.Exists(ruta) Then
        json = cache(ruta)
        status = 200
    Else
        json = EndpointGet(ruta, status)
        If status = 200 Then cache(ruta) = json
    End If

    If status = 0 Then
        Consultar = "Sin conexión con la API"
    ElseIf status <> 200 Then
        ' error: no_encontrado, validacion, sin_creditos… (ver https://endpoint.pe/docs/errores)
        Consultar = "Error " & status & " (" & ValorJson(json, "error") & "): " & ValorJson(json, "message")
    Else
        valor = ValorJson(json, campo)
        If campo = "compra" Or campo = "venta" Then
            Consultar = Val(valor)
        Else
            Consultar = valor
        End If
    End If
End Function

' GET a la ruta indicada. Devuelve el JSON completo; status recibe el código HTTP (0 si no hubo conexión).
Public Function EndpointGet(ByVal ruta As String, ByRef status As Long) As String
    Dim http As Object
    On Error GoTo fallo
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.SetTimeouts 10000, 10000, TIMEOUT_MS, TIMEOUT_MS
    http.Open "GET", BASE_URL & ruta, False
    http.SetRequestHeader "Authorization", "Bearer " & ApiKey()
    http.SetRequestHeader "Accept", "application/json"
    http.SetRequestHeader "User-Agent", "endpoint-pe-ejemplos/vba"
    http.Send
    status = http.Status
    EndpointGet = http.ResponseText
    Exit Function
fallo:
    status = 0
    EndpointGet = ""
End Function

' --- Utilidades ------------------------------------------------------------

' Valor de un campo de primer nivel del JSON: texto sin comillas o el literal (número, true, false).
' Devuelve "" si no existe o es null. Suficiente para los campos de `data`; para listas usa VBA-JSON.
Public Function ValorJson(ByVal json As String, ByVal campo As String) As String
    Dim p As Long, q As Long, c As String, valor As String

    p = InStr(1, json, """" & campo & """")
    If p = 0 Then Exit Function
    p = InStr(p + Len(campo) + 2, json, ":")
    If p = 0 Then Exit Function
    p = p + 1
    Do While Mid$(json, p, 1) = " ": p = p + 1: Loop

    If Mid$(json, p, 1) = """" Then
        p = p + 1
        Do While p <= Len(json)
            c = Mid$(json, p, 1)
            If c = "\" Then
                valor = valor & Mid$(json, p + 1, 1)   ' \" \\ \/ (simplificado)
                p = p + 2
            ElseIf c = """" Then
                Exit Do
            Else
                valor = valor & c
                p = p + 1
            End If
        Loop
    Else
        q = p
        Do While q <= Len(json)
            If InStr(",}]", Mid$(json, q, 1)) > 0 Then Exit Do
            q = q + 1
        Loop
        valor = Trim$(Mid$(json, p, q - p))
        If valor = "null" Then valor = ""
    End If
    ValorJson = valor
End Function

' Deja solo los dígitos (quita espacios, guiones y puntos que suelen venir de formularios).
Private Function SoloDigitos(ByVal texto As String) As String
    Dim i As Long, c As String
    For i = 1 To Len(texto)
        c = Mid$(texto, i, 1)
        If c >= "0" And c <= "9" Then SoloDigitos = SoloDigitos & c
    Next i
End Function

' Codifica un texto para la query string. Excel 2013+ trae EncodeURL; antes, codificación básica ASCII.
Private Function UrlEncode(ByVal texto As String) As String
    Dim i As Long, c As String
    On Error GoTo basico
    UrlEncode = Application.WorksheetFunction.EncodeURL(texto)
    Exit Function
basico:
    For i = 1 To Len(texto)
        c = Mid$(texto, i, 1)
        If (c >= "a" And c <= "z") Or (c >= "A" And c <= "Z") Or (c >= "0" And c <= "9") Or InStr("-_.~", c) > 0 Then
            UrlEncode = UrlEncode & c
        ElseIf AscW(c) < 128 Then
            UrlEncode = UrlEncode & "%" & Right$("0" & Hex$(AscW(c)), 2)
        Else
            UrlEncode = UrlEncode & "%20"
        End If
    Next i
End Function
