# Rust

Cliente mínimo de la API de endpoint.pe con [`ureq`](https://crates.io/crates/ureq) (HTTP síncrono, sin runtime asíncrono) y `serde_json`. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Rust 1.70 o superior (`cargo`).

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

cargo run -- ruc 20131312955
cargo run -- dni 45871236
cargo run -- tipo-cambio
cargo run -- ubigeo 150101
cargo run -- empresas "superintendencia aduanas"
cargo run -- anexos 20131312955
cargo run -- representantes 20131312955
cargo run -- trabajadores 20131312955
```

Para un binario optimizado: `cargo build --release && ./target/release/consulta ruc 20131312955`.

## Usar en tu proyecto

Copia `src/main.rs` como módulo (`endpointpe.rs`) y quita la función `main`. Los métodos devuelven el objeto `data` como `serde_json::Value`; si prefieres structs, deriva `serde::Deserialize` y usa `serde_json::from_value`.

```rust
let mut api = EndpointPe::nuevo()?; // lee ENDPOINT_API_KEY; o EndpointPe::con_clave("ep_live_...")

match api.ruc("20131312955") {
    Ok(ficha) => println!("{} · {} · {}", ficha["razon_social"], ficha["estado"], ficha["condicion"]),
    Err(e) if e.error == "no_encontrado" => println!("RUC no inscrito"),
    Err(e) => return Err(e.into()),
}

let tc = api.tipo_cambio()?;
println!("{} compra {} venta {}", tc["fecha"], tc["compra"], tc["venta"]);
println!("Créditos disponibles: {:?}", api.creditos_disponibles);
```

Los errores (404, 422, 402…) llegan como `EndpointError` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

Si tu proyecto ya usa `reqwest` con Tokio, la petición equivalente es `client.get(url).bearer_auth(key).timeout(Duration::from_secs(15)).send().await?.json::<Value>().await?`.
