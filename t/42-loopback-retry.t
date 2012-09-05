#!perl
package MyDownloader;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

around has_error => sub {
    return 1;
};

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use strict;
use utf8;
use warnings qw(all);

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued');
use_ok('Test::HTTP::Server');

my $server = Test::HTTP::Server->new;
isa_ok($server, 'Test::HTTP::Server');

my $q = AnyEvent::Net::Curl::Queued->new;
isa_ok($q, 'AnyEvent::Net::Curl::Queued');

can_ok($q, qw(append prepend cv));

my $n = 10;
for my $i (1 .. $n) {
    my $url = $server->uri . 'echo/head';
    $q->append(sub {
        MyDownloader->new({
            initial_url => $url,
            on_init     => sub {
                my ($self) = @_;
                my $q = "i=$i";
                $self->sign($q);
                $self->setopt(CURLOPT_POSTFIELDS => $q);
            },
            on_finish   => sub {
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
                ok($self->has_error, "forced error");

                like(${$self->data}, qr{^POST /echo/head HTTP/1\.[01]}i, 'got data: ' . ${$self->data});
            },
            retry       => 3,
        })
    });
}
$q->cv->wait;

done_testing(5 + 6 * $n * 3);
