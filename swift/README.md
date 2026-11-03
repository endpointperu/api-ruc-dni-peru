# Swift

Cliente mínimo de la API de endpoint.pe con `URLSession` y `async/await`, sin paquetes. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Swift 5.7 o superior (Xcode 14+ en macOS 12+, o el toolchain de Swift en Linux).

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

swift EndpointPe.swift ruc 20131312955
swift EndpointPe.swift dni 45871236
swift EndpointPe.swift tipo-cambio
swift EndpointPe.swift ubigeo 150101
swift EndpointPe.swift empresas "superintendencia aduanas"
swift EndpointPe.swift anexos 20131312955
swift EndpointPe.swift representantes 20131312955
swift EndpointPe.swift trabajadores 20131312955
```

Para un binario: `swiftc EndpointPe.swift -o consulta && ./consulta ruc 20131312955`.

## Usar en tu proyecto

Copia la clase `EndpointPe` y `EndpointError` (todo lo que está antes de "Uso desde la terminal"). Los métodos devuelven el objeto `data` como `[String: Any]`; si prefieres `Codable`, decodifica el envoltorio `{success, message, data, meta}` con `JSONDecoder` y tus propios structs.

```swift
let api = try EndpointPe() // lee ENDPOINT_API_KEY; también acepta EndpointPe(apiKey: "ep_live_...")

do {
    let ficha = try await api.ruc("20131312955")
    print(ficha["razon_social"] ?? "", ficha["estado"] ?? "", ficha["condicion"] ?? "")
} catch let e as EndpointError where e.error == "no_encontrado" {
    print("RUC no inscrito")
}

let tc = try await api.tipoCambio()
print(tc["fecha"] ?? "", tc["compra"] ?? 0, tc["venta"] ?? 0)
```

Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

## iOS

No incluyas la API key en una app publicada: puede extraerse del binario. Haz la consulta desde tu backend (Vapor, o cualquier servidor de este repositorio) y entrega a la app solo el resultado.
