#!/usr/bin/env perl
use common::sense;

use AnyEvent;
use AnyEvent::Util;
use Benchmark qw(cmpthese);
use File::Slurp;
use File::Temp;
use List::Util qw(shuffle);
use POSIX;

use AnyEvent::Curl::Multi;
use AnyEvent::HTTP;
use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;
use HTTP::Lite;
use HTTP::Tiny;
use LWP::Curl;
use LWP::UserAgent;
use WWW::Mechanize;

my $parallel = $AnyEvent::Util::MAX_FORKS;
my @urls = read_file('queue', 'chomp' => 1);
my $num = scalar @urls;
for (my $i = 0; $i < $num; $i++) {
    push @urls, $urls[$i] . "?$_" for 1 .. 5;
}
@urls = shuffle @urls;
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
        my $cv = AE::cv;
        for my $list (@wget_queue) {
            $cv->begin;
            fork_call {
                system qw(wget -q -O /dev/null -i), $list->filename;
            } sub {
                $cv->end;
            }
        }
        $cv->wait;
    },
    '02-curl' => sub {
        my $cv = AE::cv;
        for my $list (@curl_queue) {
            $cv->begin;
            fork_call {
                system qw(curl -s -K), $list->filename;
            } sub {
                $cv->end;
            }
        }
        $cv->wait;
    },

    # non-async modules
    '10-HTTP::Lite' => sub {
        my $cv = AE::cv;
        my $ua = HTTP::Lite->new;
        for my $queue (@queue) {
            $cv->begin;
            fork_call {
                for my $url (@{$queue}) {
                    $ua->request($url);
                }
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },
    '11-HTTP::Tiny' => sub {
        my $cv = AE::cv;
        my $ua = HTTP::Tiny->new;
        for my $queue (@queue) {
            $cv->begin;
            fork_call {
                for my $url (@{$queue}) {
                    $ua->get($url);
                }
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },
    '12-LWP::UserAgent' => sub {
        my $cv = AE::cv;
        my $ua = LWP::UserAgent->new;
        for my $queue (@queue) {
            $cv->begin;
            fork_call {
                for my $url (@{$queue}) {
                    $ua->get($url);
                }
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },
    '13-WWW::Mechanize' => sub {
        my $cv = AE::cv;
        my $ua = WWW::Mechanize->new;
        for my $queue (@queue) {
            $cv->begin;
            fork_call {
                for my $url (@{$queue}) {
                    $ua->get($url);
                }
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },
    '14-LWP::Curl' => sub {
        my $cv = AE::cv;
        my $ua = LWP::Curl->new;
        for my $queue (@queue) {
            $cv->begin;
            fork_call {
                for my $url (@{$queue}) {
                    $ua->get($url);
                }
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },

    # async modules
    '20-AnyEvent::HTTP' => sub {
        my $cv = AE::cv;
        my $i = 0;

        my $get;
        $get = sub {
            $cv->begin;
            http_get $urls[$i++], sub {
                $get->() if $i <= $#urls;
                $cv->end;
            };
        };

        for (1 .. $parallel) {
            $get->();
        }
        $cv->wait;
    },
    '21-AnyEvent::Net::Curl::Queued' => sub {
        my $q = AnyEvent::Net::Curl::Queued->new({ max => $parallel });
        for my $url (@urls) {
            $q->append(sub { AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => $url }) });
        }
        $q->wait;
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
