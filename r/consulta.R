#!/usr/bin/env Rscript
# endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde R.
#
# Dependencias: httr2 y jsonlite  →  install.packages(c("httr2", "jsonlite"))
#
# Uso desde la terminal:
#   export ENDPOINT_API_KEY=ep_live_...
#   Rscript consulta.R ruc 20131312955
#   Rscript consulta.R dni 45871236
#   Rscript consulta.R tipo-cambio
#   Rscript consulta.R ubigeo 150101
#   Rscript consulta.R empresas "superintendencia aduanas"
#   Rscript consulta.R anexos 20131312955
#   Rscript consulta.R representantes 20131312955
#   Rscript consulta.R trabajadores 20131312955
#
# Uso desde tu código:
#   source("consulta.R")
#   ficha <- consultar_ruc("20131312955")
#   ficha$razon_social
#
# Requisitos: R 4.1 o superior.
# Documentación: https://endpoint.pe/docs

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

BASE_URL <- sub("/+$", "", Sys.getenv("ENDPOINT_BASE_URL", "https://api.endpoint.pe/v1"))
TIMEOUT <- 15
REINTENTOS <- 3 # solo ante errores de red o 5xx; nunca ante 404 o 422

`%||%` <- function(a, b) if (is.null(a)) b else a

# Hace la petición y devuelve el objeto `data` como lista. Ante un error de la API lanza una
# condición de clase "endpoint_error" con status, error (código estable), mensaje y detalles.
endpoint_get <- function(ruta, params = list(), api_key = Sys.getenv("ENDPOINT_API_KEY")) {
  if (!nzchar(api_key)) stop("Falta la API key: define ENDPOINT_API_KEY.", call. = FALSE)

  req <- request(paste0(BASE_URL, ruta)) |>
    req_auth_bearer_token(api_key) |>
    req_headers(Accept = "application/json", `User-Agent` = "endpoint-pe-ejemplos/r") |>
    req_timeout(TIMEOUT) |>
    req_retry(max_tries = REINTENTOS, is_transient = function(resp) resp_status(resp) >= 500) |>
    req_error(is_error = function(resp) FALSE)
  if (length(params) > 0) req <- req_url_query(req, !!!params)

  resp <- req_perform(req)
  status <- resp_status(resp)
  cuerpo <- tryCatch(resp_body_json(resp), error = function(e) list())

  if (status != 200 || !isTRUE(cuerpo$success)) {
    stop(structure(
      list(
        message = sprintf("Error HTTP %d (%s): %s", status, cuerpo$error %||% "error",
                          cuerpo$message %||% "Respuesta inesperada"),
        status = status,
        error = cuerpo$error %||% "error",
        mensaje = cuerpo$message %||% "",
        detalles = cuerpo$detalles %||% list(),
        call = NULL
      ),
      class = c("endpoint_error", "error", "condition")
    ))
  }
  datos <- cuerpo$data
  attr(datos, "creditos_disponibles") <- cuerpo$meta$creditos_disponibles
  datos
}

codificar <- function(valor) utils::URLencode(as.character(valor), reserved = TRUE)

# Empresas (SUNAT)
consultar_ruc <- function(ruc) endpoint_get(paste0("/ruc/", codificar(ruc)))                              # ficha del contribuyente
consultar_anexos <- function(ruc) endpoint_get(paste0("/ruc/", codificar(ruc), "/anexos"))                # establecimientos anexos
consultar_representantes <- function(ruc) endpoint_get(paste0("/ruc/", codificar(ruc), "/representantes")) # representantes legales
consultar_trabajadores <- function(ruc) endpoint_get(paste0("/ruc/", codificar(ruc), "/trabajadores"))     # trabajadores por periodo
buscar_empresas <- function(texto) endpoint_get("/empresas", list(q = texto))                             # RUC por razón social
# Identidad (RENIEC)
consultar_dni <- function(dni) endpoint_get(paste0("/dni/", codificar(dni)))                              # nombres y apellidos
# Finanzas y ubicación
tipo_cambio <- function() endpoint_get("/tipo-cambio")                                                    # compra y venta de hoy
consultar_ubigeo <- function(codigo) endpoint_get(paste0("/ubigeo/", codificar(codigo)))                  # departamento, provincia, distrito

# --- Uso desde la terminal (no se ejecuta al hacer source()) ---

if (sys.nframe() == 0L) {
  uso <- "Uso: Rscript consulta.R <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys"

  args <- commandArgs(trailingOnly = TRUE)
  comando <- if (length(args) >= 1) args[[1]] else ""
  dato <- if (length(args) >= 2) args[[2]] else ""
  if (comando == "" || comando %in% c("-h", "--help", "ayuda")) {
    cat(uso, "\n")
    quit(status = 0)
  }

  comandos <- list(
    "ruc" = list(consultar_ruc, TRUE),
    "dni" = list(consultar_dni, TRUE),
    "tipo-cambio" = list(tipo_cambio, FALSE),
    "ubigeo" = list(consultar_ubigeo, TRUE),
    "empresas" = list(buscar_empresas, TRUE),
    "anexos" = list(consultar_anexos, TRUE),
    "representantes" = list(consultar_representantes, TRUE),
    "trabajadores" = list(consultar_trabajadores, TRUE)
  )
  if (is.null(comandos[[comando]])) {
    message("Comando desconocido: ", comando, "\n\n", uso)
    quit(status = 2)
  }
  funcion <- comandos[[comando]][[1]]
  necesita_dato <- comandos[[comando]][[2]]
  if (necesita_dato && dato == "") {
    message("El comando '", comando, "' necesita un dato.")
    quit(status = 2)
  }

  resultado <- tryCatch(
    if (necesita_dato) funcion(dato) else funcion(),
    endpoint_error = function(e) {
      message(conditionMessage(e))
      for (campo in names(e$detalles)) message("  ", campo, ": ", e$detalles[[campo]])
      quit(status = 1)
    },
    error = function(e) {
      message(conditionMessage(e))
      quit(status = 2)
    }
  )
  cat(toJSON(resultado, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
  restantes <- attr(resultado, "creditos_disponibles")
  if (!is.null(restantes)) message("Créditos disponibles: ", restantes)
}
