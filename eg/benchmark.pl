#!/usr/bin/env perl
use strict;
use utf8;
use warnings qw(all);

use AnyEvent;
use Benchmark qw(cmpthese :hireswallclock);
use File::Slurp;
use File::Temp;
use List::Util qw(shuffle);
use Parallel::ForkManager;

use AnyEvent::Curl::Multi;
use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;
use HTTP::Lite;
use HTTP::Request::Common qw(GET);
use HTTP::Tiny;
use LWP::Curl;
use LWP::UserAgent;
use Parallel::Downloader;
use WWW::Mechanize;

my $parallel = 4;
my @urls = read_file('queue', 'chomp' => 1);
for my $i (0 .. $#urls) {
    push @urls, $urls[$i] . "?$_" for 1 .. 5;
}
@urls = shuffle @urls;
#splice @urls, 1000;
say STDERR scalar @urls;

my (
    @queue,
    @curl_queue,
    @wget_queue,
);

my $lftp_queue = File::Temp->new;
say $lftp_queue "set cmd:queue-parallel $parallel";
say $lftp_queue "set cmd:verbose no";
say $lftp_queue "set net:connection-limit 0";
say $lftp_queue "set xfer:clobber 1";

for my $i (1 .. $parallel) {
    push @curl_queue, File::Temp->new;
    push @wget_queue, File::Temp->new;
}

for my $i (0 .. $#urls) {
    my $j = $i % $parallel;
    my $url = $urls[$i];

    push @{$queue[$j]}, $url;
    $curl_queue[$j]->say("url = \"$url\"");
    $curl_queue[$j]->say("output = \"/dev/null\"");
    $wget_queue[$j]->say($url);
    $lftp_queue->say("queue get \"$url\" -o \"/dev/null\"");
}

say $lftp_queue "wait all";

my ($http_lite, $http_tiny, $lwp, $mech, $lwp_curl, $parallel_downloader, $yada);

cmpthese(1 => {
    # external executables
    '00-lftp' => sub {
        system qw(lftp -f), $lftp_queue->filename;
    },
    '01-wget' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $list (@wget_queue) {
            my $pid = $pm->start and next;
            system qw(wget -q -O /dev/null -i), $list->filename;
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '02-curl' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $list (@curl_queue) {
            my $pid = $pm->start and next;
            system qw(curl -s -K), $list->filename;
            $pm->finish;
        }
        $pm->wait_all_children;
    },

    # non-async modules
    '10a-HTTP::Lite' => sub {
        $http_lite = HTTP::Lite->new;
    },
    '10b-HTTP::Lite' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $http_lite->request($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '11a-HTTP::Tiny' => sub {
        $http_tiny = HTTP::Tiny->new;
    },
    '11b-HTTP::Tiny' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $http_tiny->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '12a-LWP::UserAgent' => sub {
        $lwp = LWP::UserAgent->new;
    },
    '12b-LWP::UserAgent' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $lwp->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '13a-WWW::Mechanize' => sub {
        $mech = WWW::Mechanize->new;
    },
    '13b-WWW::Mechanize' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $mech->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '14a-LWP::Curl' => sub {
        $lwp_curl = LWP::Curl->new;
    },
    '14b-LWP::Curl' => sub {
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $lwp_curl->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },

    # async modules
    '20a-Parallel::Downloader' => sub {
        $parallel_downloader = Parallel::Downloader->new(
            requests        => [ map { GET($_) } @urls ],
            workers         => $parallel,
            conns_per_host  => $parallel,
        );
    },
    '20b-Parallel::Downloader' => sub {
        $parallel_downloader->run;
    },
    '21a-AnyEvent::Net::Curl::Queued' => sub {
        $yada = AnyEvent::Net::Curl::Queued->new({ max => $parallel });
        for my $url (@urls) {
            $yada->append(
                AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => $url })
            );
        }
    },
    '21b-AnyEvent::Net::Curl::Queued' => sub {
        $yada->wait;
    },
    '22-AnyEvent::Curl::Multi' => sub {
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
    },
});
