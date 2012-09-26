#!perl
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

use Test::More;

use Test::HTTP::AnyEvent::Server;
use YADA;

my $server = Test::HTTP::AnyEvent::Server->new;

my $q = YADA->new;
for my $i (1 .. 10) {
    for my $method (qw(append prepend)) {
        $q->$method(
            $server->uri . "repeat/$i/$method",
            sub {
                my ($self, $result) = @_;
                like(${$self->data}, qr{^(?:$method){$i}$}, 'got data: ' . ${$self->data});
            }
        );
    }
}
$q->wait;

done_testing(20);
