#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use File::Slurp;
use HTTP::Tiny;
use Parallel::ForkManager;

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

my @queue;
for my $i (0 .. $#urls) {
    my $j = $i % $parallel;
    my $url = $urls[$i];
    push @{$queue[$j]}, $url;
}

my $http_tiny = HTTP::Tiny->new;
my $pm = Parallel::ForkManager->new($parallel);
for my $queue (@queue) {
    my $pid = $pm->start and next;
    for my $url (@{$queue}) {
        $http_tiny->get($url);
    }
    $pm->finish;
}
$pm->wait_all_children;
