* endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Visual FoxPro 9.
*
* Requisitos: Visual FoxPro 9 y Windows con TLS 1.2 (Windows 8.1 / Server 2012 R2 o superior;
* en Windows 7 instala la actualización KB3140245 y activa TLS 1.2 en el registro).
*
* Uso desde la ventana de comandos:
*   SET PROCEDURE TO consulta ADDITIVE
*   ? ConsultarRuc("20131312955")
*   ? ConsultarDni("45871236")
*   ? TipoCambio()
*   ? ConsultarUbigeo("150101")
*   ? BuscarEmpresas("superintendencia aduanas")
*   ? ConsultarAnexos("20131312955")
*   ? ConsultarRepresentantes("20131312955")
*   ? ConsultarTrabajadores("20131312955")
*
* o como programa:  DO consulta WITH "ruc", "20131312955"
*
* Cada función devuelve el JSON completo (texto). Usa CampoJson() para leer un campo de
* primer nivel, o la biblioteca nfJson (VFPX) para convertirlo en objetos.
*
* La API key se lee de la variable de entorno ENDPOINT_API_KEY. Si prefieres, asígnala en
* la constante API_KEY_LOCAL (no compartas el archivo con la clave dentro).
*
* Documentación: https://endpoint.pe/docs

#DEFINE BASE_URL "https://api.endpoint.pe/v1"
#DEFINE API_KEY_LOCAL ""
#DEFINE TIMEOUT_MS 15000

LPARAMETERS tcComando, tcDato
LOCAL lcJson

IF VARTYPE(tcComando) <> "C" OR EMPTY(tcComando)
    ? "Uso: DO consulta WITH 'ruc', '20131312955'"
    ? "Comandos: ruc, dni, tipo-cambio, ubigeo, empresas, anexos, representantes, trabajadores"
    RETURN ""
ENDIF
IF VARTYPE(tcDato) <> "C"
    tcDato = ""
ENDIF

DO CASE
    CASE LOWER(tcComando) == "ruc"
        lcJson = ConsultarRuc(tcDato)
    CASE LOWER(tcComando) == "dni"
        lcJson = ConsultarDni(tcDato)
    CASE LOWER(tcComando) == "tipo-cambio"
        lcJson = TipoCambio()
    CASE LOWER(tcComando) == "ubigeo"
        lcJson = ConsultarUbigeo(tcDato)
    CASE LOWER(tcComando) == "empresas"
        lcJson = BuscarEmpresas(tcDato)
    CASE LOWER(tcComando) == "anexos"
        lcJson = ConsultarAnexos(tcDato)
    CASE LOWER(tcComando) == "representantes"
        lcJson = ConsultarRepresentantes(tcDato)
    CASE LOWER(tcComando) == "trabajadores"
        lcJson = ConsultarTrabajadores(tcDato)
    OTHERWISE
        ? "Comando desconocido: " + tcComando
        RETURN ""
ENDCASE
? lcJson
RETURN lcJson

*-- Empresas (SUNAT) --------------------------------------------------------

* Ficha del contribuyente: razón social, estado, condición, domicilio fiscal, padrones.
FUNCTION ConsultarRuc(tcRuc)
    RETURN EndpointGet("/ruc/" + SoloDigitos(tcRuc))
ENDFUNC

* Establecimientos anexos (sucursales, depósitos, oficinas) de un RUC.
FUNCTION ConsultarAnexos(tcRuc)
    RETURN EndpointGet("/ruc/" + SoloDigitos(tcRuc) + "/anexos")
ENDFUNC

* Representantes legales con documento, cargo y fecha de nombramiento.
FUNCTION ConsultarRepresentantes(tcRuc)
    RETURN EndpointGet("/ruc/" + SoloDigitos(tcRuc) + "/representantes")
ENDFUNC

* Trabajadores, pensionistas y prestadores de servicio declarados por periodo.
FUNCTION ConsultarTrabajadores(tcRuc)
    RETURN EndpointGet("/ruc/" + SoloDigitos(tcRuc) + "/trabajadores")
ENDFUNC

* Busca el RUC de una empresa por su razón social (hasta 20 coincidencias).
FUNCTION BuscarEmpresas(tcTexto)
    RETURN EndpointGet("/empresas?q=" + UrlEncode(ALLTRIM(tcTexto)))
ENDFUNC

*-- Identidad (RENIEC) ------------------------------------------------------

* Nombres y apellidos del titular, dígito verificador y RUC de persona natural.
FUNCTION ConsultarDni(tcDni)
    RETURN EndpointGet("/dni/" + PADL(SoloDigitos(tcDni), 8, "0"))
ENDFUNC

*-- Finanzas y ubicación ----------------------------------------------------

* Tipo de cambio compra y venta del dólar más reciente publicado por SUNAT.
FUNCTION TipoCambio()
    RETURN EndpointGet("/tipo-cambio")
ENDFUNC

* Departamento, provincia y distrito de un código de ubigeo de 6 dígitos.
FUNCTION ConsultarUbigeo(tcCodigo)
    RETURN EndpointGet("/ubigeo/" + PADL(SoloDigitos(tcCodigo), 6, "0"))
ENDFUNC

*-- Petición HTTP -----------------------------------------------------------

* GET a la ruta indicada. Devuelve el JSON completo. Si la API responde un error,
* muestra el código HTTP y el mensaje, y devuelve igualmente el JSON (success = false).
FUNCTION EndpointGet(tcRuta)
    LOCAL loHttp, lcApiKey, lnStatus, lcCuerpo, lcError

    lcApiKey = GETENV("ENDPOINT_API_KEY")
    IF EMPTY(lcApiKey)
        lcApiKey = API_KEY_LOCAL
    ENDIF
    IF EMPTY(lcApiKey)
        MESSAGEBOX("Falta la API key: define la variable de entorno ENDPOINT_API_KEY.", 48, "endpoint.pe")
        RETURN ""
    ENDIF

    lcError = ""
    TRY
        loHttp = CREATEOBJECT("MSXML2.ServerXMLHTTP.6.0")
        loHttp.SetTimeouts(10000, 10000, TIMEOUT_MS, TIMEOUT_MS)
        loHttp.Open("GET", BASE_URL + tcRuta, .F.)
        loHttp.SetRequestHeader("Authorization", "Bearer " + lcApiKey)
        loHttp.SetRequestHeader("Accept", "application/json")
        loHttp.SetRequestHeader("User-Agent", "endpoint-pe-ejemplos/visual-foxpro")
        loHttp.Send()
        lnStatus = loHttp.Status
        lcCuerpo = loHttp.ResponseText
    CATCH TO loEx
        lcError = loEx.Message
    ENDTRY

    IF !EMPTY(lcError)
        ? "No se pudo conectar con la API: " + lcError
        RETURN ""
    ENDIF
    IF lnStatus <> 200
        ? "Error HTTP " + TRANSFORM(lnStatus) + " (" + CampoJson(lcCuerpo, "error") + "): " + CampoJson(lcCuerpo, "message")
    ENDIF
    RETURN lcCuerpo
ENDFUNC

*-- Utilidades --------------------------------------------------------------

* Valor de un campo de primer nivel del JSON: texto sin comillas o el literal
* (número, true, false). Devuelve "" si no existe o es null. Para estructuras
* completas usa nfJson.
FUNCTION CampoJson(tcJson, tcCampo)
    LOCAL lnPos, lcResto, lnFin, lcValor, lnI, lcChar
    lnPos = AT('"' + tcCampo + '"', tcJson)
    IF lnPos = 0
        RETURN ""
    ENDIF
    lcResto = SUBSTR(tcJson, lnPos + LEN(tcCampo) + 2)
    lcResto = LTRIM(SUBSTR(lcResto, AT(":", lcResto) + 1))
    IF LEFT(lcResto, 1) == '"'
        lcValor = ""
        lnI = 2
        DO WHILE lnI <= LEN(lcResto)
            lcChar = SUBSTR(lcResto, lnI, 1)
            IF lcChar == "\"
                lcValor = lcValor + SUBSTR(lcResto, lnI + 1, 1)
                lnI = lnI + 2
                LOOP
            ENDIF
            IF lcChar == '"'
                EXIT
            ENDIF
            lcValor = lcValor + lcChar
            lnI = lnI + 1
        ENDDO
        RETURN lcValor
    ENDIF
    lnFin = MIN(AT(",", lcResto + ","), AT("}", lcResto + "}"), AT("]", lcResto + "]"))
    lcValor = ALLTRIM(LEFT(lcResto, lnFin - 1))
    RETURN IIF(lcValor == "null", "", lcValor)
ENDFUNC

* Deja solo los dígitos (quita espacios y guiones que suelen venir de formularios).
FUNCTION SoloDigitos(tcTexto)
    RETURN CHRTRAN(ALLTRIM(TRANSFORM(tcTexto)), CHRTRAN(ALLTRIM(TRANSFORM(tcTexto)), "0123456789", ""), "")
ENDFUNC

* Codifica un texto para usarlo en la query string (UTF-8 y porcentajes).
FUNCTION UrlEncode(tcTexto)
    LOCAL lcUtf8, lcSalida, lnI, lcChar
    lcUtf8 = STRCONV(STRCONV(tcTexto, 1), 9)
    lcSalida = ""
    FOR lnI = 1 TO LEN(lcUtf8)
        lcChar = SUBSTR(lcUtf8, lnI, 1)
        IF ISALPHA(lcChar) AND ASC(lcChar) < 128 OR ISDIGIT(lcChar) OR INLIST(lcChar, "-", "_", ".", "~")
            lcSalida = lcSalida + lcChar
        ELSE
            lcSalida = lcSalida + "%" + RIGHT(TRANSFORM(ASC(lcChar), "@0"), 2)
        ENDIF
    ENDFOR
    RETURN lcSalida
ENDFUNC
