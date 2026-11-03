program EndpointPe;

{
  endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Delphi.

  Sin componentes de terceros: System.Net.HttpClient y System.JSON (Delphi 10.3 Rio o superior,
  Windows, macOS y Linux). Para Delphi 7 a XE, ver README (Indy + OpenSSL).

  Compilar y ejecutar (consola):
    dcc32 EndpointPe.dpr          (o abre el .dpr en el IDE y compila)
    set ENDPOINT_API_KEY=ep_live_...
    EndpointPe ruc 20131312955
    EndpointPe dni 45871236
    EndpointPe tipo-cambio
    EndpointPe ubigeo 150101
    EndpointPe empresas "superintendencia aduanas"
    EndpointPe anexos 20131312955
    EndpointPe representantes 20131312955
    EndpointPe trabajadores 20131312955

  Uso desde tu código:
    Api := TEndpointPe.Create;                     // lee ENDPOINT_API_KEY del entorno
    Datos := Api.Ruc('20131312955');               // TJSONObject con el objeto `data` (liberar)
    Writeln(Datos.GetValue<string>('razon_social'));

  Documentación: https://endpoint.pe/docs
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.NetEncoding,
  System.Net.URLClient,
  System.Net.HttpClient
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const
  BASE_URL_POR_DEFECTO = 'https://api.endpoint.pe/v1';
  TIMEOUT_MS = 15000;
  REINTENTOS = 3; // solo ante errores de red o 5xx; nunca ante 404 o 422

type
  { La API respondió con success=false. Error es el código estable para comparar en tu
    código (no_encontrado, validacion, sin_creditos…); Mensaje es texto en español. }
  EEndpoint = class(Exception)
  public
    Status: Integer;
    Error: string;
    Mensaje: string;
    constructor Create(AStatus: Integer; const AError, AMensaje: string);
  end;

  { Cliente de la API v1. Cada método devuelve el objeto `data` como TJSONObject,
    que el llamador debe liberar. }
  TEndpointPe = class
  private
    FApiKey: string;
    FBaseUrl: string;
    FHttp: THTTPClient;
    FCreditosDisponibles: Integer;
    function Get(const Ruta: string): TJSONObject;
    class function Codificar(const Valor: string): string;
  public
    constructor Create(const ApiKey: string = ''; const BaseUrl: string = '');
    destructor Destroy; override;
    // Empresas (SUNAT)
    function Ruc(const ARuc: string): TJSONObject;
    function Anexos(const ARuc: string): TJSONObject;
    function Representantes(const ARuc: string): TJSONObject;
    function Trabajadores(const ARuc: string): TJSONObject;
    function Empresas(const Texto: string): TJSONObject;
    // Identidad (RENIEC)
    function Dni(const ADni: string): TJSONObject;
    // Finanzas y ubicación
    function TipoCambio: TJSONObject;
    function Ubigeo(const Codigo: string): TJSONObject;
    { Créditos que quedan (suscripción + prepago); -1 hasta la primera respuesta. }
    property CreditosDisponibles: Integer read FCreditosDisponibles;
  end;

{ EEndpoint }

constructor EEndpoint.Create(AStatus: Integer; const AError, AMensaje: string);
begin
  inherited CreateFmt('HTTP %d · %s: %s', [AStatus, AError, AMensaje]);
  Status := AStatus;
  Error := AError;
  Mensaje := AMensaje;
end;

{ TEndpointPe }

constructor TEndpointPe.Create(const ApiKey, BaseUrl: string);
begin
  inherited Create;
  FApiKey := ApiKey;
  if FApiKey = '' then
    FApiKey := GetEnvironmentVariable('ENDPOINT_API_KEY');
  if FApiKey = '' then
    raise EEndpoint.Create(0, 'configuracion', 'Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.');
  FBaseUrl := BaseUrl;
  if FBaseUrl = '' then
    FBaseUrl := GetEnvironmentVariable('ENDPOINT_BASE_URL');
  if FBaseUrl = '' then
    FBaseUrl := BASE_URL_POR_DEFECTO;
  FBaseUrl := FBaseUrl.TrimRight(['/']);
  FCreditosDisponibles := -1;

  FHttp := THTTPClient.Create;
  FHttp.ConnectionTimeout := 10000;
  FHttp.ResponseTimeout := TIMEOUT_MS;
  FHttp.Accept := 'application/json';
  FHttp.UserAgent := 'endpoint-pe-ejemplos/delphi';
  FHttp.CustomHeaders['Authorization'] := 'Bearer ' + FApiKey;
end;

destructor TEndpointPe.Destroy;
begin
  FHttp.Free;
  inherited;
end;

class function TEndpointPe.Codificar(const Valor: string): string;
begin
  Result := TNetEncoding.URL.EncodeQuery(Valor);
end;

function TEndpointPe.Ruc(const ARuc: string): TJSONObject;
begin
  Result := Get('/ruc/' + Codificar(ARuc));
end;

function TEndpointPe.Anexos(const ARuc: string): TJSONObject;
begin
  Result := Get('/ruc/' + Codificar(ARuc) + '/anexos');
end;

function TEndpointPe.Representantes(const ARuc: string): TJSONObject;
begin
  Result := Get('/ruc/' + Codificar(ARuc) + '/representantes');
end;

function TEndpointPe.Trabajadores(const ARuc: string): TJSONObject;
begin
  Result := Get('/ruc/' + Codificar(ARuc) + '/trabajadores');
end;

function TEndpointPe.Empresas(const Texto: string): TJSONObject;
begin
  Result := Get('/empresas?q=' + Codificar(Texto));
end;

function TEndpointPe.Dni(const ADni: string): TJSONObject;
begin
  Result := Get('/dni/' + Codificar(ADni));
end;

function TEndpointPe.TipoCambio: TJSONObject;
begin
  Result := Get('/tipo-cambio');
end;

function TEndpointPe.Ubigeo(const Codigo: string): TJSONObject;
begin
  Result := Get('/ubigeo/' + Codificar(Codigo));
end;

function TEndpointPe.Get(const Ruta: string): TJSONObject;
var
  Intento: Integer;
  Respuesta: IHTTPResponse;
  Cuerpo: TJSONValue;
  Obj: TJSONObject;
  Datos: TJSONValue;
  Exito: Boolean;
begin
  Result := nil;
  for Intento := 1 to REINTENTOS do
  begin
    try
      Respuesta := FHttp.Get(FBaseUrl + Ruta);
    except
      on E: ENetHTTPClientException do
      begin
        if Intento < REINTENTOS then
        begin
          Sleep(1000 shl (Intento - 1));
          Continue;
        end;
        raise EEndpoint.Create(0, 'red', 'No se pudo conectar con la API: ' + E.Message);
      end;
    end;

    if (Respuesta.StatusCode >= 500) and (Intento < REINTENTOS) then
    begin
      Sleep(1000 shl (Intento - 1));
      Continue;
    end;

    if Respuesta.ContainsHeader('X-Credits-Remaining') then
      FCreditosDisponibles := StrToIntDef(Trim(Respuesta.HeaderValue['X-Credits-Remaining']), -1);

    Cuerpo := TJSONObject.ParseJSONValue(Respuesta.ContentAsString(TEncoding.UTF8));
    try
      Obj := nil;
      if Cuerpo is TJSONObject then
        Obj := TJSONObject(Cuerpo);
      Exito := (Respuesta.StatusCode = 200) and (Obj <> nil) and Obj.GetValue<Boolean>('success', False);
      if Exito then
        Datos := Obj.GetValue('data')
      else
        Datos := nil;
      if (Datos = nil) or not (Datos is TJSONObject) then
      begin
        if Obj <> nil then
          raise EEndpoint.Create(Respuesta.StatusCode, Obj.GetValue<string>('error', 'error'),
            Obj.GetValue<string>('message', Format('Respuesta inesperada (HTTP %d)', [Respuesta.StatusCode])))
        else
          raise EEndpoint.Create(Respuesta.StatusCode, 'error', Format('Respuesta inesperada (HTTP %d)', [Respuesta.StatusCode]));
      end;
      Result := TJSONObject(Datos.Clone);
    finally
      Cuerpo.Free;
    end;
    Exit;
  end;
end;

{ Uso desde la terminal }

const
  USO =
    'Uso: EndpointPe <comando> [dato]' + sLineBreak + sLineBreak +
    '  ruc <ruc>              Ficha del contribuyente (SUNAT)' + sLineBreak +
    '  dni <dni>              Nombres y apellidos del titular (RENIEC)' + sLineBreak +
    '  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)' + sLineBreak +
    '  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo' + sLineBreak +
    '  empresas <texto>       Buscar el RUC de una empresa por su razón social' + sLineBreak +
    '  anexos <ruc>           Establecimientos anexos de un RUC' + sLineBreak +
    '  representantes <ruc>   Representantes legales de un RUC' + sLineBreak +
    '  trabajadores <ruc>     Trabajadores declarados por periodo' + sLineBreak + sLineBreak +
    'La API key se lee de la variable de entorno ENDPOINT_API_KEY.' + sLineBreak +
    'Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys';

var
  Comando, Dato: string;
  Api: TEndpointPe;
  Resultado: TJSONObject;
  Indice: Integer;

begin
  {$IFDEF MSWINDOWS}
  SetConsoleOutputCP(CP_UTF8); // para que las tildes se vean bien en la consola
  {$ENDIF}
  Comando := ParamStr(1);
  Dato := ParamStr(2);
  if (Comando = '') or (Comando = '-h') or (Comando = '--help') or (Comando = 'ayuda') then
  begin
    Writeln(USO);
    Exit;
  end;

  Indice := IndexStr(Comando, ['ruc', 'dni', 'tipo-cambio', 'ubigeo', 'empresas', 'anexos', 'representantes', 'trabajadores']);
  if Indice < 0 then
  begin
    Writeln(ErrOutput, 'Comando desconocido: ', Comando, sLineBreak, sLineBreak, USO);
    ExitCode := 2;
    Exit;
  end;
  if (Indice <> 2) and (Dato = '') then
  begin
    Writeln(ErrOutput, 'El comando ''', Comando, ''' necesita un dato.');
    ExitCode := 2;
    Exit;
  end;

  try
    Api := TEndpointPe.Create;
    try
      case Indice of
        0: Resultado := Api.Ruc(Dato);
        1: Resultado := Api.Dni(Dato);
        2: Resultado := Api.TipoCambio;
        3: Resultado := Api.Ubigeo(Dato);
        4: Resultado := Api.Empresas(Dato);
        5: Resultado := Api.Anexos(Dato);
        6: Resultado := Api.Representantes(Dato);
      else
        Resultado := Api.Trabajadores(Dato);
      end;
      try
        Writeln(Resultado.Format(2));
      finally
        Resultado.Free;
      end;
      if Api.CreditosDisponibles >= 0 then
        Writeln(ErrOutput, 'Créditos disponibles: ', Api.CreditosDisponibles);
    finally
      Api.Free;
    end;
  except
    on E: EEndpoint do
    begin
      Writeln(ErrOutput, Format('Error HTTP %d (%s): %s', [E.Status, E.Error, E.Mensaje]));
      if E.Error = 'configuracion' then
        ExitCode := 2
      else
        ExitCode := 1;
    end;
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
