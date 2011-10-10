#!/usr/bin/env perl

package MyDownloader;
use common::sense;
use Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

use Net::Curl::Easy qw(/^CURLOPT_/);

after init => sub {
    my ($self) = @_;

    $self->setopt(CURLOPT_AUTOREFERER,      1);
    #$self->setopt(CURLOPT_ENCODING,         '');
    $self->setopt(CURLOPT_FILETIME,         1);
    $self->setopt(CURLOPT_FOLLOWLOCATION,   1);
    $self->setopt(CURLOPT_MAXREDIRS,        5);
    $self->setopt(CURLOPT_NOSIGNAL,         1);
    $self->setopt(CURLOPT_SHARE,            $self->share);
    $self->setopt(CURLOPT_TIMEOUT,          10);
    $self->setopt(CURLOPT_UNRESTRICTED_AUTH,1);
    $self->setopt(CURLOPT_URL,              $self->url);
    $self->setopt(CURLOPT_USERAGENT,        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)');
    #$self->setopt(CURLOPT_VERBOSE,          1);
};

after finish => sub {
    my ($self, $result) = @_;

    printf "%-30s finished downloading %s: %d bytes\n", $result, $self->url, length ${$self->data};
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;

use AnyEvent;
use Data::Printer;

use AnyEvent::Net::Curl::Queued;

my $cv = AE::cv;
my $q = AnyEvent::Net::Curl::Queued->new({
    cv      => $cv,
    max     => 16,
});

open(my $fh, '<', 'localhost.txt') or die "erro: $!";

$cv->begin;
my $reader;
$reader = AE::io $fh, 0, sub {
    if (eof($fh)) {
        close $fh;
        undef $reader;
        $cv->end;
    } else {
        my $url = <$fh>;
        chomp $url;

        $q->prepend(
            MyDownloader->new({
                url     => $url,
            })
        );
    }
};

$cv->wait;

p Net::Curl::version_info;
