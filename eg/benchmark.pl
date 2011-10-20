#!/usr/bin/env perl
use common::sense;

use AnyEvent;
use AnyEvent::Curl::Multi;
use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;
use AnyEvent::Util;
use Benchmark qw(cmpthese);
use File::Slurp;
use File::Temp;
use HTTP::Lite;
use HTTP::Tiny;
use LWP::UserAgent;
use List::Util qw(shuffle);
use POSIX;

my $parallel = $AnyEvent::Util::MAX_FORKS;
my @urls = read_file('queue', 'chomp' => 1);
my $num = scalar @urls;
for (my $i = 0; $i < $num; $i++) {
    push @urls, $urls[$i] . "?$_" for 1 .. 3;
}
@urls = shuffle @urls;

cmpthese(5 => {
    '00-lftp' => sub {
        my $list = File::Temp->new;
        say $list "set cmd:queue-parallel $parallel";
        say $list "set cmd:verbose no";
        say $list "set net:connection-limit 0";
        say $list "queue get \"$_\" -o \"/dev/null\""
            for @urls;
        say $list "wait all";

        system qw(lftp -f), $list->filename;
    },
    '01-wget' => sub {
        my @list;
        for (my $i = 0; $i < $parallel; $i++) {
            push @list, File::Temp->new;
        }
        for (my $i = 0; $i <= $#urls; $i++) {
            my $list = $list[$i % $parallel];
            say $list $urls[$i];
        }

        my $cv = AE::cv;
        for my $list (@list) {
            $cv->begin;
            fork_call {
                system qw(wget -q -O /dev/null -i), $list->filename;
            } sub {
                $cv->end;
            }
        }
        $cv->wait;
    },

    '10-HTTP::Lite' => sub {
        my $cv = AE::cv;
        my $ua = HTTP::Lite->new;
        for my $url (@urls) {
            $cv->begin;
            fork_call {
                $ua->request($url);
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },
    '11-HTTP::Tiny' => sub {
        my $cv = AE::cv;
        my $ua = HTTP::Tiny->new;
        for my $url (@urls) {
            $cv->begin;
            fork_call {
                $ua->get($url);
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },
    '12-LWP::UserAgent' => sub {
        my $cv = AE::cv;
        my $ua = LWP::UserAgent->new;
        for my $url (@urls) {
            $cv->begin;
            fork_call {
                $ua->get($url);
            } sub {
                $cv->end;
            };
        }
        $cv->wait;
    },

    '20-AnyEvent::Net::Curl::Queued' => sub {
        my $q = AnyEvent::Net::Curl::Queued->new({ max => $parallel });
        for my $url (@urls) {
            $q->append(sub { AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => $url }) });
        }
        $q->wait;
    },
    '21-AnyEvent::Curl::Multi' => sub {
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
