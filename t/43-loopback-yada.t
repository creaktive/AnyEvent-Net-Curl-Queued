#!perl
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

use Test::More;

use_ok('YADA');
use_ok('YADA::Worker');
use_ok('Test::HTTP::AnyEvent::Server');

my $server = Test::HTTP::AnyEvent::Server->new;
isa_ok($server, 'Test::HTTP::AnyEvent::Server');

my $q = YADA->new;
isa_ok($q, qw(YADA));

can_ok($q, qw(append wait));

for my $j (1 .. 10) {
    for my $i (1 .. 10) {
        my $url = $server->uri . 'echo/head';
        my $post = qq({"i":$i,"j":$j,"k":"яда"});
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

                    isa_ok($self, qw(YADA::Worker));

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

                    like(${$self->data}, qr{\bContent-Type:\s*application/json\b}i, 'got data: ' . ${$self->data});
                },
            })
        });
    }
    $q->wait;
}

done_testing(6 + 6 * 100);
