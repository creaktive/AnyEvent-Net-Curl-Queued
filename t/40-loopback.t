#!perl
package MyDownloader;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
use Net::Curl::Easy qw(/^CURLOPT_/);

extends 'AnyEvent::Net::Curl::Queued::Easy';

has cb      => (is => 'ro', isa => 'CodeRef', required => 1);
has post    => (is => 'ro', isa => 'Str', required => 1);

after init => sub {
    my ($self) = @_;

    $self->sign($self->post);
    $self->setopt(CURLOPT_POSTFIELDS, $self->post);
};

after finish => sub {
    $_[0]->cb->(@_);
};

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued');
use_ok('Test::HTTP::AnyEvent::Server');

my $server = Test::HTTP::AnyEvent::Server->new;
isa_ok($server, 'Test::HTTP::AnyEvent::Server');

my $q = AnyEvent::Net::Curl::Queued->new;
isa_ok($q, 'AnyEvent::Net::Curl::Queued');

can_ok($q, qw(append prepend cv));

my $n = 50;
for my $i (1 .. $n) {
    my $url = $server->uri . 'echo/head';
    $q->append(sub {
        MyDownloader->new({
            initial_url => $url,
            post        => "i=$i",
            cb          => sub {
                my ($self, $result) = @_;

                isa_ok($self, qw(MyDownloader));

                can_ok($self, qw(
                    data
                    final_url
                    has_error
                    header
                    initial_url
                ));

                ok($self->final_url eq $url, 'initial/final URLs match');
                ok($result == 0, 'got CURLE_OK');
                ok(!$self->has_error, "libcurl message: '$result'");

                like(${$self->data}, qr{^POST /echo/head HTTP/1\.[01]}i, 'got data: ' . ${$self->data});
            },
        })
    });
}
$q->cv->wait;

done_testing(5 + 6 * $n);
