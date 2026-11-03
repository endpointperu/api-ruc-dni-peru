# R

Consulta la API de endpoint.pe desde R con [httr2](https://httr2.r-lib.org/) y jsonlite. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores. Útil para limpiar padrones de clientes, enriquecer bases de datos y análisis con datos de SUNAT.

## Requisitos

- R 4.1 o superior.
- Paquetes: `install.packages(c("httr2", "jsonlite"))`

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

Rscript consulta.R ruc 20131312955
Rscript consulta.R dni 45871236
Rscript consulta.R tipo-cambio
Rscript consulta.R ubigeo 150101
Rscript consulta.R empresas "superintendencia aduanas"
Rscript consulta.R anexos 20131312955
Rscript consulta.R representantes 20131312955
Rscript consulta.R trabajadores 20131312955
```

## Usar en tus análisis

```r
source("consulta.R")   # define las funciones sin ejecutar nada

ficha <- consultar_ruc("20131312955")
ficha$razon_social
ficha$estado

# Enriquecer un data frame de proveedores (una llamada por RUC, con manejo de errores)
proveedores <- data.frame(ruc = c("20131312955", "20100000001"))
proveedores$razon_social <- vapply(proveedores$ruc, function(r) {
  tryCatch(consultar_ruc(r)$razon_social, endpoint_error = function(e) NA_character_)
}, character(1))

tc <- tipo_cambio()
tc$venta
```

Cada función devuelve el objeto `data` como lista (con el atributo `creditos_disponibles`). Los errores de la API (404 `no_encontrado`, 422 `validacion`, 402 `sin_creditos`…) son condiciones de clase `endpoint_error` con `status`, `error`, `mensaje` y `detalles`, así puedes capturarlas con `tryCatch`. Los errores de red y los 5xx se reintentan hasta tres veces.

Para muchas filas, guarda los resultados (`saveRDS`) y no repitas las consultas: cada respuesta con resultado descuenta un crédito.
