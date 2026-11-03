#!/usr/bin/env perl
# endpoint.pe · Consulta RUC, DNI, tipo de cambio y ubigeo del Perú desde Perl.
#
# Solo módulos del núcleo (HTTP::Tiny y JSON::PP). Para HTTPS hace falta IO::Socket::SSL,
# que casi toda distribución trae instalado (si no: cpan IO::Socket::SSL).
#
# Uso desde la terminal:
#   export ENDPOINT_API_KEY=ep_live_...
#   perl consulta.pl ruc 20131312955
#   perl consulta.pl dni 45871236
#   perl consulta.pl tipo-cambio
#   perl consulta.pl ubigeo 150101
#   perl consulta.pl empresas "superintendencia aduanas"
#   perl consulta.pl anexos 20131312955
#   perl consulta.pl representantes 20131312955
#   perl consulta.pl trabajadores 20131312955
#
# Uso desde tu código:
#   require './consulta.pl';
#   my $api = EndpointPe->new;                    # lee ENDPOINT_API_KEY del entorno
#   my $ficha = $api->ruc('20131312955');         # hashref con el objeto `data`
#   print "$ficha->{razon_social} $ficha->{estado} ", $api->creditos_disponibles, "\n";
#
# Requisitos: Perl 5.14 o superior.
# Documentación: https://endpoint.pe/docs

use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));

use Encode qw(decode encode);
use HTTP::Tiny;
use JSON::PP;

# La API respondió con success=false. error() es el código estable para comparar en tu
# código (no_encontrado, validacion, sin_creditos…); mensaje() es texto en español.
package EndpointPe::Error {
    use overload '""' => sub { my $s = shift; "HTTP $s->{status} · $s->{error}: $s->{mensaje}" }, fallback => 1;

    sub new {
        my ( $class, %campos ) = @_;
        return bless { detalles => {}, %campos }, $class;
    }
    sub status   { $_[0]{status} }
    sub error    { $_[0]{error} }
    sub mensaje  { $_[0]{mensaje} }
    sub detalles { $_[0]{detalles} }
}

# Cliente de la API v1. Cada método devuelve el objeto `data` de la respuesta como hashref.
package EndpointPe {
    my $BASE_URL   = $ENV{ENDPOINT_BASE_URL} || 'https://api.endpoint.pe/v1';
    my $TIMEOUT    = 15;
    my $REINTENTOS = 3;    # solo ante errores de red o 5xx; nunca ante 404 o 422

    sub new {
        my ( $class, %args ) = @_;
        my $api_key = $args{api_key} // $ENV{ENDPOINT_API_KEY} // '';
        die "Falta la API key: define ENDPOINT_API_KEY o pásala a new(api_key => ...).\n" unless length $api_key;
        ( my $base = $args{base_url} // $BASE_URL ) =~ s{/+$}{};
        return bless {
            base_url => $base,
            http     => HTTP::Tiny->new(
                timeout         => $TIMEOUT,
                verify_SSL      => 1,
                agent           => 'endpoint-pe-ejemplos/perl',
                default_headers => { Authorization => "Bearer $api_key", Accept => 'application/json' },
            ),
            creditos_disponibles => undef,
        }, $class;
    }

    # Créditos que quedan (suscripción + prepago). Se actualiza con cada respuesta.
    sub creditos_disponibles { $_[0]{creditos_disponibles} }

    # Empresas (SUNAT)
    sub ruc            { my ( $s, $ruc ) = @_;   $s->_get( '/ruc/' . _codificar($ruc) ) }                     # ficha del contribuyente
    sub anexos         { my ( $s, $ruc ) = @_;   $s->_get( '/ruc/' . _codificar($ruc) . '/anexos' ) }         # establecimientos anexos
    sub representantes { my ( $s, $ruc ) = @_;   $s->_get( '/ruc/' . _codificar($ruc) . '/representantes' ) } # representantes legales
    sub trabajadores   { my ( $s, $ruc ) = @_;   $s->_get( '/ruc/' . _codificar($ruc) . '/trabajadores' ) }   # trabajadores por periodo
    sub empresas       { my ( $s, $texto ) = @_; $s->_get( '/empresas?q=' . _codificar($texto) ) }            # RUC por razón social
    # Identidad (RENIEC)
    sub dni            { my ( $s, $dni ) = @_;   $s->_get( '/dni/' . _codificar($dni) ) }                     # nombres y apellidos
    # Finanzas y ubicación
    sub tipo_cambio    { my ($s) = @_;           $s->_get('/tipo-cambio') }                                   # compra y venta de hoy
    sub ubigeo         { my ( $s, $codigo ) = @_; $s->_get( '/ubigeo/' . _codificar($codigo) ) }              # departamento, provincia, distrito

    sub _get {
        my ( $self, $ruta ) = @_;
        for my $intento ( 1 .. $REINTENTOS ) {
            my $res = $self->{http}->get( $self->{base_url} . $ruta );

            if ( ( $res->{status} == 599 || $res->{status} >= 500 ) && $intento < $REINTENTOS ) {
                sleep 2**( $intento - 1 );
                next;
            }
            if ( $res->{status} == 599 ) {    # HTTP::Tiny usa 599 para errores de conexión
                die EndpointPe::Error->new( status => 0, error => 'red', mensaje => "No se pudo conectar con la API: $res->{content}" );
            }
            if ( defined $res->{headers}{'x-credits-remaining'} ) {
                $self->{creditos_disponibles} = 0 + $res->{headers}{'x-credits-remaining'};
            }
            my $cuerpo = eval { JSON::PP->new->utf8->decode( $res->{content} ) } || {};
            unless ( $res->{status} == 200 && $cuerpo->{success} && ref $cuerpo->{data} eq 'HASH' ) {
                die EndpointPe::Error->new(
                    status   => $res->{status},
                    error    => $cuerpo->{error} // 'error',
                    mensaje  => $cuerpo->{message} // "Respuesta inesperada (HTTP $res->{status})",
                    detalles => $cuerpo->{detalles} // {},
                );
            }
            return $cuerpo->{data};
        }
    }

    sub _codificar {
        my $bytes = Encode::encode( 'UTF-8', $_[0] // '' );
        $bytes =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord $1)/ge;
        return $bytes;
    }
}

package main;

# --- Uso desde la terminal ---

my $USO = <<'TXT';
Uso: perl consulta.pl <comando> [dato]

  ruc <ruc>              Ficha del contribuyente (SUNAT)
  dni <dni>              Nombres y apellidos del titular (RENIEC)
  tipo-cambio            Tipo de cambio del dólar de hoy (SUNAT)
  ubigeo <codigo>        Departamento, provincia y distrito de un ubigeo
  empresas <texto>       Buscar el RUC de una empresa por su razón social
  anexos <ruc>           Establecimientos anexos de un RUC
  representantes <ruc>   Representantes legales de un RUC
  trabajadores <ruc>     Trabajadores declarados por periodo

La API key se lee de la variable de entorno ENDPOINT_API_KEY.
Crea la tuya gratis en https://app.endpoint.pe/panel/api-keys
TXT

sub main {
    my @argv = map { decode( 'UTF-8', $_ ) } @_;
    my ( $comando, $dato ) = ( $argv[0] // '', $argv[1] // '' );
    if ( $comando eq '' || $comando =~ /^(-h|--help|ayuda)$/ ) {
        print $USO;
        return 0;
    }

    my $api = eval { EndpointPe->new };
    if ( !$api ) {
        print STDERR $@;
        return 2;
    }

    my %comandos = (
        'ruc'            => [ sub { $api->ruc(@_) },            1 ],
        'dni'            => [ sub { $api->dni(@_) },            1 ],
        'tipo-cambio'    => [ sub { $api->tipo_cambio },        0 ],
        'ubigeo'         => [ sub { $api->ubigeo(@_) },         1 ],
        'empresas'       => [ sub { $api->empresas(@_) },       1 ],
        'anexos'         => [ sub { $api->anexos(@_) },         1 ],
        'representantes' => [ sub { $api->representantes(@_) }, 1 ],
        'trabajadores'   => [ sub { $api->trabajadores(@_) },   1 ],
    );
    if ( !$comandos{$comando} ) {
        print STDERR "Comando desconocido: $comando\n\n$USO";
        return 2;
    }
    my ( $funcion, $necesita_dato ) = @{ $comandos{$comando} };
    if ( $necesita_dato && $dato eq '' ) {
        print STDERR "El comando '$comando' necesita un dato.\n";
        return 2;
    }

    my $resultado = eval { $funcion->($dato) };
    if ( my $e = $@ ) {
        if ( ref $e && $e->isa('EndpointPe::Error') ) {
            print STDERR 'Error HTTP ', $e->status, ' (', $e->error, '): ', $e->mensaje, "\n";
            print STDERR "  $_: $e->{detalles}{$_}\n" for sort keys %{ $e->detalles };
            return 1;
        }
        die $e;
    }
    print JSON::PP->new->pretty->canonical->encode($resultado);
    print STDERR 'Créditos disponibles: ', $api->creditos_disponibles, "\n" if defined $api->creditos_disponibles;
    return 0;
}

exit main(@ARGV) unless caller;    # no se ejecuta al hacer require
1;
