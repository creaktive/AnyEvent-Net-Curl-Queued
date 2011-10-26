#!perl
use common::sense;

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued');
use_ok('AnyEvent::Net::Curl::Queued::Easy');
use_ok('AnyEvent::Net::Curl::Queued::Stats');
use_ok('Test::HTTP::Server');

my $server = Test::HTTP::Server->new;
isa_ok($server, 'Test::HTTP::Server');

my $q = new AnyEvent::Net::Curl::Queued;
isa_ok($q, qw(Net::Curl::Easy AnyEvent::Net::Curl::Queued));

can_ok($q, qw(
    add
    append
    completed
    count
    cv
    dequeue
    empty
    max
    multi
    prepend
    queue
    queue_push
    queue_unshift
    share
    start
    stats
    timeout
    wait
));

ok($q->max      == 4, 'default max()');
ok($q->timeout  == 60.0, 'default timeout()');

isa_ok($q->share, 'Net::Curl::Share');
isa_ok($q->stats, 'AnyEvent::Net::Curl::Queued::Stats');

$q->append(
    sub {
        AnyEvent::Net::Curl::Queued::Easy->new({
            initial_url => $server->uri . 'echo/head',
        })
    }
);

$q->wait;

ok($q->completed == 1, 'single GET');

done_testing(12);
