import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Java.
 *
 * Sin dependencias: usa java.net.http (Java 11+). Los métodos devuelven el objeto `data`
 * como texto JSON; para convertirlo a objetos usa Jackson o Gson (ver README).
 *
 * Uso desde la terminal (Java 11+ ejecuta el archivo sin compilar):
 *   export ENDPOINT_API_KEY=ep_live_...
 *   java EndpointPe.java ruc 20131312955
 *   java EndpointPe.java dni 45871236
 *   java EndpointPe.java tipo-cambio
 *   java EndpointPe.java ubigeo 150101
 *   java EndpointPe.java empresas "superintendencia aduanas"
 *   java EndpointPe.java anexos 20131312955
 *   java EndpointPe.java representantes 20131312955
 *   java EndpointPe.java trabajadores 20131312955
 *
 * Uso desde tu código:
 *   EndpointPe api = new EndpointPe();                 // lee ENDPOINT_API_KEY del entorno
 *   String ficha = api.ruc("20131312955");             // JSON de `data`
 *   System.out.println(EndpointPe.campo(ficha, "razon_social"));
 *
 * Documentación: https://endpoint.pe/docs
 */
public final class EndpointPe {

    public static final String BASE_URL = entornoO("ENDPOINT_BASE_URL", "https://api.endpoint.pe/v1");
    private static final Duration TIMEOUT = Duration.ofSeconds(15);
    private static final int REINTENTOS = 3; // solo ante errores de red o 5xx; nunca ante 404 o 422

    /**
     * La API respondió con success=false. `error` es el código estable para comparar en tu
     * código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
     */
    public static final class EndpointException extends RuntimeException {
        private static final long serialVersionUID = 1L;
        public final int status;
        public final String error;
        public final String mensaje;
        public final String detalles; // JSON con campo -> motivo (solo en 422), o null

        EndpointException(int status, String error, String mensaje, String detalles) {
            super("HTTP " + status + " · " + error + ": " + mensaje);
            this.status = status;
            this.error = error;
            this.mensaje = mensaje;
            this.detalles = detalles;
        }
    }

    private final String apiKey;
    private final String baseUrl;
    private final HttpClient http;
    /** Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta. */
    private Integer creditosDisponibles;

    public EndpointPe() {
        this(System.getenv("ENDPOINT_API_KEY"), BASE_URL);
    }

    public EndpointPe(String apiKey) {
        this(apiKey, BASE_URL);
    }

    public EndpointPe(String apiKey, String baseUrl) {
        if (apiKey == null || apiKey.isBlank()) {
            throw new IllegalArgumentException("Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.");
        }
        this.apiKey = apiKey;
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    }

    public Integer creditosDisponibles() {
        return creditosDisponibles;
    }

    // --- Empresas (SUNAT) ---

    /** Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones. */
    public String ruc(String ruc) {
        return get("/ruc/" + codificar(ruc));
    }

    /** Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC. */
    public String anexos(String ruc) {
        return get("/ruc/" + codificar(ruc) + "/anexos");
    }

    /** Representantes legales con documento, cargo y fecha de nombramiento. */
    public String representantes(String ruc) {
        return get("/ruc/" + codificar(ruc) + "/representantes");
    }

    /** Trabajadores, pensionistas y prestadores de servicio declarados por periodo. */
    public String trabajadores(String ruc) {
        return get("/ruc/" + codificar(ruc) + "/trabajadores");
    }

    /** Busca el RUC de una empresa por su razón social (hasta 20 coincidencias). */
    public String empresas(String texto) {
        return get("/empresas?q=" + codificar(texto));
    }

    // --- Identidad (RENIEC) ---

    /** Nombres y apellidos del titular, dígito verificador y RUC de persona natural. */
    public String dni(String dni) {
        return get("/dni/" + codificar(dni));
    }

    // --- Finanzas y ubicación ---

    /** Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT. */
    public String tipoCambio() {
        return get("/tipo-cambio");
    }

    /** Departamento, provincia y distrito de un código de ubigeo de 6 dígitos. */
    public String ubigeo(String codigo) {
        return get("/ubigeo/" + codificar(codigo));
    }

    // --- Petición HTTP ---

    private String get(String ruta) {
        HttpRequest peticion = HttpRequest.newBuilder(URI.create(baseUrl + ruta))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + apiKey)
                .header("Accept", "application/json")
                .header("User-Agent", "endpoint-pe-ejemplos/java")
                .GET()
                .build();

        for (int intento = 1; ; intento++) {
            HttpResponse<String> respuesta;
            try {
                respuesta = http.send(peticion, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            } catch (IOException e) {
                if (intento < REINTENTOS) {
                    esperar(intento);
                    continue;
                }
                throw new EndpointException(0, "red", "No se pudo conectar con la API: " + e.getMessage(), null);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new EndpointException(0, "interrumpido", "La petición fue interrumpida.", null);
            }

            if (respuesta.statusCode() >= 500 && intento < REINTENTOS) {
                esperar(intento);
                continue;
            }

            respuesta.headers().firstValue("x-credits-remaining").ifPresent(v -> creditosDisponibles = Integer.valueOf(v.trim()));
            String cuerpo = respuesta.body();
            if (respuesta.statusCode() != 200) {
                String mensaje = campo(cuerpo, "message");
                throw new EndpointException(
                        respuesta.statusCode(),
                        valorO(campo(cuerpo, "error"), "error"),
                        valorO(mensaje, "Respuesta inesperada (HTTP " + respuesta.statusCode() + ")"),
                        objeto(cuerpo, "detalles"));
            }
            return objeto(cuerpo, "data");
        }
    }

    // --- Utilidades JSON (suficientes para leer la respuesta sin bibliotecas) ---

    private static final Pattern CAMPO = Pattern.compile("\"(%s)\"\\s*:\\s*(\"((?:[^\"\\\\]|\\\\.)*)\"|[^,}\\]]+)");

    /** Valor de un campo de primer nivel: texto sin comillas, o el literal (número, true, false, null). */
    public static String campo(String json, String nombre) {
        if (json == null) {
            return null;
        }
        Matcher m = Pattern.compile(String.format(CAMPO.pattern(), Pattern.quote(nombre))).matcher(json);
        if (!m.find()) {
            return null;
        }
        if (m.group(3) != null) {
            return m.group(3).replace("\\\"", "\"").replace("\\/", "/").replace("\\n", "\n").replace("\\\\", "\\");
        }
        String literal = m.group(2).trim();
        return literal.equals("null") ? null : literal;
    }

    /** El objeto JSON (con sus llaves) de un campo de primer nivel, o null si no existe o es null. */
    public static String objeto(String json, String nombre) {
        int i = json.indexOf("\"" + nombre + "\"");
        if (i < 0) {
            return null;
        }
        int inicio = json.indexOf('{', i);
        if (inicio < 0) {
            return null;
        }
        int nivel = 0;
        boolean enTexto = false;
        for (int j = inicio; j < json.length(); j++) {
            char c = json.charAt(j);
            if (enTexto) {
                if (c == '\\') {
                    j++;
                } else if (c == '"') {
                    enTexto = false;
                }
            } else if (c == '"') {
                enTexto = true;
            } else if (c == '{') {
                nivel++;
            } else if (c == '}' && --nivel == 0) {
                return json.substring(inicio, j + 1);
            }
        }
        return null;
    }

    /** Da formato legible a un JSON compacto (sangría de dos espacios). */
    public static String formatear(String json) {
        StringBuilder sb = new StringBuilder();
        int nivel = 0;
        boolean enTexto = false;
        for (int i = 0; i < json.length(); i++) {
            char c = json.charAt(i);
            if (enTexto) {
                sb.append(c);
                if (c == '\\') {
                    sb.append(json.charAt(++i));
                } else if (c == '"') {
                    enTexto = false;
                }
                continue;
            }
            switch (c) {
                case '"': enTexto = true; sb.append(c); break;
                case '{': case '[': sb.append(c).append('\n').append("  ".repeat(++nivel)); break;
                case '}': case ']': sb.append('\n').append("  ".repeat(--nivel)).append(c); break;
                case ',': sb.append(c).append('\n').append("  ".repeat(nivel)); break;
                case ':': sb.append(": "); break;
                case ' ': case '\n': case '\r': case '\t': break;
                default: sb.append(c);
            }
        }
        return sb.toString();
    }

    private static String codificar(String valor) {
        return URLEncoder.encode(valor, StandardCharsets.UTF_8);
    }

    private static String entornoO(String variable, String porDefecto) {
        String v = System.getenv(variable);
        return v == null || v.isBlank() ? porDefecto : v;
    }

    private static String valorO(String valor, String porDefecto) {
        return valor == null ? porDefecto : valor;
    }

    private static void esperar(int intento) {
        try {
            Thread.sleep(1000L << (intento - 1));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // --- Uso desde la terminal ---

    private static final String USO = String.join("\n",
            "Uso: java EndpointPe.java <comando> [dato]",
            "",
            "  ruc <ruc>              Ficha del contribuyente (SUNAT)",
            "  dni <dni>              Nombres y apellidos del titular (RENIEC)",
            "  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)",
            "  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo",
            "  empresas <texto>       Buscar el RUC de una empresa por su razón social",
            "  anexos <ruc>           Establecimientos anexos de un RUC",
            "  representantes <ruc>   Representantes legales de un RUC",
            "  trabajadores <ruc>     Trabajadores declarados por periodo",
            "",
            "La API key se lee de la variable de entorno ENDPOINT_API_KEY.",
            "Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys");

    public static void main(String[] args) {
        String comando = args.length > 0 ? args[0] : "";
        String dato = args.length > 1 ? args[1] : "";
        if (comando.isEmpty() || comando.equals("-h") || comando.equals("--help") || comando.equals("ayuda")) {
            System.out.println(USO);
            return;
        }

        EndpointPe api;
        try {
            api = new EndpointPe();
        } catch (IllegalArgumentException e) {
            System.err.println(e.getMessage());
            System.exit(2);
            return;
        }

        Map<String, Boolean> necesitaDato = new LinkedHashMap<>();
        necesitaDato.put("ruc", true);
        necesitaDato.put("dni", true);
        necesitaDato.put("tipo-cambio", false);
        necesitaDato.put("ubigeo", true);
        necesitaDato.put("empresas", true);
        necesitaDato.put("anexos", true);
        necesitaDato.put("representantes", true);
        necesitaDato.put("trabajadores", true);
        if (!necesitaDato.containsKey(comando)) {
            System.err.println("Comando desconocido: " + comando + "\n\n" + USO);
            System.exit(2);
        }
        if (necesitaDato.get(comando) && dato.isEmpty()) {
            System.err.println("El comando '" + comando + "' necesita un dato.");
            System.exit(2);
        }

        try {
            String resultado;
            switch (comando) {
                case "ruc": resultado = api.ruc(dato); break;
                case "dni": resultado = api.dni(dato); break;
                case "tipo-cambio": resultado = api.tipoCambio(); break;
                case "ubigeo": resultado = api.ubigeo(dato); break;
                case "empresas": resultado = api.empresas(dato); break;
                case "anexos": resultado = api.anexos(dato); break;
                case "representantes": resultado = api.representantes(dato); break;
                default: resultado = api.trabajadores(dato);
            }
            System.out.println(formatear(resultado));
            if (api.creditosDisponibles() != null) {
                System.err.println("Créditos disponibles: " + api.creditosDisponibles());
            }
        } catch (EndpointException e) {
            System.err.println("Error HTTP " + e.status + " (" + e.error + "): " + e.mensaje);
            if (e.detalles != null) {
                System.err.println("  " + e.detalles);
            }
            System.exit(1);
        }
    }
}
