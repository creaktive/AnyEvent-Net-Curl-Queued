#!perl
use strict;
use utf8;
use warnings qw(all);

use FindBin qw($Bin $Script);
use Test::More;

eval q(use Test::Memory::Cycle);
plan skip_all => q(Test::Memory::Cycle required)
    if $@;

use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;

my $q = AnyEvent::Net::Curl::Queued->new;
memory_cycle_ok($q, q(AnyEvent::Net::Curl::Queued after creation));

my $e = AnyEvent::Net::Curl::Queued::Easy->new(
    http_response => 1,
    initial_url => "file://$Bin/$Script",
    on_finish => sub {
        my ($self, $result) = @_;

        memory_cycle_ok($self->queue, q(AnyEvent::Net::Curl::Queued inside on_finish));
        memory_cycle_ok($self, q(AnyEvent::Net::Curl::Queued::Easy inside on_finish));

        ok($result == 0, 'got CURLE_OK');
        ok(!$self->has_error, "libcurl message: '$result'");
    },
);
memory_cycle_ok($e, q(AnyEvent::Net::Curl::Queued::Easy after creation));

$q->append($e);
memory_cycle_ok($q, q(AnyEvent::Net::Curl::Queued after append));
memory_cycle_ok($e, q(AnyEvent::Net::Curl::Queued::Easy after append));

$q->wait;
memory_cycle_ok($q, q(AnyEvent::Net::Curl::Queued after wait));
memory_cycle_ok($e, q(AnyEvent::Net::Curl::Queued::Easy after wait));

ok($q->completed == 1, 'single fetch');

done_testing(11);
