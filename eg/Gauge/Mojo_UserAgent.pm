package Gauge::Mojo_UserAgent;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
with qw(Gauge::Role);

use Mojo::IOLoop;
use Mojo::UserAgent;

has loop => (is => 'ro', isa => 'Mojo::IOLoop', default => sub { Mojo::IOLoop->singleton });

sub run {
    my ($self) = @_;

    # stolen from https://metacpan.org/module/Mojolicious::Guides::Cookbook#Non-blocking

    # User agent
    my $ua = Mojo::UserAgent->new;
    my @queue = @{$self->queue};

    # Crawler
    my $active = 0;
    my $crawl; $crawl = sub {
        my $id = shift;

        # Fetch non-blocking just by adding a callback
        if (my $url = shift @queue) {
            $ua->get(
                $url => sub {
                    $self->loop->stop unless --$active;

                    # Next
                    $crawl->($id);
                }
            );
            ++$active;
        }

        return;
    };

    # Start a bunch of parallel crawlers sharing the same user agent
    $crawl->($_) for 1 .. $self->parallel;

    # Start event loop
    $self->loop->start unless $self->loop->is_running;

    return;
}

1;
