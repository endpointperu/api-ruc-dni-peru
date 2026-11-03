# Bash y cURL

Consulta RUC, DNI, tipo de cambio y ubigeo desde la terminal con `curl`. Útil para probar tu API key, para scripts de mantenimiento y para ver la respuesta cruda de la API.

## Requisitos

- bash 4 o superior y `curl` (vienen en Linux, macOS y WSL).
- Opcional: [`jq`](https://jqlang.github.io/jq/) para ver el JSON con formato y extraer campos.

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys
chmod +x consulta.sh

./consulta.sh ruc 20131312955
./consulta.sh dni 45871236
./consulta.sh tipo-cambio
./consulta.sh ubigeo 150101
./consulta.sh empresas "superintendencia aduanas"
./consulta.sh anexos 20131312955
./consulta.sh representantes 20131312955
./consulta.sh trabajadores 20131312955
```

El script devuelve código de salida 0 cuando la API responde 200 y 1 en cualquier otro caso, así puedes encadenarlo en otros scripts.

## La petición, sin script

```bash
curl -s https://api.endpoint.pe/v1/ruc/20131312955 \
  -H "Authorization: Bearer $ENDPOINT_API_KEY"
```

Con `jq` puedes quedarte con lo que necesitas:

```bash
curl -s https://api.endpoint.pe/v1/ruc/20131312955 \
  -H "Authorization: Bearer $ENDPOINT_API_KEY" | jq -r '.data.razon_social, .data.estado'
```

Para la búsqueda por razón social, `--get` y `--data-urlencode` se encargan de codificar el texto:

```bash
curl -s --get https://api.endpoint.pe/v1/empresas --data-urlencode "q=superintendencia aduanas" \
  -H "Authorization: Bearer $ENDPOINT_API_KEY"
```

Las cabeceras `X-Credits-Charged` y `X-Credits-Remaining` llegan en cada respuesta; míralas con `curl -i`.
