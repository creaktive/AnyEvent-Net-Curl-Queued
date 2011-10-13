#!/usr/bin/env perl

package ApacheCrawl;
use common::sense;

use HTML::LinkExtor;
use Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

after init => sub {
    my ($self) = @_;

    $self->setopt(
        followlocation  => 1,
        #verbose         => 1,
    );
};

after finish => sub {
    my ($self, $result) = @_;

    say $result . "\t" . $self->final_url;

    unless ($self->has_error) {
        my @links;

        HTML::LinkExtor->new(sub {
            my ($tag, %links) = @_;
            push @links,
                grep { $_->scheme eq 'http' and $_->host eq 'localhost' }
                values %links;
        }, $self->final_url)->parse(${$self->data});

        for my $link (@links) {
            $self->queue->prepend(sub {
                ApacheCrawl->new({ initial_url => $link });
            });
        }
    }
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;

use Data::Printer;

use AnyEvent::Net::Curl::Queued;

my $q = AnyEvent::Net::Curl::Queued->new;
$q->append(sub {
    ApacheCrawl->new({ initial_url => 'http://localhost/manual/' })
});
$q->wait;

p $q->stats;
