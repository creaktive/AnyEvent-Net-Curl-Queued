package Gauge::WWW_Mechanize;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
with qw(Gauge::Role);

use WWW::Mechanize;

sub run {
    my ($self) = @_;

    my $mech = WWW::Mechanize->new;
    $self->run_forked(sub {
        $mech->get(shift);
    });

    return;
}

1;
