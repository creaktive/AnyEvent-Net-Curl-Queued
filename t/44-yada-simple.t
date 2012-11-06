#!perl
use strict;
use utf8;
use warnings qw(all);

use Test::More;

use Test::HTTP::AnyEvent::Server;
use YADA;

my $server = Test::HTTP::AnyEvent::Server->new;

my $q = YADA->new(allow_dups => 1);
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

my @urls = ($server->uri . 'echo/head') x 2;
$urls[-1] =~ s{\b127\.0\.0\.1\b}{localhost};
my @opts = (referer => 'http://www.cpan.org/');
my $on_finish = sub {
    my ($self, $r) = @_;
    isa_ok($self->res, qw(HTTP::Response));
    like($self->res->decoded_content, qr{\bReferer\s*:\s*\Q$opts[1]\E}isx);
};

$q->append(
    { http_response => 1 },
    @urls,
    sub { $_[0]->setopt(@opts) }, # on_init placeholder
    $on_finish,
);

$q->append(
    [ @urls ],
    { http_response => 1, opts => { @opts } },
    $on_finish,
);

$q->append(
    URI->new($_) => $on_finish,
    { http_response => 1, opts => { @opts } },
) for @urls;

$q->append(
    \@urls => {
        http_response   => 1,
        opts            => { @opts },
        on_finish       => $on_finish,
    }
);

$q->wait;

done_testing(20 + 4 * (scalar @urls) * 2);
