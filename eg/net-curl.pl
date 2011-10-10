#!/usr/bin/env perl

package MyDownloader;
use common::sense;

use Moose;
use Net::Curl::Easy qw(/^CURLOPT_/);

extends 'AnyEvent::Net::Curl::Queued::Easy';

after init => sub {
    my ($self) = @_;

    $self->setopt(CURLOPT_AUTOREFERER,      1);
    #$self->setopt(CURLOPT_ENCODING,         '');
    $self->setopt(CURLOPT_FILETIME,         1);
    $self->setopt(CURLOPT_FOLLOWLOCATION,   1);
    $self->setopt(CURLOPT_MAXREDIRS,        5);
    $self->setopt(CURLOPT_NOSIGNAL,         1);
    $self->setopt(CURLOPT_UNRESTRICTED_AUTH,1);
    $self->setopt(CURLOPT_USERAGENT,        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)');
    #$self->setopt(CURLOPT_VERBOSE,          1);
};

after finish => sub {
    my ($self, $result) = @_;

    if ($self->has_error) {
        say "ERROR";
    } else {
        printf "%s finished downloading %s: %d bytes\n", $self->unique, $self->final_url, length ${$self->data};
    }
};

around has_error => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->$orig(@_);
    return 1 if $self->getinfo(Net::Curl::Easy::CURLINFO_RESPONSE_CODE) =~ m{^5[0-9]{2}$};
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;
use lib qw(lib);

use AnyEvent;
use Data::Printer;

use AnyEvent::Net::Curl::Queued;

my $cv = AE::cv;
my $q = AnyEvent::Net::Curl::Queued->new({
    cv      => $cv,
    max     => 16,
    #retry   => 10,
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

        #$url =~ s/localhost/localhost:8888/;

        $q->prepend(sub {
            MyDownloader->new({
                initial_url => $url,
            })
        });
    }
};

$cv->wait;

p $q->stats->stats;
#p Net::Curl::version_info;
