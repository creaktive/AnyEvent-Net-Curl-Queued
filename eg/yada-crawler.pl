#!/usr/bin/env perl
use 5.016;
use common::sense;
use utf8::all;

use Web::Scraper::LibXML;
use YADA;

YADA->new(common_opts => { encoding => '' }, http_response => 1, max => 4)
->append([qw[http://localhost/manual/]] => sub {
    my ($self) = @_;
    my $response = $self->response;
    if ($response->is_success and $response->content_is_html) {
        my $doc = scraper {
            process q(html title), title => q(text);
            process q(a), q(links[]) => q(@href);
        }->scrape($response->decoded_content, $self->final_url);
        printf qq(%-64s %s\n), $self->final_url, $doc->{title} =~ s/\r?\n/ /rsx;
        $self->queue->prepend([
            grep { $_->can(q(host)) and $_->host eq $self->initial_url->host } @{$doc->{links}}
        ] => __SUB__) if q(ARRAY) eq ref $doc->{links};
    }
})->wait;
