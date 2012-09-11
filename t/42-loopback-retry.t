#!perl
package MyDownloader;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

has attr1 => (is => 'ro', isa => 'Num', required => 1);
has attr2 => (is => 'ro', isa => 'Int', required => 1);
has attr3 => (is => 'rw', isa => 'URI');
has attr4 => (is => 'rw', isa => 'Str', default => 'A');

around clone => sub {
    my $orig = shift;
    my $self = shift;
    my $param = shift;

    $param->{$_} = $self->$_
        for qw(
            attr1
            attr2
            attr3
        );

    return $self->$orig($param);
};

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

use lib qw(inc);

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued');
use_ok('Test::HTTP::AnyEvent::Server');

my $server = Test::HTTP::AnyEvent::Server->new;
isa_ok($server, 'Test::HTTP::AnyEvent::Server');

my $q = AnyEvent::Net::Curl::Queued->new;
isa_ok($q, 'AnyEvent::Net::Curl::Queued');

can_ok($q, qw(append prepend cv));

my $n = 10;
for my $i (1 .. $n) {
    my $url = $server->uri . 'echo/head';
    $q->append(sub {
        MyDownloader->new({
            attr1       => rand,
            attr2       => $i,
            attr3       => URI->new($url),
            attr4       => 'B',
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
                    attr1
                    attr2
                    attr3
                    clone
                    data
                    final_url
                    has_error
                    header
                    initial_url
                ));

                ok($self->attr1 >= 0, 'custom attribute 1 is >= 0');
                ok($self->attr1 < 1, 'custom attribute 1 is < 1');

                ok($self->attr2 == $i, 'custom attribute 2 ok');

                ok(ref($self->attr3) =~ m{^URI\b}, 'custom attribute 3 ok');

                ok(
                    (($self->retry == 5) and ($self->attr4 =~ /A/))
                        or
                    (($self->retry < 5) and ($self->attr4 =~ /B/)),
                    'custom attribute 4 ok (not cloned!)'
                );

                ok($self->final_url eq $url, 'initial/final URLs match');
                ok($result == 0, 'got CURLE_OK');
                ok($self->has_error, "forced error");

                like(${$self->data}, qr{^POST /echo/head HTTP/1\.[01]}i, 'got data: ' . ${$self->data});
            },
            retry       => 5,
        })
    });
}
$q->cv->wait;

done_testing(555);
