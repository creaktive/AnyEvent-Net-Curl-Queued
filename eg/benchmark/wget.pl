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

my @wget_queue;
for my $i (1 .. $parallel) {
    push @wget_queue, File::Temp->new;
}

for my $i (0 .. $#urls) {
    my $j = $i % $parallel;
    my $url = $urls[$i];
    $wget_queue[$j]->say($url);
}

my $pm = Parallel::ForkManager->new($parallel);
for my $list (@wget_queue) {
    my $pid = $pm->start and next;
    system qw(wget -q -O /dev/null -i), $list->filename;
    $pm->finish;
}
$pm->wait_all_children;
