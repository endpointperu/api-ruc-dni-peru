# Ruby (y Rails)

Cliente mínimo de la API de endpoint.pe con `net/http` y `json`, sin gemas. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Ruby 2.7 o superior.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

ruby consulta.rb ruc 20131312955
ruby consulta.rb dni 45871236
ruby consulta.rb tipo-cambio
ruby consulta.rb ubigeo 150101
ruby consulta.rb empresas "superintendencia aduanas"
ruby consulta.rb anexos 20131312955
ruby consulta.rb representantes 20131312955
ruby consulta.rb trabajadores 20131312955
```

## Usar en tu proyecto

```ruby
require_relative 'consulta'

api = EndpointPe.new # lee ENDPOINT_API_KEY; también acepta EndpointPe.new('ep_live_...')

if ruc_valido?('20131312955')            # valida el formato antes de gastar una llamada
  begin
    ficha = api.ruc('20131312955')
    puts "#{ficha['razon_social']} · #{ficha['estado']} · #{ficha['condicion']}"
  rescue EndpointError => e
    puts e.error == 'no_encontrado' ? 'RUC no inscrito' : "#{e.status} #{e.error} #{e.mensaje}"
  end
end

tc = api.tipo_cambio
puts "#{tc['fecha']} compra #{tc['compra']} venta #{tc['venta']}"
puts "Créditos disponibles: #{api.creditos_disponibles}"
```

Cada método devuelve el objeto `data` como `Hash` y actualiza `creditos_disponibles`. Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Rails

Guarda la clave en `Rails.application.credentials` o en la variable de entorno, crea el cliente en un servicio (`app/services/endpoint_pe.rb`) y envuelve las consultas repetidas en `Rails.cache.fetch("ruc/#{ruc}", expires_in: 12.hours)`. Si ya usas Faraday o HTTParty, basta con la cabecera `Authorization: Bearer …` y leer `success`, `data` y `error` del JSON.
