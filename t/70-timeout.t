#!perl
package MyDownloader;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
use Test::More;

extends 'AnyEvent::Net::Curl::Queued::Easy';

around finish => sub {
    my ($class, $self, $result) = @_;
    like(q...$result, qr{\btimed?out\b}ix, 'timeout');
};

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

use Test::More;

use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;
use Test::HTTP::AnyEvent::Server;

my $server = Test::HTTP::AnyEvent::Server->new;
my $q = AnyEvent::Net::Curl::Queued->new({
    timeout     => 2,   # allow watchdog to manifest itself
});

$q->append(sub {
    MyDownloader->new({
        initial_url => $server->uri . 'delay/3',
        retry       => 3,
    })
});

$q->append(sub {
    AnyEvent::Net::Curl::Queued::Easy->new({
        initial_url => $server->uri . 'delay/1',
        on_finish   => sub {
            my ($self, $result) = @_;
            ok($result == 0, 'got CURLE_OK');
            like(${$self->data}, qr{^issued\s+}i, 'got data: ' . ${$self->data});
        },
        retry       => 3,
    })
});

$q->wait;

ok($q->completed == 3 + 1, 'retries detected');

done_testing(6);
