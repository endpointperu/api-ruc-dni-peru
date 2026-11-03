# Lua

Cliente mínimo de la API de endpoint.pe con LuaSocket, LuaSec y dkjson. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores. Sirve también en OpenResty/nginx y en scripts de automatización.

## Requisitos

- Lua 5.1 o superior (también LuaJIT).
- `luarocks install luasocket luasec dkjson`

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

lua consulta.lua ruc 20131312955
lua consulta.lua dni 45871236
lua consulta.lua tipo-cambio
lua consulta.lua ubigeo 150101
lua consulta.lua empresas "superintendencia aduanas"
lua consulta.lua anexos 20131312955
lua consulta.lua representantes 20131312955
lua consulta.lua trabajadores 20131312955
```

## Usar en tu proyecto

```lua
local EndpointPe = require("consulta")
local api = EndpointPe.nuevo() -- lee ENDPOINT_API_KEY; también acepta EndpointPe.nuevo("ep_live_...")

local ficha, err = api:ruc("20131312955")
if ficha then
  print(ficha.razon_social, ficha.estado, ficha.condicion)
elseif err.error == "no_encontrado" then
  print("RUC no inscrito")
else
  print("Error HTTP " .. err.status .. " (" .. err.error .. "): " .. err.message)
end

local tc = api:tipo_cambio()
print(tc.fecha, tc.compra, tc.venta, "créditos:", api.creditos_disponibles)
```

Cada método devuelve la tabla `data` o, si falla, `nil` y una tabla con `status`, `error`, `message` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## OpenResty

Dentro de nginx usa [lua-resty-http](https://github.com/ledgetech/lua-resty-http) en lugar de LuaSec (no bloquea el worker) y `cjson` para el JSON; el resto de la lógica es la misma: cabecera `Authorization: Bearer …` y leer `success`, `data` y `error`.
