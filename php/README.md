# PHP (y Laravel)

Cliente mínimo de la API de endpoint.pe con cURL, sin Composer ni dependencias. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- PHP 7.4 o superior con las extensiones `curl` y `json` (vienen activas en casi todas las instalaciones, incluidas XAMPP, Laragon y los hostings compartidos).

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

php consulta.php ruc 20131312955
php consulta.php dni 45871236
php consulta.php tipo-cambio
php consulta.php ubigeo 150101
php consulta.php empresas "superintendencia aduanas"
php consulta.php anexos 20131312955
php consulta.php representantes 20131312955
php consulta.php trabajadores 20131312955
```

En Windows (CMD): `set ENDPOINT_API_KEY=ep_live_...` y luego `php consulta.php ruc 20131312955`.

## Usar en tu proyecto

```php
require 'consulta.php';

$api = new EndpointPe(); // lee ENDPOINT_API_KEY; también acepta new EndpointPe('ep_live_...')

if (es_ruc_valido('20131312955')) {         // valida el formato antes de gastar una llamada
    try {
        $ficha = $api->ruc('20131312955');
        echo $ficha['razon_social'], ' · ', $ficha['estado'], ' · ', $ficha['condicion'], PHP_EOL;
    } catch (EndpointError $e) {
        if ($e->error === 'no_encontrado') {
            echo 'RUC no inscrito', PHP_EOL;
        } else {
            echo $e->status, ' ', $e->error, ' ', $e->mensaje, PHP_EOL;
        }
    }
}

$tc = $api->tipoCambio();
echo $tc['fecha'], ' compra ', $tc['compra'], ' venta ', $tc['venta'], PHP_EOL;
echo 'Créditos disponibles: ', $api->creditosDisponibles, PHP_EOL;
```

Cada método devuelve el objeto `data` como arreglo asociativo y actualiza `creditosDisponibles`. Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Laravel

Con el cliente HTTP de Laravel no necesitas este archivo. Guarda la clave en `.env` como `ENDPOINT_API_KEY` y léela desde `config/services.php`:

```php
// config/services.php
'endpoint' => ['key' => env('ENDPOINT_API_KEY')],
```

```php
use Illuminate\Support\Facades\Http;

$respuesta = Http::withToken(config('services.endpoint.key'))
    ->timeout(15)
    ->retry(3, 1000, fn ($e) => $e instanceof \Illuminate\Http\Client\ConnectionException)
    ->get("https://api.endpoint.pe/v1/ruc/{$ruc}");

if ($respuesta->ok() && $respuesta->json('success')) {
    $razonSocial = $respuesta->json('data.razon_social');
} else {
    $codigo = $respuesta->json('error');      // no_encontrado, validacion, sin_creditos…
}
```

Si varios usuarios consultan los mismos RUC o DNI, envuelve la llamada en `Cache::remember()`; los datos cambian poco y cada 200 descuenta un crédito.

Guía completa: [Consultar RUC con PHP y Laravel](https://endpoint.pe/blog/consultar-ruc-con-php-y-laravel).

## CodeIgniter, Symfony y WordPress

El archivo `consulta.php` no depende de ningún framework: inclúyelo donde lo necesites (una librería de CodeIgniter, un servicio de Symfony, el `functions.php` o un plugin de WordPress) y crea la instancia una sola vez. En WordPress puedes usar también `wp_remote_get()` con la cabecera `Authorization`.
