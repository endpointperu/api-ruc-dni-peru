# Python

Cliente mínimo de la API de endpoint.pe con la biblioteca estándar: sin instalar nada. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Python 3.8 o superior.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

python consulta.py ruc 20131312955
python consulta.py dni 45871236
python consulta.py tipo-cambio
python consulta.py ubigeo 150101
python consulta.py empresas "superintendencia aduanas"
python consulta.py anexos 20131312955
python consulta.py representantes 20131312955
python consulta.py trabajadores 20131312955
```

## Usar en tu proyecto

Copia `consulta.py` a tu proyecto e importa el cliente:

```python
from consulta import EndpointPe, EndpointError, es_ruc_valido

api = EndpointPe()  # lee ENDPOINT_API_KEY; también acepta EndpointPe(api_key="ep_live_...")

if es_ruc_valido("20131312955"):          # valida el formato antes de gastar una llamada
    try:
        ficha = api.ruc("20131312955")
        print(ficha["razon_social"], ficha["estado"], ficha["condicion"])
    except EndpointError as e:
        if e.error == "no_encontrado":
            print("RUC no inscrito")
        else:
            print(e.status, e.error, e.message)

tc = api.tipo_cambio()
print(tc["fecha"], tc["compra"], tc["venta"])
print("Créditos disponibles:", api.creditos_disponibles)
```

Cada método devuelve el objeto `data` de la respuesta y actualiza `creditos_disponibles`. Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `message` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## Con `requests`

Si ya usas [`requests`](https://requests.readthedocs.io/) en tu proyecto, la llamada se reduce a:

```python
import os, requests

r = requests.get(
    "https://api.endpoint.pe/v1/ruc/20131312955",
    headers={"Authorization": f"Bearer {os.environ['ENDPOINT_API_KEY']}"},
    timeout=15,
)
cuerpo = r.json()
if cuerpo["success"]:
    print(cuerpo["data"]["razon_social"])
else:
    print(r.status_code, cuerpo["error"], cuerpo["message"])
```

## Django y FastAPI

Instancia `EndpointPe` una sola vez (por ejemplo en un módulo de servicios) y reutilízala en tus vistas. Guarda la clave en la configuración del entorno, nunca en `settings.py`. Si consultas el mismo RUC o DNI con frecuencia, guarda el resultado en caché: los datos cambian poco y cada 200 descuenta un crédito.

Guías relacionadas: [Consultar DNI con Python](https://endpoint.pe/blog/consultar-dni-con-python) y [Caché de consultas RUC y DNI](https://endpoint.pe/blog/cache-de-consultas-ruc-y-dni).
