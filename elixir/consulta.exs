#!/usr/bin/env elixir
# endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Elixir.
#
# Dependencia: Req (se instala sola con Mix.install la primera vez).
#
# Uso desde la terminal:
#   export ENDPOINT_API_KEY=ep_live_...
#   elixir consulta.exs ruc 20131312955
#   elixir consulta.exs dni 45871236
#   elixir consulta.exs tipo-cambio
#   elixir consulta.exs ubigeo 150101
#   elixir consulta.exs empresas "superintendencia aduanas"
#   elixir consulta.exs anexos 20131312955
#   elixir consulta.exs representantes 20131312955
#   elixir consulta.exs trabajadores 20131312955
#
# Uso desde tu código (en un proyecto Mix con {:req, "~> 0.5"}):
#   api = EndpointPe.nuevo()                                   # lee ENDPOINT_API_KEY del entorno
#   {:ok, ficha, creditos} = EndpointPe.ruc(api, "20131312955")
#   IO.puts("#{ficha["razon_social"]} #{ficha["estado"]} #{creditos}")
#
# Requisitos: Elixir 1.14 o superior (OTP 25+).
# Documentación: https://endpoint.pe/docs

Mix.install([{:req, "~> 0.5"}])

defmodule EndpointPe do
  @moduledoc "Cliente de la API v1 de endpoint.pe. Cada función devuelve {:ok, data, creditos_disponibles} o {:error, %EndpointPe.Error{}}."

  defmodule Error do
    @moduledoc "La API respondió con success=false. `error` es el código estable (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español."
    defexception [:status, :error, :mensaje, detalles: %{}]

    @impl true
    def message(%{status: status, error: error, mensaje: mensaje}), do: "HTTP #{status} · #{error}: #{mensaje}"
  end

  @base_url_por_defecto "https://api.endpoint.pe/v1"
  @timeout 15_000

  @doc "Crea el cliente (un `Req.Request`) con la API key indicada o la de ENDPOINT_API_KEY."
  def nuevo(api_key \\ System.get_env("ENDPOINT_API_KEY")) do
    if api_key in [nil, ""] do
      raise ArgumentError, "Falta la API key: define ENDPOINT_API_KEY o pásala a nuevo/1."
    end

    base = System.get_env("ENDPOINT_BASE_URL") || @base_url_por_defecto

    Req.new(
      base_url: String.trim_trailing(base, "/"),
      auth: {:bearer, api_key},
      headers: [accept: "application/json", user_agent: "endpoint-pe-ejemplos/elixir"],
      receive_timeout: @timeout,
      # reintenta solo errores de red y 5xx (nunca 404 ni 422), con espera creciente
      retry: :transient,
      max_retries: 2,
      retry_log_level: false
    )
  end

  # Empresas (SUNAT)
  def ruc(api, ruc), do: get(api, "/ruc/#{codificar(ruc)}")
  def anexos(api, ruc), do: get(api, "/ruc/#{codificar(ruc)}/anexos")
  def representantes(api, ruc), do: get(api, "/ruc/#{codificar(ruc)}/representantes")
  def trabajadores(api, ruc), do: get(api, "/ruc/#{codificar(ruc)}/trabajadores")
  def empresas(api, texto), do: get(api, "/empresas", params: [q: texto])
  # Identidad (RENIEC)
  def dni(api, dni), do: get(api, "/dni/#{codificar(dni)}")
  # Finanzas y ubicación
  def tipo_cambio(api), do: get(api, "/tipo-cambio")
  def ubigeo(api, codigo), do: get(api, "/ubigeo/#{codificar(codigo)}")

  defp get(api, ruta, opts \\ []) do
    case Req.get(api, [url: ruta] ++ opts) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true, "data" => data} = cuerpo}} ->
        {:ok, data, get_in(cuerpo, ["meta", "creditos_disponibles"])}

      {:ok, %Req.Response{status: status, body: cuerpo}} ->
        cuerpo = if is_map(cuerpo), do: cuerpo, else: %{}

        {:error,
         %Error{
           status: status,
           error: Map.get(cuerpo, "error", "error"),
           mensaje: Map.get(cuerpo, "message", "Respuesta inesperada (HTTP #{status})"),
           detalles: Map.get(cuerpo, "detalles") || %{}
         }}

      {:error, motivo} ->
        {:error, %Error{status: 0, error: "red", mensaje: "No se pudo conectar con la API: #{Exception.message(motivo)}"}}
    end
  end

  defp codificar(valor), do: URI.encode(to_string(valor), &URI.char_unreserved?/1)
end

# --- Uso desde la terminal ---

uso = """
Uso: elixir consulta.exs <comando> [dato]

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
"""

{comando, dato} =
  case System.argv() do
    [c, d | _] -> {c, d}
    [c] -> {c, ""}
    [] -> {"", ""}
  end

necesita_dato = %{
  "ruc" => true, "dni" => true, "tipo-cambio" => false, "ubigeo" => true,
  "empresas" => true, "anexos" => true, "representantes" => true, "trabajadores" => true
}

cond do
  comando in ["", "-h", "--help", "ayuda"] ->
    IO.puts(uso)

  not Map.has_key?(necesita_dato, comando) ->
    IO.puts(:stderr, "Comando desconocido: #{comando}\n\n#{uso}")
    System.halt(2)

  necesita_dato[comando] and dato == "" ->
    IO.puts(:stderr, "El comando '#{comando}' necesita un dato.")
    System.halt(2)

  true ->
    api =
      try do
        EndpointPe.nuevo()
      rescue
        e in ArgumentError ->
          IO.puts(:stderr, e.message)
          System.halt(2)
      end

    resultado =
      case comando do
        "ruc" -> EndpointPe.ruc(api, dato)
        "dni" -> EndpointPe.dni(api, dato)
        "tipo-cambio" -> EndpointPe.tipo_cambio(api)
        "ubigeo" -> EndpointPe.ubigeo(api, dato)
        "empresas" -> EndpointPe.empresas(api, dato)
        "anexos" -> EndpointPe.anexos(api, dato)
        "representantes" -> EndpointPe.representantes(api, dato)
        _ -> EndpointPe.trabajadores(api, dato)
      end

    case resultado do
      {:ok, data, creditos} ->
        IO.puts(Jason.encode!(data, pretty: true))
        if creditos, do: IO.puts(:stderr, "Créditos disponibles: #{creditos}")

      {:error, e} ->
        IO.puts(:stderr, "Error HTTP #{e.status} (#{e.error}): #{e.mensaje}")
        Enum.each(e.detalles, fn {campo, motivo} -> IO.puts(:stderr, "  #{campo}: #{motivo}") end)
        System.halt(1)
    end
end
