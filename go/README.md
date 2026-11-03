# Go

Cliente mínimo de la API de endpoint.pe con `net/http` y `encoding/json`, sin módulos externos. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores, e incluye los structs `Ruc`, `Dni`, `TipoCambio` y `Ubigeo` listos para usar.

## Requisitos

- Go 1.21 o superior.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

go run . ruc 20131312955
go run . dni 45871236
go run . tipo-cambio
go run . ubigeo 150101
go run . empresas "superintendencia aduanas"
go run . anexos 20131312955
go run . representantes 20131312955
go run . trabajadores 20131312955
```

Para generar un binario: `go build -o consulta . && ./consulta ruc 20131312955`.

## Usar en tu proyecto

Copia `main.go` a un paquete tuyo (por ejemplo `endpointpe`) y cambia `package main`. Cada método decodifica el objeto `data` en el destino que le pases:

```go
api, err := endpointpe.Nuevo() // lee ENDPOINT_API_KEY; o NuevoConClave("ep_live_...")
if err != nil {
	log.Fatal(err)
}

var ficha endpointpe.Ruc
if err := api.Ruc("20131312955", &ficha); err != nil {
	var e *endpointpe.Error
	if errors.As(err, &e) && e.Codigo == "no_encontrado" {
		fmt.Println("RUC no inscrito")
	} else {
		log.Fatal(err)
	}
}
fmt.Println(ficha.RazonSocial, ficha.Estado, ficha.Condicion)

var tc endpointpe.TipoCambio
_ = api.TipoCambio(&tc)
fmt.Println(tc.Fecha, tc.Compra, tc.Venta, "créditos:", api.CreditosDisponibles)
```

Para las consultas sin struct definido (anexos, representantes, trabajadores, empresas) pasa un `*json.RawMessage` o un `map[string]any`, o declara tu propio struct siguiendo la [referencia de la API](https://endpoint.pe/docs). Los campos que la fuente puede no tener están declarados como punteros: `nil` significa "sin información".

Los errores (404, 422, 402…) llegan como `*Error` con `Status`, `Codigo`, `Mensaje` y `Detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.
