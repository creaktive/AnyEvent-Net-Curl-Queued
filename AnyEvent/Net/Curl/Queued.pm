package AnyEvent::Net::Curl::Queued;
use common::sense;

use AnyEvent;
use Moose;
use Net::Curl::Share qw(:constants);

use AnyEvent::Net::Curl::Queued::Multi;

has active      => (
    traits      => ['Counter'],
    is          => 'ro',
    isa         => 'Int',
    default     => 0,
    handles     => {qw{
        inc_active  inc
        dec_active  dec
    }},
);
has cv          => (is => 'ro', isa => 'AnyEvent::CondVar', default => sub { AE::cv }, lazy => 1);
has max         => (is => 'ro', isa => 'Int', default => 4);
has multi       => (is => 'rw', isa => 'AnyEvent::Net::Curl::Queued::Multi');
has queue       => (
    traits      => ['Array'],
    is          => 'ro',
    isa         => 'ArrayRef[Any]',
    default     => sub { [] },
    handles     => {qw{
        queue_push      push
        queue_unshift   unshift
        dequeue         shift
        count           count
    }},
);
has share       => (is => 'ro', isa => 'Net::Curl::Share', default => sub { Net::Curl::Share->new }, lazy => 1);
has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);
has timeout     => (is => 'ro', isa => 'Num', default => 10.0);
has unique      => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

sub BUILD {
    my ($self) = @_;

    $self->multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            timeout     => $self->timeout,
        })
    );

    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);   # 2
    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);      # 3
}

sub start {
    my ($self) = @_;

    $self->add($self->dequeue)
        while
            $self->count
            and ($self->active < $self->max);
}

sub add {
    my ($self, $worker) = @_;

    $worker->queue($self);
    $worker->init;

    if (my $unique = $worker->unique) {
        return if ++$self->unique->{$unique} > 1;
    }

    $self->inc_active;
    $self->cv->begin;

    $self->multi->add_handle($worker);
}

sub append {
    my ($self, $worker) = @_;

    $self->queue_push($worker);
    $self->start;
}

sub prepend {
    my ($self, $worker) = @_;

    $self->queue_unshift($worker);
    $self->start;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
