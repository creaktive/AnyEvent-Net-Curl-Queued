package AnyEvent::Net::Curl::Const;
# ABSTRACT: Access Net::Curl::* constants by name

=head1 SYNOPSIS

=for test_synopsis
my $easy;

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

use strict;
use utf8;
use warnings qw(all);

use Carp qw(carp);
use Net::Curl::Easy;
use Scalar::Util qw(looks_like_number);

# VERSION

=func info($constant_name)

Retrieve numeric value for C<$constant_name> in C<CURLINFO> namespace.

=func opt($constant_name)

Retrieve numeric value for C<$constant_name> in I<CURLOPT> namespace.

=cut

my (%const_info, %const_opt);

sub info {
    my ($name) = @_;
    $const_info{$name} = _curl_const(CURLINFO => $name)
        unless exists $const_info{$name};
    return $const_info{$name};
}

sub opt {
    my ($name) = @_;
    $const_opt{$name} = _curl_const(CURLOPT => $name)
        unless exists $const_opt{$name};
    return $const_opt{$name};
}

sub _curl_const {
    my ($suffix => $key) = @_;
    return $key if looks_like_number($key);

    $key =~ s{^Net::Curl::Easy::}{}ix;
    $key =~ y{-}{_};
    $key =~ s{\W}{}gx;
    $key = uc $key;
    $key = "${suffix}_${key}" if $key !~ m{^${suffix}_}x;

    my $val = eval {
        ## no critic (ProhibitNoStrict)
        no strict 'refs';
        my $const_name = 'Net::Curl::Easy::' . $key;
        *$const_name->();
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
