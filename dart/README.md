# Dart y Flutter

Cliente mínimo de la API de endpoint.pe con `dart:io` y `dart:convert`, sin paquetes. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Dart 3.0 o superior (incluido en Flutter 3.10+).

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

dart run consulta.dart ruc 20131312955
dart run consulta.dart dni 45871236
dart run consulta.dart tipo-cambio
dart run consulta.dart ubigeo 150101
dart run consulta.dart empresas "superintendencia aduanas"
dart run consulta.dart anexos 20131312955
dart run consulta.dart representantes 20131312955
dart run consulta.dart trabajadores 20131312955
```

## Usar en tu proyecto

```dart
import 'consulta.dart';

final api = EndpointPe(); // lee ENDPOINT_API_KEY; también acepta EndpointPe(apiKey: 'ep_live_...')

if (esRucValido('20131312955')) {           // valida el formato antes de gastar una llamada
  try {
    final ficha = await api.ruc('20131312955');
    print('${ficha['razon_social']} · ${ficha['estado']} · ${ficha['condicion']}');
  } on EndpointError catch (e) {
    print(e.error == 'no_encontrado' ? 'RUC no inscrito' : '${e.status} ${e.error} ${e.mensaje}');
  }
}

final tc = await api.tipoCambio();
print('${tc['fecha']} compra ${tc['compra']} venta ${tc['venta']}');
```

Cada método devuelve el objeto `data` como `Map<String, dynamic>` y actualiza `creditosDisponibles`. Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Flutter

El cliente funciona tal cual en Flutter para Android, iOS, escritorio y web (en web, cambia `dart:io` por el paquete [`http`](https://pub.dev/packages/http); la lógica es la misma). Pero no publiques una app con la API key dentro: cualquiera puede extraerla del APK o del IPA. Lo recomendable es que tu backend consulte a endpoint.pe y la app hable solo con tu backend.
