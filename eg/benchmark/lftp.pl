#!/usr/bin/env perl
use feature qw(say);
use strict;
use utf8;
use warnings qw(all);

use File::Slurp;
use File::Temp;

my $parallel = $ENV{PARALLEL} // 4;
my @urls = read_file(shift @ARGV, 'chomp' => 1);

my $lftp_queue = File::Temp->new;
say $lftp_queue "set cmd:queue-parallel $parallel";
say $lftp_queue "set cmd:verbose no";
say $lftp_queue "set net:connection-limit 0";
say $lftp_queue "set xfer:clobber 1";

for my $i (0 .. $#urls) {
    my $url = $urls[$i];
    $lftp_queue->say("queue get \"$url\" -o \"/dev/null\"");
}

say $lftp_queue "wait all";

system qw(lftp -f), $lftp_queue->filename;
