#!/usr/bin/env ruby
# frozen_string_literal: true

# endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Ruby.
#
# Sin gemas: usa net/http y json de la biblioteca estándar.
#
# Uso desde la terminal:
#   export ENDPOINT_API_KEY=ep_live_...
#   ruby consulta.rb ruc 20131312955
#   ruby consulta.rb dni 45871236
#   ruby consulta.rb tipo-cambio
#   ruby consulta.rb ubigeo 150101
#   ruby consulta.rb empresas "superintendencia aduanas"
#   ruby consulta.rb anexos 20131312955
#   ruby consulta.rb representantes 20131312955
#   ruby consulta.rb trabajadores 20131312955
#
# Uso desde tu código:
#   require_relative 'consulta'
#   api = EndpointPe.new                     # lee ENDPOINT_API_KEY del entorno
#   ficha = api.ruc('20131312955')
#   puts ficha['razon_social'], ficha['estado'], api.creditos_disponibles
#
# Requisitos: Ruby 2.7 o superior.
# Documentación: https://endpoint.pe/docs

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

# La API respondió con success=false. `error` es el código estable para comparar en tu
# código (no_encontrado, validacion, sin_creditos…); `mensaje` es texto en español.
class EndpointError < StandardError
  attr_reader :status, :error, :mensaje, :detalles

  def initialize(status, error, mensaje, detalles = {})
    super("HTTP #{status} · #{error}: #{mensaje}")
    @status = status
    @error = error
    @mensaje = mensaje
    @detalles = detalles
  end
end

# Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta como Hash.
class EndpointPe
  BASE_URL = ENV.fetch('ENDPOINT_BASE_URL', 'https://api.endpoint.pe/v1')
  TIMEOUT = 15     # segundos
  REINTENTOS = 3   # solo ante errores de red o 5xx; nunca ante 404 o 422

  # Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.
  attr_reader :creditos_disponibles

  def initialize(api_key = ENV['ENDPOINT_API_KEY'], base_url = BASE_URL)
    raise ArgumentError, 'Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.' if api_key.nil? || api_key.empty?

    @api_key = api_key
    @base_url = base_url.chomp('/')
    @creditos_disponibles = nil
  end

  # Empresas (SUNAT)

  # Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.
  def ruc(ruc)
    get("/ruc/#{codificar(ruc)}")
  end

  # Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.
  def anexos(ruc)
    get("/ruc/#{codificar(ruc)}/anexos")
  end

  # Representantes legales con documento, cargo y fecha de nombramiento.
  def representantes(ruc)
    get("/ruc/#{codificar(ruc)}/representantes")
  end

  # Trabajadores, pensionistas y prestadores de servicio declarados por periodo.
  def trabajadores(ruc)
    get("/ruc/#{codificar(ruc)}/trabajadores")
  end

  # Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).
  def empresas(texto)
    get('/empresas', q: texto)
  end

  # Identidad (RENIEC)

  # Nombres y apellidos del titular, dígito verificador y RUC de persona natural.
  def dni(dni)
    get("/dni/#{codificar(dni)}")
  end

  # Finanzas y ubicación

  # Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.
  def tipo_cambio
    get('/tipo-cambio')
  end

  # Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.
  def ubigeo(codigo)
    get("/ubigeo/#{codificar(codigo)}")
  end

  # Lista departamentos, provincias o distritos, o arma el código a partir de los nombres.
  def ubigeo_por_nombres(departamento: nil, provincia: nil, distrito: nil)
    get('/ubigeo', { departamento: departamento, provincia: provincia, distrito: distrito }.compact)
  end

  private

  def get(ruta, params = nil)
    uri = URI("#{@base_url}#{ruta}")
    uri.query = URI.encode_www_form(params) if params && !params.empty?

    (1..REINTENTOS).each do |intento|
      begin
        respuesta = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                        open_timeout: 10, read_timeout: TIMEOUT) do |http|
          peticion = Net::HTTP::Get.new(uri)
          peticion['Authorization'] = "Bearer #{@api_key}"
          peticion['Accept'] = 'application/json'
          peticion['User-Agent'] = 'endpoint-pe-ejemplos/ruby'
          http.request(peticion)
        end
      rescue SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
        raise EndpointError.new(0, 'red', "No se pudo conectar con la API: #{e.message}") if intento == REINTENTOS

        sleep(2**(intento - 1))
        next
      end

      status = respuesta.code.to_i
      if status >= 500 && intento < REINTENTOS
        sleep(2**(intento - 1))
        next
      end
      @creditos_disponibles = respuesta['X-Credits-Remaining'].to_i if respuesta['X-Credits-Remaining']

      cuerpo = begin
        JSON.parse(respuesta.body)
      rescue JSON::ParserError
        {}
      end
      unless status == 200 && cuerpo['success'] && cuerpo['data']
        raise EndpointError.new(status, cuerpo['error'] || 'error',
                                cuerpo['message'] || "Respuesta inesperada (HTTP #{status})",
                                cuerpo['detalles'] || {})
      end
      return cuerpo['data']
    end
  end

  def codificar(valor)
    URI.encode_www_form_component(valor.to_s)
  end
end

# Valida el formato de un RUC antes de consultar: 11 dígitos, prefijo 10/15/16/17/20 y dígito verificador.
def ruc_valido?(ruc)
  return false unless ruc.match?(/\A(10|15|16|17|20)\d{9}\z/)

  pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
  suma = pesos.each_with_index.sum { |peso, i| ruc[i].to_i * peso }
  resto = 11 - (suma % 11)
  verificador = { 10 => 0, 11 => 1 }.fetch(resto, resto)
  verificador == ruc[10].to_i
end

# --- Uso desde la terminal ---

if __FILE__ == $PROGRAM_NAME
  uso = <<~TXT
    Uso: ruby consulta.rb <comando> [dato]

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
  TXT

  comando = ARGV[0].to_s
  dato = ARGV[1].to_s
  if comando.empty? || %w[-h --help ayuda].include?(comando)
    puts uso
    exit 0
  end

  begin
    api = EndpointPe.new
  rescue ArgumentError => e
    warn e.message
    exit 2
  end

  comandos = {
    'ruc' => [->(d) { api.ruc(d) }, true],
    'dni' => [->(d) { api.dni(d) }, true],
    'tipo-cambio' => [->(_) { api.tipo_cambio }, false],
    'ubigeo' => [->(d) { api.ubigeo(d) }, true],
    'empresas' => [->(d) { api.empresas(d) }, true],
    'anexos' => [->(d) { api.anexos(d) }, true],
    'representantes' => [->(d) { api.representantes(d) }, true],
    'trabajadores' => [->(d) { api.trabajadores(d) }, true]
  }
  unless comandos.key?(comando)
    warn "Comando desconocido: #{comando}\n\n#{uso}"
    exit 2
  end
  funcion, necesita_dato = comandos[comando]
  if necesita_dato && dato.empty?
    warn "El comando '#{comando}' necesita un dato."
    exit 2
  end

  begin
    resultado = funcion.call(dato)
    puts JSON.pretty_generate(resultado)
    warn "Créditos disponibles: #{api.creditos_disponibles}" if api.creditos_disponibles
  rescue EndpointError => e
    warn "Error HTTP #{e.status} (#{e.error}): #{e.mensaje}"
    e.detalles.each { |campo, motivo| warn "  #{campo}: #{motivo}" }
    exit 1
  end
end
