package Test::HTTP::AnyEvent::Server;
# ABSTRACT: Test::HTTP::Server, the asynchronous way

=head1 SYNOPSIS

    use Test::HTTP::AnyEvent::Server;

    my $server = Test::HTTP::AnyEvent::Server->new;

    AE::cv->wait;

=head1 DESCRIPTION

This package provides a simple B<NON>-forking HTTP server which can be used for testing HTTP clients.

=cut

use feature qw(switch);
use strict;
use utf8;
use warnings qw(all);

use Any::Moose;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Log;
use AnyEvent::Socket;
use AnyEvent::Util;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Response;
use POSIX;

#$AnyEvent::Log::FILTER->level('debug');

our (%pool, %timer);
our $VERSION = '0.003';

has address     => (is => 'ro', isa => 'Str', default => '127.0.0.1', writer => 'set_address');
has port        => (is => 'ro', isa => 'Int', writer => 'set_port');
has maxconn     => (is => 'ro', isa => 'Int', default => 10);
has timeout     => (is => 'ro', isa => 'Int', default => 10);
has disable_proxy => (is => 'ro', isa => 'Bool', default => 1);
has forked      => (is => 'ro', isa => 'Bool', default => 0);
has forked_pid  => (is => 'ro', isa => 'Int', writer => 'set_forked_pid');
has server      => (is => 'ro', isa => 'Ref', writer => 'set_server');

sub BUILD {
    my ($self) = @_;

    @ENV{qw(no_proxy http_proxy ftp_proxy all_proxy)} = (q(localhost,127.0.0.1), (q()) x 3)
        if $self->disable_proxy;

    unless ($self->forked) {
        $self->set_server(
            $self->start_server(sub {
                my (undef, $address, $port) = @_;
                $self->set_address($address);
                $self->set_port($port);
                AE::log info =>
                    "bound to http://$address:$port/";
            })
        );
    } else {
        my ($rh, $wh) = portable_pipe;

        given (fork) {
            when (undef) {
                AE::log fatal =>
                    "couldn't fork(): $!";
            } when (0) {
                # child
                close $rh;

                my $cv = AE::cv;
                my $h = AnyEvent::Handle->new(
                    fh          => $wh,
                    on_error    => sub {
                        my ($_h, $fatal, $msg) = @_;
                        shutdown $_h->{fh}, 2;
                        $_h->destroy;
                    },
                );

                my $server = $self->start_server(sub {
                    my (undef, $address, $port) = @_;
                    $h->push_write(join("\t", $address, $port));
                });

                $cv->wait;
                POSIX::_exit(0);
                exit 1;
            } default {
                # parent
                my $pid = $_;
                close $wh;

                my $buf;
                my $len = sysread $rh, $buf, 65536;
                AE::log fatal =>
                    "couldn't sysread() from pipe: $!"
                        if not defined $len or not $len;

                my ($address, $port) = split m{\t}x, $buf;
                $self->set_address($address);
                $self->set_port($port);
                $self->set_forked_pid($pid);
                AE::log info =>
                    "forked as $pid and bound to http://$address:$port/";
            }
        }
    }
}

sub DEMOLISH {
    my ($self) = @_;

    if ($self->forked) {
        my $pid = $self->forked_pid;
        kill 9 => $pid;
        AE::log info =>
            "killed $pid";
    }
}

=head1 METHODS

=head2 new

Create a new instance.

=head2 start_server

Internal.

=cut

sub start_server {
    my ($self, $cb) = @_;

    return tcp_server(
        $self->address => $self->port,
        sub {
            my ($fh, $host, $port) = @_;
            if (scalar keys %pool > $self->maxconn) {
                AE::log error =>
                    "deny connection from $host:$port (too many connections)\n";
                return;
            } else {
                AE::log warn =>
                    "new connection from $host:$port\n";
            }

            my $h = AnyEvent::Handle->new(
                fh          => $fh,
                on_eof      => \&_cleanup,
                on_error    => \&_cleanup,
                timeout     => $self->timeout,
            );

            $pool{fileno($fh)} = $h;
            AE::log debug =>
                sprintf "%d connection(s) in pool\n", scalar keys %pool;

            my ($req, $hdr);

            $h->push_read(regex => qr{\015?\012}x, sub {
                my ($h, $data) = @_;
                $data =~ s/\s+$//sx;
                $req = $data;
                AE::log debug => "request: [$req]\n";
            });

            $h->push_read(regex => qr{(\015?\012){2}}x, sub {
                my ($h, $data) = @_;
                $hdr = $data;
                AE::log debug => "got headers\n";
                if ($hdr =~ m{\bContent-length:\s*(\d+)\b}isx) {
                    AE::log debug => "expecting content\n";
                    $h->push_read(chunk => int($1), sub {
                        my ($h, $data) = @_;
                        _reply($h, $req, $hdr, $data);
                    });
                } else {
                    _reply($h, $req, $hdr);
                }
            });
        } => $cb
    );
}

=head2 uri

Return URI of a newly created server.

=cut

sub uri {
    my ($self) = @_;
    return sprintf('http://%s:%d/', $self->address, $self->port);
}

=head1 INTERNAL FUNCTIONS

=head2 _cleanup

Close descriptor and shutdown connection.

=cut

sub _cleanup {
    my ($h, $fatal, $msg) = @_;
    AE::log debug => "closing connection\n";
    eval {
        no warnings;    ## no critic

        my $id = fileno($h->{fh});
        delete $pool{$id};
        shutdown $h->{fh}, 2;
    };
    $h->destroy;
    return;
}

=head2 _reply

Issue HTTP reply to HTTP request.

=cut

sub _reply {
    my ($h, $req, $hdr, $content) = @_;

    my $res = HTTP::Response->new(
        200 => 'OK',
        HTTP::Headers->new(
            Connection      => 'close',
            Content_Type    => 'text/plain',
            Server          => __PACKAGE__ . "/$Test::HTTP::AnyEvent::Server::VERSION AnyEvent/$AE::VERSION Perl/$] ($^O)",
        )
    );
    $res->date(time);
    $res->protocol('HTTP/1.0');

    if ($req =~ m{^(GET|POST)\s+(.+)\s+(HTTP/1\.[01])$}ix) {
        my ($method, $uri, $protocol) = ($1, $2, $3);
        AE::log debug => "sending response\n";
        for ($uri) {
            when (m{^/repeat/(\d+)/(.+)}x) {
                $res->content($2 x $1);
            } when (m{^/echo/head$}x) {
                $res->content(
                    join(
                        "\015\012",
                        $req,
                        $hdr,
                    )
                );
            } when (m{^/echo/body$}x) {
                $res->content($content);
            } when (m{^/delay/(\d+)$}x) {
                $res->content('issued ' . scalar localtime);
                $timer{$h} = AE::timer $1, 0, sub {
                    delete $timer{$h};
                    AE::log debug => "delayed response\n";
                    $h->push_write($res->as_string("\015\012"));
                    _cleanup($h);
                };
                return;
            } default {
                $res->code(404);
                $res->message('Not Found');
                $res->content('Not Found');
            }
        }
    } else {
        AE::log error => "bad request\n";
        $res->code(400);
        $res->message('Bad Request');
        $res->content('Bad Request');
    }

    $h->push_write($res->as_string("\015\012"));
    _cleanup($h);
    return;
}

=head1 SEE ALSO

L<Test::HTTP::Server>

=cut

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
