# Elixir (y Phoenix)

Cliente mínimo de la API de endpoint.pe con [Req](https://hexdocs.pm/req). Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Elixir 1.14 o superior (OTP 25+). El script instala Req solo, con `Mix.install`, la primera vez que se ejecuta.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

elixir consulta.exs ruc 20131312955
elixir consulta.exs dni 45871236
elixir consulta.exs tipo-cambio
elixir consulta.exs ubigeo 150101
elixir consulta.exs empresas "superintendencia aduanas"
elixir consulta.exs anexos 20131312955
elixir consulta.exs representantes 20131312955
elixir consulta.exs trabajadores 20131312955
```

## Usar en tu proyecto

Agrega `{:req, "~> 0.5"}` a `mix.exs`, copia el módulo `EndpointPe` (sin la línea `Mix.install` ni la parte de terminal) a `lib/` y guarda la clave en la configuración en tiempo de ejecución (`config/runtime.exs`, leyendo `System.get_env("ENDPOINT_API_KEY")`):

```elixir
api = EndpointPe.nuevo() # lee ENDPOINT_API_KEY; también acepta EndpointPe.nuevo("ep_live_...")

case EndpointPe.ruc(api, "20131312955") do
  {:ok, ficha, creditos} -> IO.puts("#{ficha["razon_social"]} · #{ficha["estado"]} · #{ficha["condicion"]} (quedan #{creditos})")
  {:error, %EndpointPe.Error{error: "no_encontrado"}} -> IO.puts("RUC no inscrito")
  {:error, e} -> IO.puts(Exception.message(e)) # HTTP 422 · validacion: …
end

{:ok, tc, _} = EndpointPe.tipo_cambio(api)
IO.puts("#{tc["fecha"]} compra #{tc["compra"]} venta #{tc["venta"]}")
```

Cada función devuelve `{:ok, data, creditos_disponibles}` o `{:error, %EndpointPe.Error{status, error, mensaje, detalles}}`. Req reintenta solo los errores de red y los 5xx, con espera creciente.

En Phoenix, crea el `Req.Request` una vez (por ejemplo en un módulo de contexto) y, si consultas los mismos RUC con frecuencia, guarda el resultado en ETS o en `Cachex`.
