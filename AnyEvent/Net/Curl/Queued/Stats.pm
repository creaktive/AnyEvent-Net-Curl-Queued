package AnyEvent::Net::Curl::Queued::Stats;
use common::sense;

use Moose;

use Net::Curl::Easy qw(/^CURLOPT_/);

has stamp       => (is => 'rw', isa => 'Int', default => time);
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
        total_time          => 0,
    } },
);

sub sum {
    my ($self, $from) = @_;

    foreach my $type (keys %{$self->stats}) {
        my $val = 0;

        if (ref($from) ne __PACKAGE__) {
            eval '$val = $from->getinfo(Net::Curl::Easy::CURLINFO_' . uc($type) . ')';  ## no critic
        } else {
            $val = $from->stats->{$type};
        }

        $self->stats->{$type} += $val;
    }

    $self->stamp(time);
    return 1;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
