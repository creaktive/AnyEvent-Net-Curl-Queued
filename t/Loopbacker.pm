package Loopbacker;
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
use Net::Curl::Easy qw(/^CURLOPT_/);

extends 'AnyEvent::Net::Curl::Queued::Easy';

has cb      => (is => 'ro', isa => 'CodeRef', required => 1);
has post    => (is => 'ro', isa => 'Str', required => 1);

after init => sub {
    my ($self) = @_;

    $self->setopt(CURLOPT_POSTFIELDS, $self->post);
};

after finish => sub {
    $_[0]->cb->(@_);
};

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
