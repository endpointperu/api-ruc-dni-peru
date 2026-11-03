# Delphi (Object Pascal)

Cliente mínimo de la API de endpoint.pe con `System.Net.HttpClient` y `System.JSON`, sin componentes de terceros. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores. Pensado para los sistemas de facturación y gestión que siguen en Delphi.

## Requisitos

- Delphi 10.3 Rio o superior (Community Edition incluida). Compila para Windows, macOS y Linux.

## Compilar y ejecutar

Abre `EndpointPe.dpr` en el IDE y compila, o desde la línea de comandos:

```bat
dcc32 EndpointPe.dpr

set ENDPOINT_API_KEY=ep_live_...   REM tu clave, creada en https://app.endpoint.pe/panel/api-keys

EndpointPe ruc 20131312955
EndpointPe dni 45871236
EndpointPe tipo-cambio
EndpointPe ubigeo 150101
EndpointPe empresas "superintendencia aduanas"
EndpointPe anexos 20131312955
EndpointPe representantes 20131312955
EndpointPe trabajadores 20131312955
```

## Usar en tu proyecto

Copia la clase `TEndpointPe` (y `EEndpoint`) a una unidad. Los métodos devuelven el objeto `data` como `TJSONObject`, que debes liberar:

```pascal
var
  Api: TEndpointPe;
  Ficha: TJSONObject;
begin
  Api := TEndpointPe.Create; // lee ENDPOINT_API_KEY; también acepta TEndpointPe.Create('ep_live_...')
  try
    try
      Ficha := Api.Ruc('20131312955');
      try
        ShowMessage(Ficha.GetValue<string>('razon_social') + ' · ' + Ficha.GetValue<string>('estado'));
        // null en el JSON: usa GetValue<string>('nombre_comercial', '') para un valor por defecto
      finally
        Ficha.Free;
      end;
    except
      on E: EEndpoint do
        if E.Error = 'no_encontrado' then
          ShowMessage('RUC no inscrito')
        else
          ShowMessage(E.Message); // HTTP 422 · validacion: …
    end;
  finally
    Api.Free;
  end;
end;
```

Los errores (404, 422, 402…) llegan como `EEndpoint` con `Status`, `Error` y `Mensaje`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Delphi 7, 2007 y XE (Indy)

En versiones anteriores a 10 usa `TIdHTTP` con `TIdSSLIOHandlerSocketOpenSSL` (necesitas `libeay32.dll` y `ssleay32.dll` de OpenSSL 1.0.2 junto al ejecutable, con `SSLOptions.SSLVersions := [sslvTLSv1_2]`):

```pascal
IdHTTP1.Request.CustomHeaders.Values['Authorization'] := 'Bearer ' + ApiKey;
IdHTTP1.Request.Accept := 'application/json';
Json := IdHTTP1.Get('https://api.endpoint.pe/v1/ruc/20131312955');
```

Para leer el JSON en esas versiones, [SuperObject](https://github.com/hgourvest/superobject) o [lkJSON](https://sourceforge.net/projects/lkjson/) funcionan bien.
