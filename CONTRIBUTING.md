# Cómo contribuir

Gracias por querer mejorar estos ejemplos. Aceptamos correcciones, mejoras y lenguajes nuevos.

## Antes de empezar

- Revisa los [issues abiertos](../../issues) para no duplicar trabajo.
- Para cambios grandes (un lenguaje nuevo, reestructurar un ejemplo) abre primero un issue y cuéntanos qué tienes en mente.
- Nunca incluyas tu API key ni datos personales reales (nombres, DNI, direcciones) en el código, en los README ni en las capturas.

## Qué debe tener cada ejemplo

Todos los ejemplos siguen el mismo contrato para que cualquier persona pueda pasar de un lenguaje a otro sin sorpresas:

1. **Carpeta por lenguaje**, en minúsculas y sin espacios (`python/`, `visual_foxpro/`), con un `README.md` que indique requisitos, cómo ejecutarlo y cómo instalar dependencias si las hay.
2. **Un solo archivo principal** llamado `consulta.<ext>` o, en lenguajes que lo exigen, con el nombre de la clase (`EndpointPe.java`).
3. **La API key se lee de la variable de entorno `ENDPOINT_API_KEY`**. Nada de constantes con `<token>` para reemplazar.
4. **Cubre las ocho consultas**: `ruc`, `dni`, `tipo-cambio`, `ubigeo`, `empresas`, `anexos`, `representantes` y `trabajadores`, con la misma interfaz de línea de comandos que el resto (`<comando> [dato]`).
5. **Maneja la respuesta completa**: lee `success`, `data`, `error`, `message` y `detalles`, y muestra el código HTTP cuando falla.
6. **Timeout** en la petición y **reintentos solo ante errores de red o 5xx** (nunca ante 404 o 422).
7. **Sin dependencias** cuando el lenguaje lo permite. Si hace falta una biblioteca, usa la más extendida y documenta cómo instalarla.
8. **Probado de verdad** contra `https://api.endpoint.pe` con una cuenta gratuita.

## Flujo de trabajo

```bash
git clone https://github.com/endpointperu/api-ruc-dni-peru.git
cd api-ruc-dni-peru
git checkout -b lenguaje/nombre-del-lenguaje
# haz tus cambios
git commit -m "Agrega ejemplo en <Lenguaje>"
git push origin lenguaje/nombre-del-lenguaje
```

Abre el pull request desde GitHub. En la descripción indica con qué versión del lenguaje lo probaste y pega la salida de una consulta (sin tu API key y sin datos personales: el RUC 20131312955 de SUNAT es un buen dato de prueba).

## Lista de verificación del pull request

- [ ] El ejemplo compila o se interpreta sin avisos.
- [ ] Ejecuta las ocho consultas y muestra los errores de forma legible.
- [ ] Lee `ENDPOINT_API_KEY` del entorno.
- [ ] Tiene `README.md` con requisitos y comandos de ejecución.
- [ ] Está agregado a la tabla de lenguajes del `README.md` principal.
- [ ] No contiene claves, datos personales ni archivos generados (binarios, `node_modules`, `target`).

## Estilo

Respeta el `.editorconfig` y las convenciones habituales de cada lenguaje (PEP 8 en Python, `gofmt` en Go, `rustfmt` en Rust, PSR-12 en PHP). Comentarios y mensajes en español, con tildes.
