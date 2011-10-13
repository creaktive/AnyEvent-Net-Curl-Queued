#!/usr/bin/env perl

package MyDownloader;
use common::sense;

use Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

after init => sub {
    my ($self) = @_;

    $self->setopt(
        autoreferer         => 1,
        encoding            => '',
        filetime            => 1,
        followlocation      => 1,
        maxredirs           => 5,
        unrestricted_auth   => 1,
        useragent           => 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)',
        verbose             => 1,
    );
};

after finish => sub {
    my ($self, $result) = @_;

    if ($self->has_error) {
        say "ERROR: $result";
    } else {
        printf "%s finished downloading %s: %d bytes\n", $self->unique, $self->final_url, length ${$self->data};
    }
};

around has_error => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->$orig(@_);
    return 1 if $self->getinfo('response_code') =~ m{^5[0-9]{2}$};
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;
use lib qw(lib);

use Data::Printer;

use AnyEvent::Net::Curl::Queued;

my $q = AnyEvent::Net::Curl::Queued->new({
    max     => 8,
    timeout => 30,
});

open(my $fh, '<', 'localhost.txt') or die "erro: $!";
while (my $url = <$fh>) {
    chomp $url;

    #$url =~ s/localhost/localhost:8888/;

    $q->append(sub {
        MyDownloader->new({
            initial_url => $url,
            retry       => 10,
        })
    });
}
$q->wait;

p $q->stats;
#p Net::Curl::version_info;
