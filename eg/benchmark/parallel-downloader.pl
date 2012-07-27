#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use File::Slurp;
use HTTP::Request::Common qw(GET);
use Parallel::Downloader;

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

my $parallel_downloader = Parallel::Downloader->new(
    requests        => [ map { GET($_) } @urls ],
    workers         => $parallel,
    conns_per_host  => $parallel,
);
$parallel_downloader->run;
