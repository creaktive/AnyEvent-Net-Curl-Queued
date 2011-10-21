package AnyEvent::Net::Curl::Const;
# ABSTRACT: Access Net::Curl::* constants by string

=head1 SYNOPSIS

    ...

=head1 DESCRIPTION

...

=cut

use common::sense;

use Carp qw(carp);
use Memoize;
use Net::Curl::Easy;
use Scalar::Util qw(looks_like_number);

# VERSION

memoize($_) for qw(info opt);

sub info {
    return _curl_const(CURLINFO => shift);
}

sub opt {
    return _curl_const(CURLOPT => shift);
}

sub _curl_const {
    my ($suffix => $key) = @_;

    return $key if looks_like_number($key);

    $key =~ s{^Net::Curl::Easy::}{}i;
    $key =~ y{-}{_};
    $key =~ s{\W}{}g;
    $key = uc $key;
    $key = "${suffix}_${key}" if $key !~ m{^${suffix}_};

    my $val;
    eval {
        no strict 'refs';   ## no critic
        my $const_name = 'Net::Curl::Easy::' . $key;
        $val = *$const_name->();
    };
    carp "Invalid libcurl constant: $key" if $@;

    return $val;
}

=head1 SEE ALSO

=for :list
* L<AnyEvent>
* L<Moose>
* L<Net::Curl>
* L<WWW::Curl>
* L<AnyEvent::Curl::Multi>

=cut

1;
