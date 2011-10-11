#!perl
use common::sense;

use Test::More;

use_ok('AnyEvent::Net::Curl::Queued::Easy');
use Net::Curl::Easy qw(:constants);

my $easy = new AnyEvent::Net::Curl::Queued::Easy({ initial_url => 'http://www.cpan.org/' });
isa_ok($easy, qw(Net::Curl::Easy AnyEvent::Net::Curl::Queued::Easy));
can_ok($easy, qw(
    clone
    curl_result
    data
    final_url
    finish
    has_error
    header
    init
    initial_url
    new
    queue
    retry
    sha
    sign
    stats
    unique

    perform
));

$easy->init;

ok($easy->sign('TEST'), 'sign()');
ok($easy->unique eq 'iNmIrn-mUqH6CA6Ee78z1Sek5Rl5zXzO5Hc9j127_1s', 'URL uniqueness signature: ' . $easy->unique);
ok($easy->perform == Net::Curl::Easy::CURLE_OK, 'perform()');
ok($easy->getinfo(Net::Curl::Easy::CURLINFO_RESPONSE_CODE) eq '200', '200 OK');

isa_ok($easy->stats, 'AnyEvent::Net::Curl::Queued::Stats');
ok($easy->stats->sum($easy), 'stats sum()');

ok($easy->stats->stats->{header_size} == length ${$easy->header}, 'headers size match');
ok($easy->stats->stats->{size_download} == length ${$easy->data}, 'body size match');

done_testing(11);
