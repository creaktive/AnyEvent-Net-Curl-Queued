#!perl
package MyDownloader;
use strict;
use utf8;
use warnings qw(all);

use Data::Dumper;
use Mouse;
use Test::More;
use Time::HiRes qw(time);

extends 'AnyEvent::Net::Curl::Queued::Easy';

has started => (is => 'rw', isa => 'Num', default => sub { time });
has '+use_stats' => (default => 1);

around finish => sub {
    my ($class, $self, $result) = @_;
    like(
        q...$result,
        qr{\btimed?out\b}ix,
        sprintf('%s after %0.3fs [%s]', $self->final_url, time - $self->started, scalar localtime),
    );

    diag Dumper $self->stats
        unless 0 + $result;
};

no Mouse;
__PACKAGE__->meta->make_immutable;

1;

use strict;
use utf8;
use warnings qw(all);

use Test::More;

use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;
use Config;
use Test::HTTP::AnyEvent::Server;

my $server = Test::HTTP::AnyEvent::Server->new;
my $q = AnyEvent::Net::Curl::Queued->new(
    timeout         => 5,   # allow watchdog to manifest itself
);

$q->append(sub {
    MyDownloader->new(
        initial_url => $server->uri . 'delay/20',   # 3x timeout
        retry       => 3,
    )
});

$q->append(sub {
    AnyEvent::Net::Curl::Queued::Easy->new(
        initial_url => $server->uri . 'delay/1',
        on_finish   => sub {
            my ($self, $result) = @_;
            is(0 + $result, 0, 'got CURLE_OK');
            chomp(my $body = ${$self->data});
            like(${$self->data}, qr{^issued\s+}i, qq(got data: "$body"));
        },
        retry       => 3,
    )
});

my @weird = qw(
    amd64-freebsd-thread-multi
    i86pc-solaris-64int
);

TODO: {
    local $TODO = "test known to occasionally fail under $Config{archname}"
        if grep { $_ eq $Config{archname} } @weird;

    $q->wait;

    is(
        $q->completed,
        3 + 1,
        qq(retries detected [@{[ scalar localtime ]}]),
    );
}

done_testing 6;
