#!/usr/bin/env bash
# endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde la terminal.
#
# Requisitos: bash 4+, curl. Opcional: jq, para mostrar la respuesta con formato.
#
# Uso:
#   export ENDPOINT_API_KEY=ep_live_...
#   ./consulta.sh ruc 20131312955
#   ./consulta.sh dni 45871236
#   ./consulta.sh tipo-cambio
#   ./consulta.sh ubigeo 150101
#   ./consulta.sh empresas "superintendencia aduanas"
#   ./consulta.sh anexos 20131312955
#   ./consulta.sh representantes 20131312955
#   ./consulta.sh trabajadores 20131312955
#
# Documentación: https://endpoint.pe/docs
set -euo pipefail

BASE_URL="${ENDPOINT_BASE_URL:-https://api.endpoint.pe/v1}"
API_KEY="${ENDPOINT_API_KEY:-}"
TIMEOUT=15

uso() {
  cat <<'TXT'
Uso: ./consulta.sh <comando> [dato]

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
}

# consultar <ruta> [clave=valor ...]
# Hace la petición GET, imprime el JSON y devuelve 0 solo si la respuesta fue 200.
consultar() {
  local ruta="$1"; shift
  local params=()
  for p in "$@"; do params+=(--data-urlencode "$p"); done

  local cuerpo status
  cuerpo=$(mktemp)
  status=$(curl --silent --show-error --get "$BASE_URL$ruta" \
    ${params[@]+"${params[@]}"} \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json" \
    --max-time "$TIMEOUT" \
    --output "$cuerpo" \
    --write-out '%{http_code}') || { rm -f "$cuerpo"; echo "No se pudo conectar con la API." >&2; return 1; }

  if command -v jq >/dev/null 2>&1; then
    jq . "$cuerpo"
  else
    cat "$cuerpo"; echo
  fi
  rm -f "$cuerpo"

  if [[ "$status" != "200" ]]; then
    echo "La API respondió HTTP $status (revisa los campos error y message)." >&2
    return 1
  fi
}

requiere_dato() {
  if [[ -z "${2:-}" ]]; then
    echo "El comando '$1' necesita un dato. Ejemplo: ./consulta.sh $1 $3" >&2
    exit 2
  fi
}

comando="${1:-}"
dato="${2:-}"

case "$comando" in
  ""|-h|--help|ayuda) uso; exit 0 ;;
esac

if [[ -z "$API_KEY" ]]; then
  echo "Falta la API key: export ENDPOINT_API_KEY=ep_live_..." >&2
  exit 2
fi

case "$comando" in
  ruc)            requiere_dato "$comando" "$dato" 20131312955; consultar "/ruc/$dato" ;;
  dni)            requiere_dato "$comando" "$dato" 45871236;    consultar "/dni/$dato" ;;
  tipo-cambio)    consultar "/tipo-cambio" ;;
  ubigeo)         requiere_dato "$comando" "$dato" 150101;      consultar "/ubigeo/$dato" ;;
  empresas)       requiere_dato "$comando" "$dato" '"superintendencia aduanas"'; consultar "/empresas" "q=$dato" ;;
  anexos)         requiere_dato "$comando" "$dato" 20131312955; consultar "/ruc/$dato/anexos" ;;
  representantes) requiere_dato "$comando" "$dato" 20131312955; consultar "/ruc/$dato/representantes" ;;
  trabajadores)   requiere_dato "$comando" "$dato" 20131312955; consultar "/ruc/$dato/trabajadores" ;;
  *) echo "Comando desconocido: $comando" >&2; uso >&2; exit 2 ;;
esac
