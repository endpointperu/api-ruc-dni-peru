# PowerShell

Consulta la API de endpoint.pe desde PowerShell con `Invoke-WebRequest`, sin módulos. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores. Útil para scripts de administración, cargas masivas y automatizaciones en Windows.

## Requisitos

- Windows PowerShell 5.1 (incluido en Windows 10 y 11) o PowerShell 7+ en Windows, Linux o macOS.

## Ejecutar

```powershell
$env:ENDPOINT_API_KEY = "ep_live_..."   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

.\consulta.ps1 ruc 20131312955
.\consulta.ps1 dni 45871236
.\consulta.ps1 tipo-cambio
.\consulta.ps1 ubigeo 150101
.\consulta.ps1 empresas "superintendencia aduanas"
.\consulta.ps1 anexos 20131312955
.\consulta.ps1 representantes 20131312955
.\consulta.ps1 trabajadores 20131312955
```

Si Windows bloquea la ejecución de scripts: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Usar en tus scripts

Carga las funciones con *dot sourcing* y trabaja con objetos de PowerShell:

```powershell
. .\consulta.ps1 -Comando ''   # define las funciones sin ejecutar nada

$ficha = Get-Ruc 20131312955
"$($ficha.razon_social) · $($ficha.estado) · $($ficha.condicion)"

$tc = Get-TipoCambio
"$($tc.fecha): compra $($tc.compra), venta $($tc.venta)"

# Validar una lista de RUC desde un CSV
Import-Csv proveedores.csv | ForEach-Object {
    try {
        $r = Get-Ruc $_.ruc
        [pscustomobject]@{ ruc = $_.ruc; razon_social = $r.razon_social; estado = $r.estado; condicion = $r.condicion }
    } catch {
        [pscustomobject]@{ ruc = $_.ruc; razon_social = ''; estado = 'ERROR'; condicion = $_.Exception.Message }
    }
} | Export-Csv proveedores-validados.csv -NoTypeInformation -Encoding UTF8
```

Los errores de la API (404 `no_encontrado`, 422 `validacion`, 402 `sin_creditos`…) se lanzan como excepciones con el código HTTP y el mensaje en español. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.
