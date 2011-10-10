package AnyEvent::Net::Curl::Queued::Easy;

use common::sense;

use Moose;
use MooseX::NonMoose;

extends 'Net::Curl::Easy';

use Net::Curl::Easy qw(/^CURLOPT_/);

has data        => (is => 'rw', isa => 'Ref');
has header      => (is => 'rw', isa => 'Ref');
has queue       => (is => 'rw', isa => 'Ref');
has share       => (is => 'rw', isa => 'Net::Curl::Share');
has unique      => (is => 'rw', isa => 'Str');
has url         => (is => 'rw', isa => 'Str', required => 1);

sub BUILD {
    my ($self) = @_;
    $self->init;
}

sub init {
    my ($self) = @_;

    my $data;
    $self->setopt(CURLOPT_WRITEDATA,        \$data);
    $self->data(\$data);

    my $header;
    $self->setopt(CURLOPT_WRITEHEADER,      \$header);
    $self->header(\$header);
}

sub finish {
    my ($self, $result) = @_;

    $self->queue->cv->end;

    $self->queue->dec_active;
    $self->queue->start;

}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
