#!perl
package AnyEvent::HTTP::Tiny;
use strict;
use utf8;
use warnings qw(all);

use AnyEvent::Handle;
use HTTP::Response;

use constant CRLF => "\015\012";

sub http_req {
    my ($req, $cb) = @_;

    return $cb->(HTTP::Response->new(500, 'Usage: http_req(HTTP::Request->new(...), sub {...})'))
        if
            ref($req) ne 'HTTP::Request'
            or ref($cb) ne 'CODE';
    return $cb->(HTTP::Response->new(500, 'Unsupported Protocol'))
        unless $req->uri->scheme =~ m{^https?$};

    $req->header(Content_Length => length $req->content) if $req->content;
    $req->header(Host           => $req->uri->host_port);
    $req->header(User_Agent     => "AnyEvent/$AE::VERSION Perl/$] ($^O)");

    my $buf = '';

    my $h;
    $h = new AnyEvent::Handle
        connect     => [$req->uri->host => $req->uri->port],
        on_eof      => sub {
            $cb->(HTTP::Response->parse($buf));
            $h->destroy;
        },
        on_error    => sub {
            $cb->(HTTP::Response->new(500, $!));
            $h->destroy;
        },
        tls         => ($req->uri->scheme eq 'https') ? 'connect' : undef;

    $h->push_write(
        $req->method . ' ' . $req->uri->path_query . ' HTTP/1.0' . CRLF .
        $req->headers->as_string(CRLF) . CRLF .
        $req->content
    );

    $h->on_read(
        sub {
            my ($h) = @_;
            $buf .= $h->rbuf;
            $h->rbuf = '';
        }
    );
}

1;

package main;
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

BEGIN {
    unless ($ENV{TEST_SERVER}) {
        require Test::More;
        Test::More::plan(skip_all => 'these tests are for testing by the author');
    }
}

use Test::More;

use AnyEvent::Util;
use HTTP::Request;
use Test::HTTP::AnyEvent::Server;

my $server = Test::HTTP::AnyEvent::Server->new;

my $cv = AE::cv;
AnyEvent::HTTP::Tiny::http_req(
    HTTP::Request->new(GET => $server->uri . 404),
    sub {
        is(shift->code, 404, q(404 Not Found));
        $cv->send;
    }
);
$cv->recv;

my $buf;
my $num = 1000;

$buf = '';
$cv = run_cmd
    [qw[
        ab
        -c 10
        -n], $num, qw[
        -r
    ], $server->uri . q(echo/head)],
    q(<)    => q(/dev/null),
    q(>)    => \$buf,
    q(2>)   => q(/dev/null),
    close_all => 1;
$cv->recv;
like($buf, qr{\bComplete\s+requests:\s*${num}\b}isx, q(benchmark complete));
like($buf, qr{\bFailed\s+requests:\s*0\b}isx, q(benchmark failed));
like($buf, qr{\bWrite\s+errors:\s*0\b}isx, q(benchmark write errrors));

$buf = '';
$cv = run_cmd
    [qw[
        ab
        -c 100
        -n], $num, qw[
        -i
        -r
    ], $server->uri . q(echo/head)],
    q(<)    => q(/dev/null),
    q(>)    => \$buf,
    q(2>)   => q(/dev/null),
    close_all => 1;
$cv->recv;
unlike($buf, qr{\bFailed\s+requests:\s*0\b}isx, q(benchmark failed));

done_testing(5);
