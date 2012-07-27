#!/usr/bin/env perl
use strict;
use utf8;
use warnings qw(all);

use Benchmark qw(cmpthese :hireswallclock);
use File::Basename;

cmpthese(100 => {
    map {
        my $benchmark = $_;
        basename($benchmark, q(.pl)) => sub {
            system $^X, $benchmark, q(queue);
        }
    } glob q(benchmark/*.pl)
});
