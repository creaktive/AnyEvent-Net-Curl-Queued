#!/usr/bin/env perl
use common::sense;

use Data::Printer;

use AnyEvent::Net::Curl::Queued;
use CrawlApache;

my $q = AnyEvent::Net::Curl::Queued->new;
$q->append(sub {
    CrawlApache->new({ initial_url => 'http://localhost/manual/', use_stats => 1 })
});
$q->wait;

p $q->stats;
