#!/usr/bin/env perl

package MyDownloader;
use common::sense;

use Any::Moose;

extends 'YADA::Worker';

after init => sub {
    my ($self) = @_;

    $self->setopt(
        encoding            => '',
        verbose             => 1,
    );
};

after finish => sub {
    my ($self, $result) = @_;

    if ($self->has_error) {
        say "ERROR: $result";
    } else {
        printf "Finished downloading %s: %d bytes\n", $self->final_url, length ${$self->data};
    }
};

around has_error => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->$orig(@_);
    return 1 if $self->getinfo('response_code') =~ m{^5[0-9]{2}$};
};

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;

use Data::Printer;

use YADA;

my $q = YADA->new({
    max     => 8,
    timeout => 30,
});

open(my $fh, '<', 'queue')
    or die "can't open queue: $!";
while (my $url = <$fh>) {
    chomp $url;

    $q->append(sub {
        MyDownloader->new({
            initial_url => $url,
            retry       => 10,
            use_stats   => 1,
        })
    });
}
close $fh;
$q->wait;

p $q->stats;
