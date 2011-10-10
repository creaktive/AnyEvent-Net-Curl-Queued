#!perl
use common::sense;

use Test::More tests => 1;

BEGIN {
    use_ok('AnyEvent::Net::Curl::Queued');
}

diag("Testing AnyEvent::Net::Curl::Queued v$AnyEvent::Net::Curl::Queued::VERSION, Perl $], $^X");
