package AnyEvent::Net::Curl::Queued;
# ABSTRACT: Moose wrapper for queued downloads via Net::Curl & AnyEvent

=head1 SYNOPSIS

    ...

=head1 DESCRIPTION

...

=cut

use common::sense;

use AnyEvent;
use Moose;
use Moose::Util::TypeConstraints;
use Net::Curl::Share qw(:constants);

use AnyEvent::Net::Curl::Queued::Multi;

# VERSION

=attr cv

L<AnyEvent> condition variable.
Initialized automatically, unless you specify your own.

=cut

has cv          => (is => 'ro', isa => 'AnyEvent::CondVar', default => sub { AE::cv }, lazy => 1);

=attr max

Maximum number of parallel connections (default: 4; minimum value: 2).

=cut

subtype 'MaxConn'
    => as Int
    => where { $_ >= 2 };
has max         => (is => 'ro', isa => 'MaxConn', default => 4);

=attr multi

L<Net::Curl::Multi> instance.

=cut

has multi       => (is => 'rw', isa => 'AnyEvent::Net::Curl::Queued::Multi');

=attr queue

C<ArrayRef> to the queue.
Has the following helper methods:

=for :list
* queue_push: append item at the end of the queue;
* queue_unshift: prepend item at the top of the queue;
* dequeue: shift item from the top of the queue;
* count: number of items in queue.

=cut

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

=attr share

L<Net::Curl::Share> instance.

=cut

has share       => (is => 'ro', isa => 'Net::Curl::Share', default => sub { Net::Curl::Share->new }, lazy => 1);

=attr stats

L<AnyEvent::Net::Curl::Queued::Stats> instance.

=cut

has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);

=attr timeout

Timeout (default: 10 seconds).

=cut

has timeout     => (is => 'ro', isa => 'Num', default => 10.0);

=attr unique

C<HashRef> to store request unique identifiers to prevent repeated accesses.

=cut

has unique      => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

sub BUILD {
    my ($self) = @_;

    $self->multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            max         => $self->max,
            timeout     => $self->timeout,
        })
    );

    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);   # 2
    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);      # 3
}

=method start()

Populate empty request slots with workers from the queue.

=cut

sub start {
    my ($self) = @_;

    # populate queue
    $self->add($self->dequeue)
        while
            $self->count
            and ($self->multi->handles < $self->max);

    # check if queue is empty
    $self->empty;
}

=method empty()

Check if there are active requests or requests in queue.

=cut

sub empty {
    my ($self) = @_;

    $self->cv->send
        if
            $self->stats->stats->{total} > 1
            and $self->count == 0
            and $self->multi->handles == 0;
}


=method add($worker)

Activate a worker.

=cut

sub add {
    my ($self, $worker) = @_;

    # vivify the worker
    $worker = $worker->()
        if ref($worker) eq 'CODE';

    # self-reference & warmup
    $worker->queue($self);
    $worker->init;

    # check if already processed
    if (my $unique = $worker->unique) {
        return if ++$self->unique->{$unique} > 1;
    }

    # fire
    $self->multi->add_handle($worker);
}

=method append($worker)

Put the worker at the end of the queue.

=cut

sub append {
    my ($self, $worker) = @_;

    $self->queue_push($worker);
    $self->start;
}

=method prepend($worker)

Put the worker at the beginning of the queue.

=cut

sub prepend {
    my ($self, $worker) = @_;

    $self->queue_unshift($worker);
    $self->start;
}

=method wait()

Shortcut to C<$queue-E<gt>cv-E<gt>recv>.

=cut

sub wait {
    my ($self) = @_;

    $self->cv->recv;
}

=head1 SEE ALSO

=for :list
* L<AnyEvent>
* L<Moose>
* L<Net::Curl>
* L<WWW::Curl>
* L<AnyEvent::Curl::Multi>

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;
