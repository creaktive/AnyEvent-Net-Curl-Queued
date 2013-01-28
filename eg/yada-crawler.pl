#!/usr/bin/env perl
use 5.016;
use common::sense;
use utf8::all;

use Web::Scraper::LibXML;
use YADA;

my $parser = scraper {
    process q(html title), title => q(text);
    process q(a), q(links[]) => q(@href);
};

YADA->new(16)->append({ http_response => 1 } => [qw[http://localhost/manual/]] => sub {
    my ($self) = @_;
    my ($response_code, $content_type) = $self->getinfo([qw[response_code content_type]]);
    if (not $self->has_error and $response_code eq q(200) and $content_type =~ m{^text/html\b}x) {
        my $parsed = $parser->scrape($self->res->decoded_content, $self->final_url);
        printf qq(%-64s %s\n), $self->final_url, $parsed->{title} =~ s/\r?\n/ /rsx;
        $self->queue->prepend({ http_response => 1 } => [
            grep { $_->can(q(host)) and $_->host eq $self->initial_url->host } @{$parsed->{links}}
        ] => __SUB__) if q(ARRAY) eq ref $parsed->{links};
    }
})->wait;
