# Visual FoxPro 9

Consulta la API de endpoint.pe desde Visual FoxPro con `MSXML2.ServerXMLHTTP`, sin librerías adicionales. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores. Pensado para sistemas de facturación y ERP que siguen en producción con VFP.

## Requisitos

- Visual FoxPro 9 (SP2 recomendado).
- Windows con TLS 1.2: Windows 8.1 / Server 2012 R2 o superior. En Windows 7 o Server 2008 R2 instala la actualización [KB3140245](https://support.microsoft.com/kb/3140245) y activa TLS 1.2 para WinHTTP.

## Usar

Define la API key como variable de entorno del sistema (`ENDPOINT_API_KEY`) o en la constante `API_KEY_LOCAL` del archivo. Luego, desde la ventana de comandos o tu programa:

```foxpro
SET PROCEDURE TO consulta ADDITIVE

? ConsultarRuc("20131312955")
? ConsultarDni("45871236")
? TipoCambio()
? ConsultarUbigeo("150101")
? BuscarEmpresas("superintendencia aduanas")
? ConsultarAnexos("20131312955")
? ConsultarRepresentantes("20131312955")
? ConsultarTrabajadores("20131312955")
```

También funciona como programa: `DO consulta WITH "ruc", "20131312955"`.

Cada función devuelve el JSON completo como texto. Para leer un campo de primer nivel sin librerías:

```foxpro
lcJson = ConsultarRuc(ALLTRIM(cliente.ruc))
IF CampoJson(lcJson, "success") == "true"
    REPLACE cliente.razon_social WITH CampoJson(lcJson, "razon_social"), ;
            cliente.direccion    WITH CampoJson(lcJson, "direccion_completa"), ;
            cliente.estado       WITH CampoJson(lcJson, "estado")
ELSE
    * no_encontrado, validacion, sin_creditos… (CampoJson(lcJson, "error"))
    MESSAGEBOX(CampoJson(lcJson, "message"), 48, "endpoint.pe")
ENDIF

lcJson = TipoCambio()
lnVenta = VAL(CampoJson(lcJson, "venta"))
```

Para recorrer listas (anexos, representantes, periodos de trabajadores, resultados de empresas) convierte el JSON en objetos con [nfJson](https://github.com/VFPX/nfJson) de VFPX: `loDatos = nfJsonRead(lcJson)` y luego `loDatos.data.representantes[1].nombre`.

## Consejos

- Guarda el resultado de RUC y DNI en tu tabla de clientes y vuelve a consultar solo cuando el usuario lo pida: cada respuesta con resultado descuenta un crédito.
- El tipo de cambio es un valor por día: consúltalo una vez al abrir el sistema y guárdalo.
- Los textos llegan en mayúsculas y con tildes (UTF-8); `ResponseText` ya los convierte a la página de códigos de Windows, así que se guardan bien en tablas DBF con cotejamiento por defecto.
