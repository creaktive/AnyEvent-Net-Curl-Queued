package AnyEvent::Net::Curl::Queued::Easy;
use common::sense;

use Digest::SHA;
use Moose;
use MooseX::NonMoose;

extends 'Net::Curl::Easy';

use Net::Curl::Easy qw(/^CURLOPT_/);

has curl_result => (is => 'rw', isa => 'Net::Curl::Easy::Code');
has data        => (is => 'rw', isa => 'Ref');
has final_url   => (is => 'rw', isa => 'Str');
has header      => (is => 'rw', isa => 'Ref');
has initial_url => (is => 'ro', isa => 'Str', required => 1);
has queue       => (is => 'rw', isa => 'Ref');
has retry       => (is => 'rw', isa => 'Int', default => 5);
has sha         => (is => 'ro', isa => 'Digest::SHA', default => sub { new Digest::SHA(256) }, lazy => 1);
has share       => (is => 'rw', isa => 'Net::Curl::Share');
has timeout     => (is => 'rw', isa => 'Num', default => 10.0);

use overload '""' => \&unique, fallback => 1;

#sub BUILD {
#    my ($self) = @_;
#
#    $self->init;
#}

sub unique {
    my ($self) = @_;

    return $self->sha->clone->b64digest;
}

sub sign {
    my ($self, $str) = @_;

    $self->sha->add($str);
}

sub init {
    my ($self) = @_;

    $self->sign(__PACKAGE__);
    $self->sign($self->initial_url);

    $self->setopt(CURLOPT_SHARE,            $self->share);
    $self->setopt(CURLOPT_TIMEOUT,          $self->timeout);
    $self->setopt(CURLOPT_URL,              $self->initial_url);

    my $data;
    $self->setopt(CURLOPT_WRITEDATA,        \$data);
    $self->data(\$data);

    my $header;
    $self->setopt(CURLOPT_WRITEHEADER,      \$header);
    $self->header(\$header);
}

sub has_error {
    my ($self) = @_;
    return ($self->curl_result == Net::Curl::Easy::CURLE_OK) ? 0 : 1;
}

sub finish {
    my ($self, $result) = @_;

    $self->curl_result($result);
    $self->final_url($self->getinfo(Net::Curl::Easy::CURLINFO_EFFECTIVE_URL));

    $self->queue->cv->end;

    $self->queue->dec_active;

    if ($self->has_error and $self->retry > 0) {
        $self->queue->unique->{$self->unique} = 0;
        $self->queue->queue_push($self->clone);
    }

    $self->queue->start;
}

sub clone {
    my ($self) = @_;

    my @class = $self->meta->class_precedence_list;
    my $class = shift @class;

    return $class->new({
        initial_url     => $self->initial_url,
        retry           => $self->retry - 1,
    });
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
