# Perl

Cliente mínimo de la API de endpoint.pe con módulos del núcleo (`HTTP::Tiny` y `JSON::PP`), sin CPAN. Cubre consulta RUC, DNI, tipo de cambio SUNAT, ubigeo, búsqueda por razón social, establecimientos anexos, representantes legales y trabajadores.

## Requisitos

- Perl 5.14 o superior.
- `IO::Socket::SSL` para HTTPS. Viene en casi todas las distribuciones (`apt install libio-socket-ssl-perl`, o `cpan IO::Socket::SSL`).

## Ejecutar

```bash
export ENDPOINT_API_KEY=ep_live_...   # tu clave, creada en https://app.endpoint.pe/panel/api-keys

perl consulta.pl ruc 20131312955
perl consulta.pl dni 45871236
perl consulta.pl tipo-cambio
perl consulta.pl ubigeo 150101
perl consulta.pl empresas "superintendencia aduanas"
perl consulta.pl anexos 20131312955
perl consulta.pl representantes 20131312955
perl consulta.pl trabajadores 20131312955
```

## Usar en tu proyecto

```perl
require './consulta.pl';

my $api = EndpointPe->new;   # lee ENDPOINT_API_KEY; también acepta EndpointPe->new(api_key => 'ep_live_...')

my $ficha = eval { $api->ruc('20131312955') };
if (my $e = $@) {
    print $e->error eq 'no_encontrado' ? "RUC no inscrito\n" : "$e\n";   # HTTP 422 · validacion: …
} else {
    print "$ficha->{razon_social} · $ficha->{estado} · $ficha->{condicion}\n";
}

my $tc = $api->tipo_cambio;
print "$tc->{fecha} compra $tc->{compra} venta $tc->{venta}\n";
print 'Créditos disponibles: ', $api->creditos_disponibles, "\n";
```

Cada método devuelve el objeto `data` como hashref y actualiza `creditos_disponibles`. Los errores (404, 422, 402…) se lanzan como objetos `EndpointPe::Error` con `status`, `error`, `mensaje` y `detalles`. Los errores de red y los 5xx se reintentan hasta tres veces con espera creciente.

Si tu proyecto ya usa `LWP::UserAgent` o `Mojo::UserAgent`, basta con la cabecera `Authorization: Bearer …` y leer `success`, `data` y `error` del JSON.
