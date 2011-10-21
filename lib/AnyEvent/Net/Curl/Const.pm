package AnyEvent::Net::Curl::Const;
# ABSTRACT: Access Net::Curl::* constants by name

=for test_synopsis
my ($easy);

=head1 SYNOPSIS

    $easy->setopt(AnyEvent::Net::Curl::Const::opt('verbose'), 1);
    ...;
    $easy->getinfo(AnyEvent::Net::Curl::Const::info('size_download'));

=head1 DESCRIPTION

Perl-friendly access to the L<libcurl|http://curl.haxx.se/libcurl/> constants.
For example, you can access C<CURLOPT_TCP_NODELAY> value by supplying any of:

=for :list
* C<'Net::Curl::Easy::CURLOPT_TCP_NODELAY'>
* C<'CURLOPT_TCP_NODELAY'>
* C<'TCP_NODELAY'>
* C<'TCP-NoDelay'>
* C<'tcp_nodelay'>

=cut

use common::sense;

use Carp qw(carp);
use Memoize;
use Net::Curl::Easy;
use Scalar::Util qw(looks_like_number);

# VERSION

memoize($_) for qw(info opt);

=func info($constant_name)

Retrieve numeric value for C<$constant_name> in C<CURLINFO> namespace.

=func opt($constant_name)

Retrieve numeric value for C<$constant_name> in I<CURLOPT> namespace.

=cut

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
* L<libcurl - curl_easy_getinfo()|http://curl.haxx.se/libcurl/c/curl_easy_getinfo.html>
* L<libcurl - curl_easy_setopt()|http://curl.haxx.se/libcurl/c/curl_easy_setopt.html>
* L<Net::Curl::Easy>

=cut

1;
