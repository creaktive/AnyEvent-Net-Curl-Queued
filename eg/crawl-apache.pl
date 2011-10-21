#!/usr/bin/env perl

package CrawlApache;
use common::sense;

use HTML::LinkExtor;
use Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

after finish => sub {
    my ($self, $result) = @_;

    say $result . "\t" . $self->final_url;

    if (
        not $self->has_error
        and $self->getinfo('content_type') =~ m{^text/html}
    ) {
        my @links;

        HTML::LinkExtor->new(sub {
            my ($tag, %links) = @_;
            push @links,
                grep { $_->scheme eq 'http' and $_->host eq 'localhost' }
                values %links;
        }, $self->final_url)->parse(${$self->data});

        for my $link (@links) {
            $self->queue->prepend(sub {
                CrawlApache->new({ initial_url => $link });
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
    CrawlApache->new({ initial_url => 'http://localhost/manual/', use_stats => 1 })
});
$q->wait;

p $q->stats;
