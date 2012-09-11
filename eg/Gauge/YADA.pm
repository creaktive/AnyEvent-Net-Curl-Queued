package Gauge::YADA;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
with qw(Gauge::Role);

use YADA;

sub run {
    my ($self) = @_;

    my $yada = YADA->new({ max => $self->parallel });
    for my $url (@{$self->queue}) {
        $yada->append(sub {
            YADA::Worker->new({ initial_url => $url })
        });
    }
    $yada->wait;

    return;
}

1;
