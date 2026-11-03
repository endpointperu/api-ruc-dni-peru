<?php
/**
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde PHP.
 *
 * Sin dependencias: usa la extensión cURL, incluida en casi cualquier instalación de PHP.
 *
 * Uso desde la terminal:
 *   export ENDPOINT_API_KEY=ep_live_...
 *   php consulta.php ruc 20131312955
 *   php consulta.php dni 45871236
 *   php consulta.php tipo-cambio
 *   php consulta.php ubigeo 150101
 *   php consulta.php empresas "superintendencia aduanas"
 *   php consulta.php anexos 20131312955
 *   php consulta.php representantes 20131312955
 *   php consulta.php trabajadores 20131312955
 *
 * Uso desde tu código:
 *   require 'consulta.php';
 *   $api = new EndpointPe();                 // lee ENDPOINT_API_KEY del entorno
 *   $ficha = $api->ruc('20131312955');
 *   echo $ficha['razon_social'], ' ', $ficha['estado'], ' ', $api->creditosDisponibles;
 *
 * Requisitos: PHP 7.4 o superior con ext-curl y ext-json.
 * Documentación: https://endpoint.pe/docs
 */

declare(strict_types=1);

/**
 * La API respondió con success=false. `error` es el código estable para comparar en tu
 * código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
 */
final class EndpointError extends RuntimeException
{
    public int $status;
    public string $error;
    public string $mensaje;
    /** @var array<string, string> */
    public array $detalles;

    /** @param array<string, string> $detalles */
    public function __construct(int $status, string $error, string $mensaje, array $detalles = [])
    {
        parent::__construct("HTTP $status · $error: $mensaje", $status);
        $this->status = $status;
        $this->error = $error;
        $this->mensaje = $mensaje;
        $this->detalles = $detalles;
    }
}

/** Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta como arreglo. */
final class EndpointPe
{
    public const BASE_URL = 'https://api.endpoint.pe/v1';
    private const TIMEOUT = 15;     // segundos
    private const REINTENTOS = 3;   // solo ante errores de red o 5xx; nunca ante 404 o 422

    private string $apiKey;
    private string $baseUrl;
    /** Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta. */
    public ?int $creditosDisponibles = null;

    public function __construct(?string $apiKey = null, ?string $baseUrl = null)
    {
        $apiKey = $apiKey ?? (getenv('ENDPOINT_API_KEY') ?: '');
        if ($apiKey === '') {
            throw new InvalidArgumentException('Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.');
        }
        $this->apiKey = $apiKey;
        $this->baseUrl = rtrim($baseUrl ?? (getenv('ENDPOINT_BASE_URL') ?: self::BASE_URL), '/');
    }

    // --- Empresas (SUNAT) ---

    /** Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones. */
    public function ruc(string $ruc): array
    {
        return $this->get('/ruc/' . rawurlencode($ruc));
    }

    /** Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC. */
    public function anexos(string $ruc): array
    {
        return $this->get('/ruc/' . rawurlencode($ruc) . '/anexos');
    }

    /** Representantes legales con documento, cargo y fecha de nombramiento. */
    public function representantes(string $ruc): array
    {
        return $this->get('/ruc/' . rawurlencode($ruc) . '/representantes');
    }

    /** Trabajadores, pensionistas y prestadores de servicio declarados por periodo. */
    public function trabajadores(string $ruc): array
    {
        return $this->get('/ruc/' . rawurlencode($ruc) . '/trabajadores');
    }

    /** Busca el RUC de una empresa por su razón social (hasta 20 coincidencias). */
    public function empresas(string $texto): array
    {
        return $this->get('/empresas', ['q' => $texto]);
    }

    // --- Identidad (RENIEC) ---

    /** Nombres y apellidos del titular, dígito verificador y RUC de persona natural. */
    public function dni(string $dni): array
    {
        return $this->get('/dni/' . rawurlencode($dni));
    }

    // --- Finanzas y ubicación ---

    /** Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT. */
    public function tipoCambio(): array
    {
        return $this->get('/tipo-cambio');
    }

    /** Departamento, provincia y distrito de un código de ubigeo de 6 dígitos. */
    public function ubigeo(string $codigo): array
    {
        return $this->get('/ubigeo/' . rawurlencode($codigo));
    }

    /** Lista departamentos, provincias o distritos, o arma el código a partir de los nombres. */
    public function ubigeoPorNombres(?string $departamento = null, ?string $provincia = null, ?string $distrito = null): array
    {
        return $this->get('/ubigeo', array_filter([
            'departamento' => $departamento,
            'provincia' => $provincia,
            'distrito' => $distrito,
        ]));
    }

    // --- Petición HTTP ---

    /** @param array<string, string> $params */
    private function get(string $path, array $params = []): array
    {
        $url = $this->baseUrl . $path . ($params ? '?' . http_build_query($params) : '');

        for ($intento = 1; ; $intento++) {
            $restantes = null;
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPHEADER => [
                    'Authorization: Bearer ' . $this->apiKey,
                    'Accept: application/json',
                    'User-Agent: endpoint-pe-ejemplos/php',
                ],
                CURLOPT_CONNECTTIMEOUT => 10,
                CURLOPT_TIMEOUT => self::TIMEOUT,
                CURLOPT_HEADERFUNCTION => static function ($ch, string $linea) use (&$restantes): int {
                    if (stripos($linea, 'X-Credits-Remaining:') === 0) {
                        $restantes = (int) trim(substr($linea, strlen('X-Credits-Remaining:')));
                    }
                    return strlen($linea);
                },
            ]);
            $cuerpo = curl_exec($ch);
            $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            $errorRed = curl_error($ch);
            curl_close($ch);

            if (($cuerpo === false || $status >= 500) && $intento < self::REINTENTOS) {
                sleep(2 ** ($intento - 1));
                continue;
            }
            if ($cuerpo === false) {
                throw new EndpointError(0, 'red', "No se pudo conectar con la API: $errorRed");
            }

            if ($restantes !== null) {
                $this->creditosDisponibles = $restantes;
            }
            $json = json_decode((string) $cuerpo, true);
            $json = is_array($json) ? $json : [];

            if ($status !== 200 || empty($json['success'])) {
                throw new EndpointError(
                    $status,
                    $json['error'] ?? 'error',
                    $json['message'] ?? "Respuesta inesperada (HTTP $status)",
                    $json['detalles'] ?? []
                );
            }
            return $json['data'];
        }
    }
}

/** Valida el formato de un RUC antes de consultar: 11 dígitos, prefijo 10/15/16/17/20 y dígito verificador. */
function es_ruc_valido(string $ruc): bool
{
    if (!preg_match('/^(10|15|16|17|20)\d{9}$/', $ruc)) {
        return false;
    }
    $pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    $suma = 0;
    foreach ($pesos as $i => $peso) {
        $suma += (int) $ruc[$i] * $peso;
    }
    $resto = 11 - ($suma % 11);
    $verificador = $resto === 10 ? 0 : ($resto === 11 ? 1 : $resto);
    return $verificador === (int) $ruc[10];
}

// --- Uso desde la terminal ---

if (PHP_SAPI === 'cli' && isset($argv[0]) && realpath($argv[0]) === __FILE__) {
    $uso = <<<TXT
Uso: php consulta.php <comando> [dato]

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
TXT;

    $comando = $argv[1] ?? '';
    $dato = $argv[2] ?? '';
    if ($comando === '' || in_array($comando, ['-h', '--help', 'ayuda'], true)) {
        echo $uso, PHP_EOL;
        exit(0);
    }

    try {
        $api = new EndpointPe();
    } catch (InvalidArgumentException $e) {
        fwrite(STDERR, $e->getMessage() . PHP_EOL);
        exit(2);
    }

    // comando => [método, necesita dato]
    $comandos = [
        'ruc' => ['ruc', true],
        'dni' => ['dni', true],
        'tipo-cambio' => ['tipoCambio', false],
        'ubigeo' => ['ubigeo', true],
        'empresas' => ['empresas', true],
        'anexos' => ['anexos', true],
        'representantes' => ['representantes', true],
        'trabajadores' => ['trabajadores', true],
    ];
    if (!isset($comandos[$comando])) {
        fwrite(STDERR, "Comando desconocido: $comando\n\n$uso\n");
        exit(2);
    }
    [$metodo, $necesitaDato] = $comandos[$comando];
    if ($necesitaDato && $dato === '') {
        fwrite(STDERR, "El comando '$comando' necesita un dato.\n");
        exit(2);
    }

    try {
        $resultado = $necesitaDato ? $api->$metodo($dato) : $api->$metodo();
    } catch (EndpointError $e) {
        fwrite(STDERR, "Error HTTP {$e->status} ({$e->error}): {$e->mensaje}\n");
        foreach ($e->detalles as $campo => $motivo) {
            fwrite(STDERR, "  $campo: $motivo\n");
        }
        exit(1);
    }

    echo json_encode($resultado, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), PHP_EOL;
    if ($api->creditosDisponibles !== null) {
        fwrite(STDERR, "Créditos disponibles: {$api->creditosDisponibles}\n");
    }
}
