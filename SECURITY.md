# Seguridad

## Reportar una vulnerabilidad

Si encuentras un problema de seguridad en la API de endpoint.pe, en el panel o en estos ejemplos, escríbenos a **contacto@endpoint.pe** con el asunto "Seguridad". No abras un issue público: así evitamos que alguien lo aproveche antes de corregirlo.

Respondemos en un máximo de dos días hábiles y te mantenemos al tanto hasta cerrar el caso.

## Tu API key

- La clave `ep_live_…` identifica tu cuenta y descuenta tus créditos. Trátala como una contraseña.
- Nunca la escribas en el código, en capturas de pantalla ni en issues o pull requests de este repositorio. Todos los ejemplos la leen de la variable de entorno `ENDPOINT_API_KEY`.
- Si crees que se filtró, revócala de inmediato en [API keys](https://app.endpoint.pe/panel/api-keys) y crea una nueva. En el historial del panel puedes ver qué consultas se hicieron con ella.
- Consulta desde tu servidor, no desde el navegador ni desde una app móvil: cualquiera podría leer la clave.

Más recomendaciones en la guía [Autenticación](https://endpoint.pe/docs/autenticacion) y en [Buenas prácticas](https://endpoint.pe/docs/buenas-practicas).
