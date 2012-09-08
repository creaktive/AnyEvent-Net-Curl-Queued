#!perl
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
use Test::HTTP::AnyEvent::Server;

my ($cv, $buf);
my $server = Test::HTTP::AnyEvent::Server->new;

$cv = run_cmd
    [qw[
        ab
        -c 10
        -n 100
        -r
    ], $server->uri . q(echo/head)],
    q(<)    => q(/dev/null),
    q(>)    => \$buf,
    q(2>)   => q(/dev/null),
    close_all => 1;
$cv->recv;
like($buf, qr{\bComplete\s+requests:\s*100\b}isx, q(benchmark));

$cv = run_cmd
    [qw[
        ab
        -c 100
        -n 100
        -i
        -r
    ], $server->uri . q(echo/head)],
    q(<)    => q(/dev/null),
    q(>)    => \$buf,
    q(2>)   => q(/dev/null),
    close_all => 1;
$cv->recv;
like($buf, qr{\bSend\s+request\s+failed\b}isx, q(DoS));

done_testing(2);
