#!perl
package MyDownloader;
use common::sense;

use Moose;
use Net::Curl::Easy qw(/^CURLOPT_/);

extends 'AnyEvent::Net::Curl::Queued::Easy';

has cb      => (is => 'ro', isa => 'CodeRef', required => 1);

after finish => sub {
    my ($self, $result) = @_;

    my @path = $self->final_url->path_segments;
    my $str = pop @path;
    my $num = pop @path;
    --$num;

    for (0 .. $num) {
        $str++;
        my $uri = $self->final_url->clone;
        $uri->path('/repeat/' . $_ . '/' . $str);

        # TODO prepend() fails sporadically?!
        $self->queue->append(
            sub {
                __PACKAGE__->new({
                    initial_url => $uri,
                    cb          => $self->cb,
                })
            }
        );
    }

    $self->cb->(@_);
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
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

$q->append(
    sub {
        MyDownloader->new({
            initial_url => $server->uri . 'repeat/6/aaaaa',
            cb          => sub {
                my ($self, $result) = @_;

                diag($self->final_url);

                isa_ok($self, qw(MyDownloader AnyEvent::Net::Curl::Queued::Easy));
                ok($result == 0, 'got CURLE_OK');
                ok(!$self->has_error, "libcurl message: '$result'");
            },
        })
    }
);

$q->wait;

done_testing(156);
