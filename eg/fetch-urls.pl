#!/usr/bin/env perl

package MyDownloader;
use strict;
use utf8;
use warnings qw(all);

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
        print "ERROR: $result\n";
    } else {
        printf "Finished downloading %s: %d bytes\n", $self->final_url, length ${$self->data};
    }
};

around has_error => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->$orig(@_);
    return 1 if $self->getinfo('response_code') =~ m{^5[0-9]{2}$}x;
};

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use strict;
use utf8;
use warnings qw(all);

use Carp;
use Data::Printer;

use YADA;

my $q = YADA->new({
    max     => 8,
    timeout => 30,
});

open(my $fh, '<', 'queue')
    or croak "can't open queue: $!";
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
