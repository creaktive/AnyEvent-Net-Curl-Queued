#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use File::Slurp;
use YADA;

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

my $yada = YADA->new({ max => $parallel });
for my $url (@urls) {
    $yada->append(sub {
        YADA::Worker->new({ initial_url => $url })
    });
}
$yada->wait;
