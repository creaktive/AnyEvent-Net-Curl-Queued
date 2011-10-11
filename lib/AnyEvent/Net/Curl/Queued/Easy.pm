package AnyEvent::Net::Curl::Queued::Easy;
# ABSTRACT: Net::Curl::Easy wrapped by Moose

=head1 SYNOPSIS

    ...

=head1 DESCRIPTION

    ...

=cut

use common::sense;

use Digest::SHA;
use Moose;
use MooseX::NonMoose;
use Net::Curl::Easy qw(/^CURLOPT_/);

extends 'Net::Curl::Easy';

use AnyEvent::Net::Curl::Queued::Stats;

# VERSION

# return code
has curl_result => (is => 'rw', isa => 'Net::Curl::Easy::Code');

# receive buffers
has data        => (is => 'rw', isa => 'Ref');
has header      => (is => 'rw', isa => 'Ref');

# URLs
has initial_url => (is => 'ro', isa => 'Str', required => 1);
has final_url   => (is => 'rw', isa => 'Str');

# queue back-reference
has queue       => (is => 'rw', isa => 'Ref');

# uniqueness detection helper
has sha         => (is => 'ro', isa => 'Digest::SHA', default => sub { new Digest::SHA(256) }, lazy => 1);

# accumulators
has retry       => (is => 'rw', isa => 'Int', default => 5);
has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);

=method unique()

Returns the unique signature of the request.
By default, the signature is derived from L<Digest::SHA> of the C<initial_url>.

=cut

sub unique {
    my ($self) = @_;

    # return the signature
    return $self->sha->clone->b64digest =~ tr{+/}{-_}r;
}

=method sign($str)

Use C<$str> to compute the C<unique> value.
Useful to successfully enqueue POST parameters.

=cut

sub sign {
    my ($self, $str) = @_;

    # add entropy to the signature
    $self->sha->add($str);
}

=method init()

Initialize the instance.
We can't use the default C<BUILD> method as we need the initialization to be done B<after> the instance is in the queue.

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub init {
    my ($self) = @_;

    # salt
    $self->sign(($self->meta->class_precedence_list)[0]);
    # URL; GET parameters included
    $self->sign($self->initial_url);

    # common parameters
    if ($self->queue) {
        $self->setopt(CURLOPT_SHARE,    $self->queue->share);
        $self->setopt(CURLOPT_TIMEOUT,  $self->queue->timeout);
    }
    $self->setopt(CURLOPT_URL,          $self->initial_url);

    # buffers
    my $data;
    $self->setopt(CURLOPT_WRITEDATA,    \$data);
    $self->data(\$data);

    my $header;
    $self->setopt(CURLOPT_WRITEHEADER,  \$header);
    $self->header(\$header);
}

=method has_error()

Error handling: if C<has_error> returns true, the request is re-enqueued (until the retries number is exhausted).

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub has_error {
    my ($self) = @_;

    # very bad error
    return ($self->curl_result == Net::Curl::Easy::CURLE_OK) ? 0 : 1;
}

=method finish($result)

Called when the download is finished.
C<$result> holds the C<Net::Curl::Easy::Code>.

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub finish {
    my ($self, $result) = @_;

    # populate results
    $self->curl_result($result);
    $self->final_url($self->getinfo(Net::Curl::Easy::CURLINFO_EFFECTIVE_URL));

    # inactivate worker
    $self->queue->cv->end;
    $self->queue->dec_active;

    # re-enqueue the request
    if ($self->has_error and $self->retry > 1) {
        $self->queue->unique->{$self->unique} = 0;
        $self->queue->queue_push($self->clone);
    }

    # update stats
    $self->stats->sum($self);
    $self->queue->stats->sum($self);

    # move queue
    $self->queue->start;
}

=method clone()

Clones the instance, for re-enqueuing purposes.

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub clone {
    my ($self) = @_;

    my $class = ($self->meta->class_precedence_list)[0];
    my $param = {
        initial_url => $self->initial_url,
        retry       => $self->retry - 1,
    };

    return sub { $class->new($param) };
}

=head1 SEE ALSO

=for :list
* L<Moose>
* L<MooseX::NonMoose>
* L<Net::Curl::Easy>

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;
