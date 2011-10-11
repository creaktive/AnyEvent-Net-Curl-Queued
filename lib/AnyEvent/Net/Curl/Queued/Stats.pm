package AnyEvent::Net::Curl::Queued::Stats;
# ABSTRACT: Connection statistics for AnyEvent::Net::Curl::Queued::Easy

=head1 SYNOPSIS

    use AnyEvent::Net::Curl::Queued;
    use Data::Printer;

    my $q = AnyEvent::Net::Curl::Queued->new;
    ...;
    $q->wait;

    p $q->stats;

    $q->stats->sum(AnyEvent::Net::Curl::Queued::Stats->new);

=head1 DESCRIPTION

Tracks statistics for L<AnyEvent::Net::Curl::Queued> and L<AnyEvent::Net::Curl::Queued::Easy>.

=cut

use common::sense;

use Moose;
use Net::Curl::Easy qw(/^CURLOPT_/);

# VERSION

=attr stamp

Unix timestamp for statistics update.

=cut

has stamp       => (is => 'rw', isa => 'Int', default => time);

=attr stats

C<HashRef[Num]> with statistics:

    appconnect_time
    connect_time
    header_size
    namelookup_time
    num_connects
    pretransfer_time
    redirect_count
    redirect_time
    request_size
    size_download
    size_upload
    starttransfer_time
    total
    total_time

Variable names are from respective L<curl_easy_getinfo()|http://curl.haxx.se/libcurl/c/curl_easy_getinfo.html> accessors.

=cut

has stats       => (
    is          => 'ro',
    isa         => 'HashRef[Num]',
    default     => sub { {
        appconnect_time     => 0,
        connect_time        => 0,
        header_size         => 0,
        namelookup_time     => 0,
        num_connects        => 0,
        pretransfer_time    => 0,
        redirect_count      => 0,
        redirect_time       => 0,
        request_size        => 0,
        size_download       => 0,
        size_upload         => 0,
        starttransfer_time  => 0,
        total               => 0,
        total_time          => 0,
    } },
);

=method sum($from)

Aggregate attributes from the C<$from> object.
It is supposed to be an instance of L<AnyEvent::Net::Curl::Queued::Easy> or L<AnyEvent::Net::Curl::Queued::Stats>.

=cut

sub sum {
    my ($self, $from) = @_;

    foreach my $type (keys %{$self->stats}) {
        my $val = 0;

        if ($from->isa('AnyEvent::Net::Curl::Queued::Easy')) {
            eval '$val = $from->getinfo(Net::Curl::Easy::CURLINFO_' . uc($type) . ')';  ## no critic
        } elsif (ref($from) eq __PACKAGE__) {
            $val = $from->stats->{$type};
        }

        $self->stats->{$type} += $val;
    }

    ++$self->stats->{total};
    $self->stamp(time);

    return 1;
}

=head1 SEE ALSO

=for :list
* L<AnyEvent::Net::Curl::Queued::Easy>
* L<AnyEvent::Net::Curl::Queued>

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;
