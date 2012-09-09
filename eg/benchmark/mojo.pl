#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use File::Slurp;
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::UserAgent;

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

# stolen from https://metacpan.org/module/Mojolicious::Guides::Cookbook#Non-blocking

# User agent
my $ua = Mojo::UserAgent->new;

# Crawler
sub crawl {
    my $id = shift;

    # Dequeue or wait 0.1 seconds for more URLs
    return Mojo::IOLoop->timer(0.1 => sub { @urls ? crawl($id) : Mojo::IOLoop->stop })
        unless my $url = shift @urls;

    # Fetch non-blocking just by adding a callback
    $ua->get(
        $url => sub {
            # Next
            crawl($id);
        }
    );

    return;
}

# Start a bunch of parallel crawlers sharing the same user agent
crawl($_) for 1 .. $parallel;

# Start event loop
Mojo::IOLoop->start;
