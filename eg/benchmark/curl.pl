#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use File::Slurp;
use File::Temp;
use Parallel::ForkManager;

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

my @curl_queue;
for my $i (1 .. $parallel) {
    push @curl_queue, File::Temp->new;
}

for my $i (0 .. $#urls) {
    my $j = $i % $parallel;
    my $url = $urls[$i];
    $curl_queue[$j]->say("url = \"$url\"");
    $curl_queue[$j]->say("output = \"/dev/null\"");
}

my $pm = Parallel::ForkManager->new($parallel);
for my $list (@curl_queue) {
    my $pid = $pm->start and next;
    system qw(curl -s -K), $list->filename;
    $pm->finish;
}
$pm->wait_all_children;
