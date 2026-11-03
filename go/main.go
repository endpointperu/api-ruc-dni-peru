// endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Go.
//
// Sin dependencias: usa net/http y encoding/json de la biblioteca estándar.
//
// Uso desde la terminal:
//
//	export ENDPOINT_API_KEY=ep_live_...
//	go run . ruc 20131312955
//	go run . dni 45871236
//	go run . tipo-cambio
//	go run . ubigeo 150101
//	go run . empresas "superintendencia aduanas"
//	go run . anexos 20131312955
//	go run . representantes 20131312955
//	go run . trabajadores 20131312955
//
// Uso desde tu código:
//
//	api, err := Nuevo()                      // lee ENDPOINT_API_KEY del entorno
//	var ficha Ruc
//	err = api.Ruc("20131312955", &ficha)
//	fmt.Println(ficha.RazonSocial, ficha.Estado, api.CreditosDisponibles)
//
// Documentación: https://endpoint.pe/docs
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"time"
)

const (
	baseURLPorDefecto = "https://api.endpoint.pe/v1"
	timeout           = 15 * time.Second
	reintentos        = 3 // solo ante errores de red o 5xx; nunca ante 404 o 422
)

// Error es la respuesta con success=false. Codigo es el valor estable para comparar en tu
// código (no_encontrado, validacion, sin_creditos…); Mensaje es texto en español.
type Error struct {
	Status   int
	Codigo   string
	Mensaje  string
	Detalles map[string]string
}

func (e *Error) Error() string {
	return fmt.Sprintf("HTTP %d · %s: %s", e.Status, e.Codigo, e.Mensaje)
}

// envoltorio es la forma común de todas las respuestas de /v1.
type envoltorio struct {
	Success  bool              `json:"success"`
	Message  string            `json:"message"`
	Error    string            `json:"error"`
	Data     json.RawMessage   `json:"data"`
	Detalles map[string]string `json:"detalles"`
}

// Ruc es la ficha del contribuyente (GET /v1/ruc/{ruc}). Los punteros son campos que la
// fuente puede no tener (llegan como null).
type Ruc struct {
	Ruc                             string  `json:"ruc"`
	RazonSocial                     string  `json:"razon_social"`
	NombreComercial                 *string `json:"nombre_comercial"`
	TipoContribuyente               *string `json:"tipo_contribuyente"`
	Estado                          string  `json:"estado"`
	Condicion                       string  `json:"condicion"`
	FechaInscripcion                *string `json:"fecha_inscripcion"`
	FechaInicioActividades          *string `json:"fecha_inicio_actividades"`
	Direccion                       *string `json:"direccion"`
	DireccionCompleta               *string `json:"direccion_completa"`
	Departamento                    *string `json:"departamento"`
	Provincia                       *string `json:"provincia"`
	Distrito                        *string `json:"distrito"`
	Ubigeo                          *string `json:"ubigeo"`
	UbigeoReniec                    *string `json:"ubigeo_reniec"`
	EsAgenteDeRetencion             *bool   `json:"es_agente_de_retencion"`
	EsAgenteDePercepcion            *bool   `json:"es_agente_de_percepcion"`
	EsAgenteDePercepcionCombustible *bool   `json:"es_agente_de_percepcion_combustible"`
	EsBuenContribuyente             *bool   `json:"es_buen_contribuyente"`
	CantidadTrabajadores            *int    `json:"cantidad_trabajadores"`
	CantidadEstablecimientos        int     `json:"cantidad_establecimientos"`
	CantidadRepresentantes          int     `json:"cantidad_representantes"`
}

// Dni es la identidad del titular (GET /v1/dni/{dni}).
type Dni struct {
	Dni               string  `json:"dni"`
	DigitoVerificador string  `json:"digito_verificador"`
	Nombres           string  `json:"nombres"`
	ApellidoPaterno   string  `json:"apellido_paterno"`
	ApellidoMaterno   string  `json:"apellido_materno"`
	NombreCompleto    string  `json:"nombre_completo"`
	Ruc               *string `json:"ruc"`
}

// TipoCambio es el valor publicado por SUNAT (GET /v1/tipo-cambio).
type TipoCambio struct {
	Fecha  string  `json:"fecha"`
	Moneda string  `json:"moneda"`
	Compra float64 `json:"compra"`
	Venta  float64 `json:"venta"`
	Fuente string  `json:"fuente"`
}

// Ubigeo es la ubicación de un código (GET /v1/ubigeo/{codigo}).
type Ubigeo struct {
	Ubigeo       string  `json:"ubigeo"`
	UbigeoReniec *string `json:"ubigeo_reniec"`
	Departamento string  `json:"departamento"`
	Provincia    string  `json:"provincia"`
	Distrito     string  `json:"distrito"`
	Codigos      struct {
		Departamento string `json:"departamento"`
		Provincia    string `json:"provincia"`
		Distrito     string `json:"distrito"`
	} `json:"codigos"`
	Vigente bool `json:"vigente"`
}

// Cliente de la API v1. Cada método decodifica el objeto `data` en `destino`
// (un struct como Ruc, o *json.RawMessage para quedarte con el JSON tal cual).
type Cliente struct {
	apiKey  string
	baseURL string
	http    *http.Client
	// CreditosDisponibles son los créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.
	CreditosDisponibles int
}

// Nuevo crea el cliente con la API key de ENDPOINT_API_KEY.
func Nuevo() (*Cliente, error) {
	return NuevoConClave(os.Getenv("ENDPOINT_API_KEY"))
}

// NuevoConClave crea el cliente con una API key explícita.
func NuevoConClave(apiKey string) (*Cliente, error) {
	if apiKey == "" {
		return nil, errors.New("falta la API key: define ENDPOINT_API_KEY o pásala a NuevoConClave")
	}
	baseURL := os.Getenv("ENDPOINT_BASE_URL")
	if baseURL == "" {
		baseURL = baseURLPorDefecto
	}
	return &Cliente{
		apiKey:              apiKey,
		baseURL:             baseURL,
		http:                &http.Client{Timeout: timeout},
		CreditosDisponibles: -1,
	}, nil
}

// Empresas (SUNAT)

// Ruc devuelve la ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.
func (c *Cliente) Ruc(ruc string, destino any) error {
	return c.get("/ruc/"+url.PathEscape(ruc), nil, destino)
}

// Anexos devuelve los establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.
func (c *Cliente) Anexos(ruc string, destino any) error {
	return c.get("/ruc/"+url.PathEscape(ruc)+"/anexos", nil, destino)
}

// Representantes devuelve los representantes legales con documento, cargo y fecha de nombramiento.
func (c *Cliente) Representantes(ruc string, destino any) error {
	return c.get("/ruc/"+url.PathEscape(ruc)+"/representantes", nil, destino)
}

// Trabajadores devuelve trabajadores, pensionistas y prestadores de servicio declarados por periodo.
func (c *Cliente) Trabajadores(ruc string, destino any) error {
	return c.get("/ruc/"+url.PathEscape(ruc)+"/trabajadores", nil, destino)
}

// Empresas busca el RUC de una empresa por su razón social (hasta 20 coincidencias).
func (c *Cliente) Empresas(texto string, destino any) error {
	return c.get("/empresas", url.Values{"q": {texto}}, destino)
}

// Identidad (RENIEC)

// Dni devuelve nombres y apellidos del titular, dígito verificador y RUC de persona natural.
func (c *Cliente) Dni(dni string, destino any) error {
	return c.get("/dni/"+url.PathEscape(dni), nil, destino)
}

// Finanzas y ubicación

// TipoCambio devuelve el tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.
func (c *Cliente) TipoCambio(destino any) error {
	return c.get("/tipo-cambio", nil, destino)
}

// Ubigeo devuelve departamento, provincia y distrito de un código de ubigeo de 6 dígitos.
func (c *Cliente) Ubigeo(codigo string, destino any) error {
	return c.get("/ubigeo/"+url.PathEscape(codigo), nil, destino)
}

// UbigeoPorNombres lista departamentos, provincias o distritos, o arma el código a partir de los nombres.
func (c *Cliente) UbigeoPorNombres(departamento, provincia, distrito string, destino any) error {
	params := url.Values{}
	for clave, valor := range map[string]string{"departamento": departamento, "provincia": provincia, "distrito": distrito} {
		if valor != "" {
			params.Set(clave, valor)
		}
	}
	return c.get("/ubigeo", params, destino)
}

func (c *Cliente) get(ruta string, params url.Values, destino any) error {
	direccion := c.baseURL + ruta
	if len(params) > 0 {
		direccion += "?" + params.Encode()
	}

	for intento := 1; ; intento++ {
		req, err := http.NewRequest(http.MethodGet, direccion, nil)
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
		req.Header.Set("Accept", "application/json")
		req.Header.Set("User-Agent", "endpoint-pe-ejemplos/go")

		res, err := c.http.Do(req)
		if err != nil {
			if intento < reintentos {
				esperar(intento)
				continue
			}
			return &Error{Status: 0, Codigo: "red", Mensaje: "No se pudo conectar con la API: " + err.Error()}
		}
		cuerpo, err := io.ReadAll(res.Body)
		res.Body.Close()
		if err != nil {
			return err
		}

		if res.StatusCode >= 500 && intento < reintentos {
			esperar(intento)
			continue
		}
		if restantes, err := strconv.Atoi(res.Header.Get("X-Credits-Remaining")); err == nil {
			c.CreditosDisponibles = restantes
		}

		var env envoltorio
		_ = json.Unmarshal(cuerpo, &env)
		if res.StatusCode != http.StatusOK || !env.Success || len(env.Data) == 0 {
			codigo, mensaje := env.Error, env.Message
			if codigo == "" {
				codigo = "error"
			}
			if mensaje == "" {
				mensaje = fmt.Sprintf("Respuesta inesperada (HTTP %d)", res.StatusCode)
			}
			return &Error{Status: res.StatusCode, Codigo: codigo, Mensaje: mensaje, Detalles: env.Detalles}
		}
		return json.Unmarshal(env.Data, destino)
	}
}

func esperar(intento int) {
	time.Sleep(time.Duration(1<<(intento-1)) * time.Second)
}

// --- Uso desde la terminal ---

const uso = `Uso: go run . <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys`

func main() {
	os.Exit(ejecutar(os.Args[1:]))
}

func ejecutar(args []string) int {
	comando, dato := "", ""
	if len(args) > 0 {
		comando = args[0]
	}
	if len(args) > 1 {
		dato = args[1]
	}
	if comando == "" || comando == "-h" || comando == "--help" || comando == "ayuda" {
		fmt.Println(uso)
		return 0
	}

	api, err := Nuevo()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}

	type accion struct {
		fn           func(string, any) error
		necesitaDato bool
	}
	comandos := map[string]accion{
		"ruc":            {api.Ruc, true},
		"dni":            {api.Dni, true},
		"tipo-cambio":    {func(_ string, d any) error { return api.TipoCambio(d) }, false},
		"ubigeo":         {api.Ubigeo, true},
		"empresas":       {api.Empresas, true},
		"anexos":         {api.Anexos, true},
		"representantes": {api.Representantes, true},
		"trabajadores":   {api.Trabajadores, true},
	}
	entrada, ok := comandos[comando]
	if !ok {
		fmt.Fprintf(os.Stderr, "Comando desconocido: %s\n\n%s\n", comando, uso)
		return 2
	}
	if entrada.necesitaDato && dato == "" {
		fmt.Fprintf(os.Stderr, "El comando '%s' necesita un dato.\n", comando)
		return 2
	}

	var resultado json.RawMessage
	if err := entrada.fn(dato, &resultado); err != nil {
		var e *Error
		if errors.As(err, &e) {
			fmt.Fprintf(os.Stderr, "Error HTTP %d (%s): %s\n", e.Status, e.Codigo, e.Mensaje)
			for campo, motivo := range e.Detalles {
				fmt.Fprintf(os.Stderr, "  %s: %s\n", campo, motivo)
			}
			return 1
		}
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	var bonito bytes.Buffer
	_ = json.Indent(&bonito, resultado, "", "  ")
	fmt.Println(bonito.String())
	if api.CreditosDisponibles >= 0 {
		fmt.Fprintf(os.Stderr, "Créditos disponibles: %d\n", api.CreditosDisponibles)
	}
	return 0
}
