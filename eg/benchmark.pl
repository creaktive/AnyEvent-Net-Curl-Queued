#!/usr/bin/env perl
use common::sense;

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
my $num = scalar @urls;
for (my $i = 0; $i < $num; $i++) {
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

for (my $i = 0; $i < $parallel; $i++) {
    push @curl_queue, File::Temp->new;
    push @wget_queue, File::Temp->new;
}

for (my $i = 0; $i <= $#urls; $i++) {
    my $j = $i % $parallel;
    my $url = $urls[$i];

    push @{$queue[$j]}, $url;
    $curl_queue[$j]->say("url = \"$url\"");
    $curl_queue[$j]->say("output = \"/dev/null\"");
    $wget_queue[$j]->say($url);
    $lftp_queue->say("queue get \"$url\" -o \"/dev/null\"");
}

say $lftp_queue "wait all";

cmpthese(10 => {
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
    '10-HTTP::Lite' => sub {
        my $ua = HTTP::Lite->new;
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $ua->request($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '11-HTTP::Tiny' => sub {
        my $ua = HTTP::Tiny->new;
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $ua->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '12-LWP::UserAgent' => sub {
        my $ua = LWP::UserAgent->new;
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $ua->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '13-WWW::Mechanize' => sub {
        my $ua = WWW::Mechanize->new;
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $ua->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },
    '14-LWP::Curl' => sub {
        my $ua = LWP::Curl->new;
        my $pm = Parallel::ForkManager->new($parallel);
        for my $queue (@queue) {
            my $pid = $pm->start and next;
            for my $url (@{$queue}) {
                $ua->get($url);
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    },

    # async modules
    '20-Parallel::Downloader' => sub {
        my $downloader = Parallel::Downloader->new(
            requests        => [ map { GET($_) } @urls ],
            workers         => $parallel,
            conns_per_host  => $parallel,
        );
        $downloader->run;
    },
    '21-AnyEvent::Net::Curl::Queued' => sub {
        my $yada = AnyEvent::Net::Curl::Queued->new({ max => $parallel });
        for my $url (@urls) {
            $yada->append(sub {
                AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => $url })
            });
        }
        $yada->wait;
    },
    '22-AnyEvent::Curl::Multi' => sub {
        my $cv = AE::cv;
        my $client = AnyEvent::Curl::Multi->new;
        $client->max_concurrency($parallel);
        $client->reg_cb(
            response => sub {
                my ($client, $request, $response, $stats) = @_;
                $cv->end;
            }
        );
        $client->reg_cb(
            error => sub {
                my ($client, $request, $errmsg, $stats) = @_;
                $cv->end;
            }
        );
        for (@urls) {
            $cv->begin;
            $client->request(HTTP::Request->new(GET => $_));
        }
        $cv->wait;
    },
});
