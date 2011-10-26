#!perl
use common::sense;

use Test::More;

use_ok('YADA');
use_ok('YADA::Worker');
use_ok('Test::HTTP::Server');

my $server = Test::HTTP::Server->new;
isa_ok($server, 'Test::HTTP::Server');

my $q = YADA->new;
isa_ok($q, qw(AnyEvent::Net::Curl::Queued YADA));

can_ok($q, qw(append wait));

my $n = 50;
for my $i (1 .. $n) {
    my $url = $server->uri . 'echo/head';
    my $post = "i=$i";
    $q->append(sub {
        YADA::Worker->new({
            initial_url => $url,
            on_init     => sub {
                my ($self) = @_;

                $self->sign($post);
                $self->setopt(postfields => $post);
            },
            on_finish   => sub {
                my ($self, $result) = @_;

                isa_ok($self, qw(AnyEvent::Net::Curl::Queued::Easy YADA::Worker));

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
$q->wait;

done_testing(6 + 6 * $n);
