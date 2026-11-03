// endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Dart (y Flutter).
//
// Sin paquetes: usa dart:io (HttpClient) y dart:convert.
//
// Uso desde la terminal:
//   export ENDPOINT_API_KEY=ep_live_...
//   dart run consulta.dart ruc 20131312955
//   dart run consulta.dart dni 45871236
//   dart run consulta.dart tipo-cambio
//   dart run consulta.dart ubigeo 150101
//   dart run consulta.dart empresas "superintendencia aduanas"
//   dart run consulta.dart anexos 20131312955
//   dart run consulta.dart representantes 20131312955
//   dart run consulta.dart trabajadores 20131312955
//
// Uso desde tu código:
//   final api = EndpointPe();                         // lee ENDPOINT_API_KEY del entorno
//   final ficha = await api.ruc('20131312955');       // Map<String, dynamic> con el objeto `data`
//   print('${ficha['razon_social']} ${ficha['estado']} ${api.creditosDisponibles}');
//
// Documentación: https://endpoint.pe/docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _baseUrlPorDefecto = 'https://api.endpoint.pe/v1';
const _timeout = Duration(seconds: 15);
const _reintentos = 3; // solo ante errores de red o 5xx; nunca ante 404 o 422

/// La API respondió con success=false. [error] es el código estable para comparar en tu
/// código (no_encontrado, validacion, sin_creditos…); [mensaje] es texto en español.
class EndpointError implements Exception {
  final int status;
  final String error;
  final String mensaje;
  final Map<String, String> detalles;

  EndpointError(this.status, this.error, this.mensaje, [this.detalles = const {}]);

  @override
  String toString() => 'HTTP $status · $error: $mensaje';
}

/// Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta.
class EndpointPe {
  final String _apiKey;
  final String _baseUrl;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  /// Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.
  int? creditosDisponibles;

  EndpointPe({String? apiKey, String? baseUrl})
      : _apiKey = apiKey ?? Platform.environment['ENDPOINT_API_KEY'] ?? '',
        _baseUrl = (baseUrl ?? Platform.environment['ENDPOINT_BASE_URL'] ?? _baseUrlPorDefecto)
            .replaceAll(RegExp(r'/+$'), '') {
    if (_apiKey.isEmpty) {
      throw ArgumentError('Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.');
    }
  }

  // Empresas (SUNAT)

  /// Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.
  Future<Map<String, dynamic>> ruc(String ruc) => _get('/ruc/${Uri.encodeComponent(ruc)}');

  /// Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.
  Future<Map<String, dynamic>> anexos(String ruc) => _get('/ruc/${Uri.encodeComponent(ruc)}/anexos');

  /// Representantes legales con documento, cargo y fecha de nombramiento.
  Future<Map<String, dynamic>> representantes(String ruc) =>
      _get('/ruc/${Uri.encodeComponent(ruc)}/representantes');

  /// Trabajadores, pensionistas y prestadores de servicio declarados por periodo.
  Future<Map<String, dynamic>> trabajadores(String ruc) =>
      _get('/ruc/${Uri.encodeComponent(ruc)}/trabajadores');

  /// Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).
  Future<Map<String, dynamic>> empresas(String texto) => _get('/empresas', {'q': texto});

  // Identidad (RENIEC)

  /// Nombres y apellidos del titular, dígito verificador y RUC de persona natural.
  Future<Map<String, dynamic>> dni(String dni) => _get('/dni/${Uri.encodeComponent(dni)}');

  // Finanzas y ubicación

  /// Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.
  Future<Map<String, dynamic>> tipoCambio() => _get('/tipo-cambio');

  /// Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.
  Future<Map<String, dynamic>> ubigeo(String codigo) => _get('/ubigeo/${Uri.encodeComponent(codigo)}');

  /// Lista departamentos, provincias o distritos, o arma el código a partir de los nombres.
  Future<Map<String, dynamic>> ubigeoPorNombres({String? departamento, String? provincia, String? distrito}) =>
      _get('/ubigeo', {
        if (departamento != null) 'departamento': departamento,
        if (provincia != null) 'provincia': provincia,
        if (distrito != null) 'distrito': distrito,
      });

  Future<Map<String, dynamic>> _get(String ruta, [Map<String, String>? params]) async {
    var uri = Uri.parse('$_baseUrl$ruta');
    if (params != null && params.isNotEmpty) uri = uri.replace(queryParameters: params);

    for (var intento = 1;; intento++) {
      HttpClientResponse respuesta;
      String texto;
      try {
        final peticion = await _http.getUrl(uri);
        peticion.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
          ..set(HttpHeaders.acceptHeader, 'application/json')
          ..set(HttpHeaders.userAgentHeader, 'endpoint-pe-ejemplos/dart');
        respuesta = await peticion.close().timeout(_timeout);
        texto = await respuesta.transform(utf8.decoder).join().timeout(_timeout);
      } on Exception catch (e) {
        // SocketException, HttpException, TimeoutException…
        if (intento < _reintentos) {
          await Future.delayed(Duration(seconds: 1 << (intento - 1)));
          continue;
        }
        throw EndpointError(0, 'red', 'No se pudo conectar con la API: $e');
      }

      if (respuesta.statusCode >= 500 && intento < _reintentos) {
        await Future.delayed(Duration(seconds: 1 << (intento - 1)));
        continue;
      }
      final restantes = respuesta.headers.value('x-credits-remaining');
      if (restantes != null) creditosDisponibles = int.tryParse(restantes.trim());

      Map<String, dynamic> cuerpo;
      try {
        cuerpo = jsonDecode(texto) as Map<String, dynamic>;
      } catch (_) {
        cuerpo = {};
      }
      final data = cuerpo['data'];
      if (respuesta.statusCode != 200 || cuerpo['success'] != true || data is! Map<String, dynamic>) {
        final detalles = (cuerpo['detalles'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            const {};
        throw EndpointError(
          respuesta.statusCode,
          cuerpo['error'] as String? ?? 'error',
          cuerpo['message'] as String? ?? 'Respuesta inesperada (HTTP ${respuesta.statusCode})',
          detalles,
        );
      }
      return data;
    }
  }

  /// Cierra las conexiones abiertas (llámalo al terminar en programas de línea de comandos).
  void cerrar() => _http.close();
}

/// Valida el formato de un RUC antes de consultar: 11 dígitos, prefijo 10/15/16/17/20 y dígito verificador.
bool esRucValido(String ruc) {
  if (!RegExp(r'^(10|15|16|17|20)\d{9}$').hasMatch(ruc)) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  var suma = 0;
  for (var i = 0; i < 10; i++) {
    suma += int.parse(ruc[i]) * pesos[i];
  }
  final resto = 11 - (suma % 11);
  final verificador = resto == 10 ? 0 : (resto == 11 ? 1 : resto);
  return verificador == int.parse(ruc[10]);
}

// --- Uso desde la terminal ---

const _uso = '''
Uso: dart run consulta.dart <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys''';

Future<void> main(List<String> args) async {
  final comando = args.isNotEmpty ? args[0] : '';
  final dato = args.length > 1 ? args[1] : '';
  if (comando.isEmpty || const ['-h', '--help', 'ayuda'].contains(comando)) {
    print(_uso);
    return;
  }

  final EndpointPe api;
  try {
    api = EndpointPe();
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }

  final comandos = <String, (Future<Map<String, dynamic>> Function(String), bool)>{
    'ruc': (api.ruc, true),
    'dni': (api.dni, true),
    'tipo-cambio': ((_) => api.tipoCambio(), false),
    'ubigeo': (api.ubigeo, true),
    'empresas': (api.empresas, true),
    'anexos': (api.anexos, true),
    'representantes': (api.representantes, true),
    'trabajadores': (api.trabajadores, true),
  };
  final entrada = comandos[comando];
  if (entrada == null) {
    stderr.writeln('Comando desconocido: $comando\n\n$_uso');
    exit(2);
  }
  final (funcion, necesitaDato) = entrada;
  if (necesitaDato && dato.isEmpty) {
    stderr.writeln("El comando '$comando' necesita un dato.");
    exit(2);
  }

  try {
    final resultado = await funcion(dato);
    print(const JsonEncoder.withIndent('  ').convert(resultado));
    if (api.creditosDisponibles != null) {
      stderr.writeln('Créditos disponibles: ${api.creditosDisponibles}');
    }
  } on EndpointError catch (e) {
    stderr.writeln('Error HTTP ${e.status} (${e.error}): ${e.mensaje}');
    e.detalles.forEach((campo, motivo) => stderr.writeln('  $campo: $motivo'));
    exitCode = 1;
  } finally {
    api.cerrar();
  }
}
