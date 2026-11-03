#!/usr/bin/env lua
-- endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Lua.
--
-- Dependencias: luasocket, luasec y dkjson  →  luarocks install luasocket luasec dkjson
--
-- Uso desde la terminal:
--   export ENDPOINT_API_KEY=ep_live_...
--   lua consulta.lua ruc 20131312955
--   lua consulta.lua dni 45871236
--   lua consulta.lua tipo-cambio
--   lua consulta.lua ubigeo 150101
--   lua consulta.lua empresas "superintendencia aduanas"
--   lua consulta.lua anexos 20131312955
--   lua consulta.lua representantes 20131312955
--   lua consulta.lua trabajadores 20131312955
--
-- Uso desde tu código:
--   local EndpointPe = require("consulta")
--   local api = EndpointPe.nuevo()                    -- lee ENDPOINT_API_KEY del entorno
--   local ficha, err = api:ruc("20131312955")         -- tabla con el objeto `data`, o nil + error
--   print(ficha.razon_social, ficha.estado, api.creditos_disponibles)
--
-- Requisitos: Lua 5.1 o superior (incluido LuaJIT).
-- Documentación: https://endpoint.pe/docs

local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local json = require("dkjson")

local BASE_URL = (os.getenv("ENDPOINT_BASE_URL") or "https://api.endpoint.pe/v1"):gsub("/+$", "")
local TIMEOUT = 15
local REINTENTOS = 3 -- solo ante errores de red o 5xx; nunca ante 404 o 422

https.TIMEOUT = TIMEOUT

local EndpointPe = {}
EndpointPe.__index = EndpointPe

--- Crea el cliente con la API key indicada o la de ENDPOINT_API_KEY.
function EndpointPe.nuevo(api_key)
  api_key = api_key or os.getenv("ENDPOINT_API_KEY")
  if not api_key or api_key == "" then
    error("Falta la API key: define ENDPOINT_API_KEY o pásala a EndpointPe.nuevo().", 0)
  end
  -- creditos_disponibles: suscripción + prepago, se actualiza con cada respuesta
  return setmetatable({ api_key = api_key, creditos_disponibles = nil }, EndpointPe)
end

local function codificar(valor)
  return (tostring(valor):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

--- GET a la ruta. Devuelve la tabla `data` en éxito, o nil y una tabla de error
--- {status, error, message, detalles}. `error` es el código estable (no_encontrado,
--- validacion, sin_creditos…); `message` es texto en español.
function EndpointPe:get(ruta)
  for intento = 1, REINTENTOS do
    local partes = {}
    local ok, status, cabeceras = https.request({
      url = BASE_URL .. ruta,
      method = "GET",
      headers = {
        ["Authorization"] = "Bearer " .. self.api_key,
        ["Accept"] = "application/json",
        ["User-Agent"] = "endpoint-pe-ejemplos/lua",
      },
      sink = ltn12.sink.table(partes),
    })

    if not ok then
      if intento < REINTENTOS then
        socket.sleep(2 ^ (intento - 1))
      else
        return nil, { status = 0, error = "red", message = "No se pudo conectar con la API: " .. tostring(status) }
      end
    elseif status >= 500 and intento < REINTENTOS then
      socket.sleep(2 ^ (intento - 1))
    else
      if cabeceras and cabeceras["x-credits-remaining"] then
        self.creditos_disponibles = tonumber(cabeceras["x-credits-remaining"])
      end
      local cuerpo = json.decode(table.concat(partes)) or {}
      if status ~= 200 or cuerpo.success ~= true or type(cuerpo.data) ~= "table" then
        return nil, {
          status = status,
          error = cuerpo.error or "error",
          message = cuerpo.message or ("Respuesta inesperada (HTTP " .. tostring(status) .. ")"),
          detalles = cuerpo.detalles,
        }
      end
      return cuerpo.data
    end
  end
end

-- Empresas (SUNAT)
function EndpointPe:ruc(ruc) return self:get("/ruc/" .. codificar(ruc)) end                               -- ficha del contribuyente
function EndpointPe:anexos(ruc) return self:get("/ruc/" .. codificar(ruc) .. "/anexos") end               -- establecimientos anexos
function EndpointPe:representantes(ruc) return self:get("/ruc/" .. codificar(ruc) .. "/representantes") end -- representantes legales
function EndpointPe:trabajadores(ruc) return self:get("/ruc/" .. codificar(ruc) .. "/trabajadores") end   -- trabajadores por periodo
function EndpointPe:empresas(texto) return self:get("/empresas?q=" .. codificar(texto)) end               -- RUC por razón social
-- Identidad (RENIEC)
function EndpointPe:dni(dni) return self:get("/dni/" .. codificar(dni)) end                               -- nombres y apellidos
-- Finanzas y ubicación
function EndpointPe:tipo_cambio() return self:get("/tipo-cambio") end                                     -- compra y venta de hoy
function EndpointPe:ubigeo(codigo) return self:get("/ubigeo/" .. codificar(codigo)) end                   -- departamento, provincia, distrito

-- --- Uso desde la terminal (no se ejecuta al hacer require) ---

local es_principal = not pcall(debug.getlocal, 4, 1)
if es_principal then
  local USO = [[
Uso: lua consulta.lua <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys]]

  local comando, dato = arg[1] or "", arg[2] or ""
  if comando == "" or comando == "-h" or comando == "--help" or comando == "ayuda" then
    print(USO)
    os.exit(0)
  end

  local ok, api = pcall(EndpointPe.nuevo)
  if not ok then
    io.stderr:write(api, "\n")
    os.exit(2)
  end

  local comandos = {
    ["ruc"] = { function(d) return api:ruc(d) end, true },
    ["dni"] = { function(d) return api:dni(d) end, true },
    ["tipo-cambio"] = { function() return api:tipo_cambio() end, false },
    ["ubigeo"] = { function(d) return api:ubigeo(d) end, true },
    ["empresas"] = { function(d) return api:empresas(d) end, true },
    ["anexos"] = { function(d) return api:anexos(d) end, true },
    ["representantes"] = { function(d) return api:representantes(d) end, true },
    ["trabajadores"] = { function(d) return api:trabajadores(d) end, true },
  }
  local entrada = comandos[comando]
  if not entrada then
    io.stderr:write("Comando desconocido: ", comando, "\n\n", USO, "\n")
    os.exit(2)
  end
  if entrada[2] and dato == "" then
    io.stderr:write("El comando '", comando, "' necesita un dato.\n")
    os.exit(2)
  end

  local resultado, err = entrada[1](dato)
  if not resultado then
    io.stderr:write(string.format("Error HTTP %s (%s): %s\n", tostring(err.status), err.error, err.message))
    for campo, motivo in pairs(err.detalles or {}) do
      io.stderr:write("  ", campo, ": ", tostring(motivo), "\n")
    end
    os.exit(1)
  end
  print(json.encode(resultado, { indent = true }))
  if api.creditos_disponibles then
    io.stderr:write("Créditos disponibles: ", tostring(api.creditos_disponibles), "\n")
  end
end

return EndpointPe
