#!perl
use common::sense;

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued');
use_ok('AnyEvent::Net::Curl::Queued::Easy');
use_ok('Test::HTTP::Server');

my $server = Test::HTTP::Server->new;
isa_ok($server, 'Test::HTTP::Server');

my $q = AnyEvent::Net::Curl::Queued->new;
isa_ok($q, 'AnyEvent::Net::Curl::Queued');

can_ok($q, qw(append prepend cv));

my $n = 50;
for my $i (1 .. $n) {
    my $url = $server->uri . 'echo/head';
    my $post = "i=$i";
    $q->append(sub {
        AnyEvent::Net::Curl::Queued::Easy->new({
            initial_url => $url,
            on_init     => sub {
                my ($self) = @_;

                $self->sign($post);
                $self->setopt(postfields => $post);
            },
            on_finish   => sub {
                my ($self, $result) = @_;

                isa_ok($self, qw(AnyEvent::Net::Curl::Queued::Easy));

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

done_testing(6 + 6 * $n);
