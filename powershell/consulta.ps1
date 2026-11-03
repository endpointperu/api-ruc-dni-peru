<#
.SYNOPSIS
  endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde PowerShell.

.DESCRIPTION
  Sin módulos adicionales: usa Invoke-WebRequest y ConvertFrom-Json. Funciona en Windows PowerShell 5.1
  y en PowerShell 7+ (Windows, Linux y macOS).

.EXAMPLE
  $env:ENDPOINT_API_KEY = "ep_live_..."
  .\consulta.ps1 ruc 20131312955
  .\consulta.ps1 dni 45871236
  .\consulta.ps1 tipo-cambio
  .\consulta.ps1 ubigeo 150101
  .\consulta.ps1 empresas "superintendencia aduanas"
  .\consulta.ps1 anexos 20131312955
  .\consulta.ps1 representantes 20131312955
  .\consulta.ps1 trabajadores 20131312955

.NOTES
  Documentación: https://endpoint.pe/docs
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Comando,
    [Parameter(Position = 1)] [string] $Dato
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 no usa TLS 1.2 por defecto.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$BaseUrl = if ($env:ENDPOINT_BASE_URL) { $env:ENDPOINT_BASE_URL.TrimEnd('/') } else { 'https://api.endpoint.pe/v1' }
$ApiKey = $env:ENDPOINT_API_KEY
$TimeoutSeg = 15
$Reintentos = 3   # solo ante errores de red o 5xx; nunca ante 404 o 422
$script:CreditosDisponibles = $null

# Hace la petición GET y devuelve el objeto `data` de la respuesta.
# Ante un error de la API lanza una excepción con el código HTTP, el campo `error` y el `message`.
function Invoke-EndpointPe {
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [hashtable] $Parametros
    )
    $uri = "$BaseUrl$Ruta"
    if ($Parametros) {
        $pares = foreach ($p in $Parametros.GetEnumerator()) { "$($p.Key)=$([uri]::EscapeDataString([string]$p.Value))" }
        $uri += '?' + ($pares -join '&')
    }
    $cabeceras = @{ Authorization = "Bearer $ApiKey"; Accept = 'application/json'; 'User-Agent' = 'endpoint-pe-ejemplos/powershell' }

    for ($intento = 1; $intento -le $Reintentos; $intento++) {
        try {
            $respuesta = Invoke-WebRequest -Uri $uri -Headers $cabeceras -TimeoutSec $TimeoutSeg -UseBasicParsing
            $restantes = @($respuesta.Headers['X-Credits-Remaining'])[0]
            if ($restantes) { $script:CreditosDisponibles = [int]$restantes }
            $cuerpo = $respuesta.Content | ConvertFrom-Json
            if (-not $cuerpo.success) { throw "Respuesta inesperada de la API." }
            return $cuerpo.data
        }
        catch {
            $http = $_.Exception.Response
            $status = if ($http) { [int]$http.StatusCode } else { 0 }
            if (($status -eq 0 -or $status -ge 500) -and $intento -lt $Reintentos) {
                Start-Sleep -Seconds ([math]::Pow(2, $intento - 1))
                continue
            }
            if ($status -eq 0) { throw "No se pudo conectar con la API: $($_.Exception.Message)" }

            # El cuerpo del error: PowerShell 7 lo trae en ErrorDetails; en 5.1 hay que leer el stream.
            $texto = $_.ErrorDetails.Message
            if (-not $texto -and $http -and $http.GetType().GetMethod('GetResponseStream')) {
                $lector = New-Object IO.StreamReader($http.GetResponseStream())
                $texto = $lector.ReadToEnd()
                $lector.Close()
            }
            $error_ = try { $texto | ConvertFrom-Json } catch { $null }
            $codigo = if ($error_.error) { $error_.error } else { 'error' }
            $mensaje = if ($error_.message) { $error_.message } else { "Respuesta inesperada (HTTP $status)" }
            $detalle = ''
            if ($error_.detalles) {
                $detalle = "`n" + (($error_.detalles.PSObject.Properties | ForEach-Object { "  $($_.Name): $($_.Value)" }) -join "`n")
            }
            throw "Error HTTP $status ($codigo): $mensaje$detalle"
        }
    }
}

# Empresas (SUNAT)
function Get-Ruc            { param([Parameter(Mandatory)][string]$Ruc)   Invoke-EndpointPe "/ruc/$([uri]::EscapeDataString($Ruc))" }
function Get-Anexos         { param([Parameter(Mandatory)][string]$Ruc)   Invoke-EndpointPe "/ruc/$([uri]::EscapeDataString($Ruc))/anexos" }
function Get-Representantes { param([Parameter(Mandatory)][string]$Ruc)   Invoke-EndpointPe "/ruc/$([uri]::EscapeDataString($Ruc))/representantes" }
function Get-Trabajadores   { param([Parameter(Mandatory)][string]$Ruc)   Invoke-EndpointPe "/ruc/$([uri]::EscapeDataString($Ruc))/trabajadores" }
function Find-Empresa       { param([Parameter(Mandatory)][string]$Texto) Invoke-EndpointPe '/empresas' @{ q = $Texto } }
# Identidad (RENIEC)
function Get-Dni            { param([Parameter(Mandatory)][string]$Dni)   Invoke-EndpointPe "/dni/$([uri]::EscapeDataString($Dni))" }
# Finanzas y ubicación
function Get-TipoCambio     { Invoke-EndpointPe '/tipo-cambio' }
function Get-Ubigeo         { param([Parameter(Mandatory)][string]$Codigo) Invoke-EndpointPe "/ubigeo/$([uri]::EscapeDataString($Codigo))" }

# --- Uso desde la terminal ---

$Uso = @'
Uso: .\consulta.ps1 <comando> [dato]

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
'@

if (-not $Comando -or $Comando -in '-h', '--help', 'ayuda') {
    Write-Host $Uso
    exit 0
}
if (-not $ApiKey) {
    Write-Error 'Falta la API key: $env:ENDPOINT_API_KEY = "ep_live_..."'
    exit 2
}

$comandos = @{
    'ruc'            = @{ Funcion = { Get-Ruc $Dato };            NecesitaDato = $true }
    'dni'            = @{ Funcion = { Get-Dni $Dato };            NecesitaDato = $true }
    'tipo-cambio'    = @{ Funcion = { Get-TipoCambio };           NecesitaDato = $false }
    'ubigeo'         = @{ Funcion = { Get-Ubigeo $Dato };         NecesitaDato = $true }
    'empresas'       = @{ Funcion = { Find-Empresa $Dato };       NecesitaDato = $true }
    'anexos'         = @{ Funcion = { Get-Anexos $Dato };         NecesitaDato = $true }
    'representantes' = @{ Funcion = { Get-Representantes $Dato }; NecesitaDato = $true }
    'trabajadores'   = @{ Funcion = { Get-Trabajadores $Dato };   NecesitaDato = $true }
}
if (-not $comandos.ContainsKey($Comando)) {
    Write-Error "Comando desconocido: $Comando`n`n$Uso"
    exit 2
}
if ($comandos[$Comando].NecesitaDato -and -not $Dato) {
    Write-Error "El comando '$Comando' necesita un dato."
    exit 2
}

try {
    $resultado = & $comandos[$Comando].Funcion
    $resultado | ConvertTo-Json -Depth 8
    if ($null -ne $script:CreditosDisponibles) {
        Write-Host "Créditos disponibles: $script:CreditosDisponibles" -ForegroundColor DarkGray
    }
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
