#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use AnyEvent;
use AnyEvent::Curl::Multi;
use File::Slurp;
use HTTP::Request::Common qw(GET);

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

my $multi = AnyEvent::Curl::Multi->new;
$multi->max_concurrency($parallel);
$multi->reg_cb(
    response => sub {
        my ($client, $request, $response, $stats) = @_;
    }
);
$multi->reg_cb(
    error => sub {
        my ($client, $request, $errmsg, $stats) = @_;
    }
);
my @multi = map { $multi->request(GET($_)) } @urls;
$_->cv->recv for @multi;
