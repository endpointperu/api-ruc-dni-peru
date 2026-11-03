#!/usr/bin/env python3
"""endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Python.

Cliente mínimo con la biblioteca estándar (sin dependencias). Cubre todas las APIs
de https://endpoint.pe/docs y sirve como punto de partida para tu integración.

Uso desde la terminal:
    export ENDPOINT_API_KEY=ep_live_...
    python consulta.py ruc 20131312955
    python consulta.py dni 45871236
    python consulta.py tipo-cambio
    python consulta.py ubigeo 150101
    python consulta.py empresas "superintendencia aduanas"
    python consulta.py anexos 20131312955
    python consulta.py representantes 20131312955
    python consulta.py trabajadores 20131312955

Uso desde tu código:
    from consulta import EndpointPe, EndpointError

    api = EndpointPe()                      # lee ENDPOINT_API_KEY del entorno
    ficha = api.ruc("20131312955")
    print(ficha["razon_social"], ficha["estado"], api.creditos_disponibles)

Requisitos: Python 3.8 o superior.
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any, Callable, Dict, Optional
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

BASE_URL = os.environ.get("ENDPOINT_BASE_URL", "https://api.endpoint.pe/v1")
TIMEOUT = 15  # segundos de espera por respuesta
REINTENTOS = 3  # solo ante errores de red o 5xx; nunca ante 404 o 422

Json = Dict[str, Any]


class EndpointError(Exception):
    """La API respondió con success=false.

    `error` es el código estable para comparar en tu código (no_encontrado, validacion,
    sin_creditos…); `message` es un texto en español que puedes mostrar tal cual.
    """

    def __init__(self, status: int, error: str, message: str, detalles: Optional[Dict[str, str]] = None):
        super().__init__(f"HTTP {status} · {error}: {message}")
        self.status = status
        self.error = error
        self.message = message
        self.detalles = detalles or {}


class EndpointPe:
    """Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta."""

    def __init__(self, api_key: Optional[str] = None, base_url: str = BASE_URL):
        self.api_key = api_key or os.environ.get("ENDPOINT_API_KEY", "")
        if not self.api_key:
            raise ValueError("Falta la API key: define ENDPOINT_API_KEY o pásala al constructor.")
        self.base_url = base_url.rstrip("/")
        # Se actualiza con cada respuesta (suma de suscripción y prepago).
        self.creditos_disponibles: Optional[int] = None

    # --- Empresas (SUNAT) ---------------------------------------------------

    def ruc(self, ruc: str) -> Json:
        """Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones."""
        return self._get(f"/ruc/{quote(ruc, safe='')}")

    def anexos(self, ruc: str) -> Json:
        """Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC."""
        return self._get(f"/ruc/{quote(ruc, safe='')}/anexos")

    def representantes(self, ruc: str) -> Json:
        """Representantes legales con documento, cargo y fecha de nombramiento."""
        return self._get(f"/ruc/{quote(ruc, safe='')}/representantes")

    def trabajadores(self, ruc: str) -> Json:
        """Trabajadores, pensionistas y prestadores de servicio declarados por periodo."""
        return self._get(f"/ruc/{quote(ruc, safe='')}/trabajadores")

    def empresas(self, texto: str) -> Json:
        """Busca el RUC de una empresa por su razón social (hasta 20 coincidencias)."""
        return self._get("/empresas", {"q": texto})

    # --- Identidad (RENIEC) ------------------------------------------------

    def dni(self, dni: str) -> Json:
        """Nombres y apellidos del titular, dígito verificador y RUC de persona natural."""
        return self._get(f"/dni/{quote(dni, safe='')}")

    # --- Finanzas y ubicación -----------------------------------------------

    def tipo_cambio(self) -> Json:
        """Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT."""
        return self._get("/tipo-cambio")

    def ubigeo(self, codigo: str) -> Json:
        """Departamento, provincia y distrito de un código de ubigeo de 6 dígitos."""
        return self._get(f"/ubigeo/{quote(codigo, safe='')}")

    def ubigeo_por_nombres(
        self,
        departamento: Optional[str] = None,
        provincia: Optional[str] = None,
        distrito: Optional[str] = None,
    ) -> Json:
        """Lista departamentos, provincias o distritos, o arma el código a partir de los nombres."""
        params = {k: v for k, v in (("departamento", departamento), ("provincia", provincia), ("distrito", distrito)) if v}
        return self._get("/ubigeo", params or None)

    # --- Petición HTTP ------------------------------------------------------

    def _get(self, path: str, params: Optional[Dict[str, str]] = None) -> Json:
        url = self.base_url + path
        if params:
            url += "?" + urlencode(params)
        peticion = Request(
            url,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Accept": "application/json",
                "User-Agent": "endpoint-pe-ejemplos/python",
            },
        )

        for intento in range(1, REINTENTOS + 1):
            try:
                with urlopen(peticion, timeout=TIMEOUT) as respuesta:
                    cuerpo = json.load(respuesta)
                    self.creditos_disponibles = cuerpo.get("meta", {}).get("creditos_disponibles")
                    return cuerpo["data"]
            except HTTPError as exc:
                if exc.code >= 500 and intento < REINTENTOS:
                    time.sleep(2 ** (intento - 1))
                    continue
                cuerpo = _leer_json(exc)
                restantes = exc.headers.get("X-Credits-Remaining")
                if restantes is not None:
                    self.creditos_disponibles = int(restantes)
                raise EndpointError(
                    exc.code,
                    cuerpo.get("error", "error"),
                    cuerpo.get("message", str(exc.reason)),
                    cuerpo.get("detalles"),
                ) from None
            except OSError as exc:  # sin red, DNS, timeout
                if intento < REINTENTOS:
                    time.sleep(2 ** (intento - 1))
                    continue
                raise EndpointError(0, "red", f"No se pudo conectar con la API: {exc}") from None
        raise AssertionError("inalcanzable")


def _leer_json(exc: HTTPError) -> Json:
    try:
        return json.loads(exc.read().decode("utf-8"))
    except Exception:  # noqa: BLE001 - un cuerpo no JSON se trata como vacío
        return {}


def es_ruc_valido(ruc: str) -> bool:
    """Valida el formato antes de consultar: 11 dígitos, prefijo 10/15/16/17/20 y dígito verificador (módulo 11)."""
    if len(ruc) != 11 or not ruc.isdigit() or ruc[:2] not in {"10", "15", "16", "17", "20"}:
        return False
    pesos = (5, 4, 3, 2, 7, 6, 5, 4, 3, 2)
    resto = 11 - sum(int(d) * p for d, p in zip(ruc[:10], pesos)) % 11
    verificador = {10: 0, 11: 1}.get(resto, resto)
    return verificador == int(ruc[10])


# --- Uso desde la terminal ----------------------------------------------------

USO = """Uso: python consulta.py <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys"""


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help", "ayuda"):
        print(USO)
        return 0

    comando, dato = argv[0], (argv[1] if len(argv) > 1 else "")
    try:
        api = EndpointPe()
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 2

    # comando -> (función, necesita dato)
    comandos: Dict[str, tuple[Callable[..., Json], bool]] = {
        "ruc": (api.ruc, True),
        "dni": (api.dni, True),
        "tipo-cambio": (api.tipo_cambio, False),
        "ubigeo": (api.ubigeo, True),
        "empresas": (api.empresas, True),
        "anexos": (api.anexos, True),
        "representantes": (api.representantes, True),
        "trabajadores": (api.trabajadores, True),
    }
    if comando not in comandos:
        print(f"Comando desconocido: {comando}\n\n{USO}", file=sys.stderr)
        return 2
    funcion, necesita_dato = comandos[comando]
    if necesita_dato and not dato:
        print(f"El comando '{comando}' necesita un dato.", file=sys.stderr)
        return 2

    try:
        resultado = funcion(dato) if necesita_dato else funcion()
    except EndpointError as exc:
        print(f"Error HTTP {exc.status} ({exc.error}): {exc.message}", file=sys.stderr)
        for campo, motivo in exc.detalles.items():
            print(f"  {campo}: {motivo}", file=sys.stderr)
        return 1

    print(json.dumps(resultado, ensure_ascii=False, indent=2))
    if api.creditos_disponibles is not None:
        print(f"Créditos disponibles: {api.creditos_disponibles}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
