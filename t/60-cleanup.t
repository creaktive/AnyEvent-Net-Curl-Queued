#!perl
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued');
use_ok('AnyEvent::Net::Curl::Queued::Easy');
use_ok('Test::HTTP::AnyEvent::Server');

my $server = Test::HTTP::AnyEvent::Server->new;
isa_ok($server, 'Test::HTTP::AnyEvent::Server');

my $n = 5;
for (1 .. $n) {
    my $q = new AnyEvent::Net::Curl::Queued;
    isa_ok($q, qw(AnyEvent::Net::Curl::Queued));

    $q->append(
        sub {
            AnyEvent::Net::Curl::Queued::Easy->new({
                initial_url => $server->uri . 'echo/head',
            })
        }
    );

    $q->wait;

    ok($q->completed == 1, 'single GET');
}

done_testing(4 + 2 * $n);
