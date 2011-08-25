#!/usr/bin/env perl

package Multi::Event;

use base qw(Net::Curl::Multi);
use common::sense;

use AE;
use Net::Curl::Multi qw(/^CURL_POLL_/ /^CURL_CSELECT_/);

BEGIN {
    unless (Net::Curl::Multi->can('CURLMOPT_TIMERFUNCTION')) {
        die "Net::Curl::Multi is missing timer callback,\n" .
            "rebuild Net::Curl with libcurl 7.16.0 or newer\n";
    }
}

sub new {
    my ($class) = @_;

    # no base object this time
    # we'll use the default hash
    my $multi = $class->SUPER::new;

    $multi->setopt(Net::Curl::Multi::CURLMOPT_SOCKETFUNCTION, \&_cb_socket);
    $multi->setopt(Net::Curl::Multi::CURLMOPT_TIMERFUNCTION, \&_cb_timer);

    return $multi;
}

# socket callback: will be called by curl any time events on some
# socket must be updated
sub _cb_socket {
    my ($multi, $easy, $socket, $poll) = @_;
    #warn "on_socket($socket => $poll)\n";

    # Right now $socket belongs to that $easy, but it can be
    # shared with another easy handle if server supports persistent
    # connections.
    # This is why we register socket events inside multi object
    # and not $easy.

    # deregister old io events
    delete $multi->{"r$socket"};
    delete $multi->{"w$socket"};

    # AnyEvent does not support registering a socket for both
    # reading and writing. This is rarely used so there is no
    # harm in separating the events.

    # register read event
    if (($poll == CURL_POLL_IN) or ($poll == CURL_POLL_INOUT)) {
        $multi->{"r$socket"} = AE::io $socket, 'r', sub {
            $multi->socket_action($socket, CURL_CSELECT_IN);
        };
    }

    # register write event
    if (($poll == CURL_POLL_OUT) or ($poll == CURL_POLL_INOUT)) {
        $multi->{"w$socket"} = AE::io $socket, 'w', sub {
            $multi->socket_action($socket, CURL_CSELECT_OUT);
        };
    }

    return 1;
}

# timer callback: It triggers timeout update. Timeout value tells
# us how soon socket_action must be called if there were no actions
# on sockets. This will allow curl to trigger timeout events.
sub _cb_timer {
    my ($multi, $timeout_ms) = @_;
    #warn "on_timer($timeout_ms)\n";

    # deregister old timer
    delete $multi->{timer};

    my $cb = sub {
        $multi->socket_action(Net::Curl::Multi::CURL_SOCKET_TIMEOUT);
    };

    if ($timeout_ms < 0) {
        # Negative timeout means there is no timeout at all.
        # Normally happens if there are no handles anymore.
        #
        # However, curl_multi_timeout(3) says:
        #
        # Note: if libcurl returns a -1 timeout here, it just means
        # that libcurl currently has no stored timeout value. You
        # must not wait too long (more than a few seconds perhaps)
        # before you call curl_multi_perform() again.

        if ($multi->handles) {
            $multi->{timer} = AE::timer 10, 10, $cb;
        }
    } else {
        # This will trigger timeouts if there are any.
        $multi->{timer} = AE::timer $timeout_ms / 1000, 0, $cb;
    }

    return 1;
}

# add one handle and kickstart download
sub add_handle($$) {
    my ($multi, $easy) = @_;

    die "easy cannot finish()\n"
        unless $easy->can('finish');

    # Calling socket_action with default arguments will trigger
    # socket callback and register IO events.
    #
    # It _must_ be called _after_ add_handle(); AE will take care
    # of that.
    #
    # We are delaying the call because in some cases socket_action
    # may finish immediately (i.e. there was some error or we used
    # persistent connections and server returned data right away)
    # and it could confuse our application -- it would appear to
    # have finished before it started.
    AE::timer 0, 0, sub {
        $multi->socket_action;
    };

    $multi->SUPER::add_handle($easy);
}

# perform and call any callbacks that have finished
sub socket_action {
    my $multi = shift;

    my $active = $multi->SUPER::socket_action(@_);

    while (my ($msg, $easy, $result) = $multi->info_read) {
        if ($msg == Net::Curl::Multi::CURLMSG_DONE) {
            $multi->remove_handle($easy);
            $easy->finish($result);
        } else {
            die "I don't know what to do with message $msg.\n";
        }
    }
}

1;

package Easy::Event;

use base qw(Net::Curl::Easy);
use common::sense;

use Net::Curl::Easy qw(/^CURLOPT_/);

sub new {
    my ($class, $uri, $share, $cb) = @_;

    my $easy = $class->SUPER::new({ uri => $uri, body => '', cb => $cb });

    $easy->setopt(CURLOPT_AUTOREFERER,      1);
    $easy->setopt(CURLOPT_ENCODING,         '');
    $easy->setopt(CURLOPT_FILETIME,         1);
    $easy->setopt(CURLOPT_FOLLOWLOCATION,   1);
    $easy->setopt(CURLOPT_MAXREDIRS,        5);
    $easy->setopt(CURLOPT_NOSIGNAL,         1);
    $easy->setopt(CURLOPT_SHARE,            $share);
    $easy->setopt(CURLOPT_TIMEOUT,          10);
    $easy->setopt(CURLOPT_UNRESTRICTED_AUTH,1);
    $easy->setopt(CURLOPT_URL,              $uri);
    $easy->setopt(CURLOPT_USERAGENT,        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)');
    #$easy->setopt(CURLOPT_VERBOSE,          1);
    $easy->setopt(CURLOPT_WRITEDATA,        \$easy->{body});
    $easy->setopt(CURLOPT_WRITEHEADER,      \$easy->{headers});

    return $easy;
}

sub finish {
    $_[0]->{cb}->(@_);
}

1;

package Queue::Event;

use AE;
use Moose;
use Net::Curl::Share qw(:constants);

has active  => (
    traits  => ['Counter'],
    is      => 'ro',
    isa     => 'Int',
    default => 0,
    handles => {qw{
        inc_active  inc
        dec_active  dec
    }},
);
has cv      => (is => 'ro', isa => 'AnyEvent::CondVar', default => sub { AE::cv }, lazy => 1);
has max     => (is => 'ro', isa => 'Int', default => 4);
has multi   => (is => 'ro', isa => 'Multi::Event', default => sub { Multi::Event->new }, lazy => 1);
has queue   => (
    traits  => ['Array'],
    is      => 'ro',
    isa     => 'ArrayRef[Any]',
    default => sub { [] },
    handles => {qw{
        enqueue     push
        dequeue     shift
        count       count
    }},
);
has share   => (is => 'ro', isa => 'Net::Curl::Share', default => sub { Net::Curl::Share->new }, lazy => 1);

sub BUILD {
    my ($self) = @_;
    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);   # 2
    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);      # 3
}

sub start {
    my ($self) = @_;
    $self->feed;
    $self->cv->wait;
}

sub feed {
    my ($self) = @_;

    $self->add($self->dequeue)
        while
            $self->count
            and ($self->active < $self->max);
}

sub add {
    my ($self, $url) = @_;

    $self->inc_active;

    $self->cv->begin;
    $self->multi->add_handle(
        Easy::Event->new(
            $url,
            $self->share,
            sub {
                my ($easy, $result) = @_;
                printf "%-20s finished downloading %s: %d bytes\n", $result, $easy->{uri}, length $easy->{body};
                # process...                
                $self->cv->end;

                $self->dec_active;
                $self->feed;
            }
        )
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;

use DDP;
use FindBin qw($RealBin);
use List::Util qw(shuffle);

my @urls;
open(my $fh, '<', 'localhost.txt') or die "erro: $!";
while (my $url = <$fh>) {
    chomp $url;
    #$url =~ s/localhost/localhost:8888/;
    push @urls, $url for 1..10;
}
close $fh;

my $q = Queue::Event->new({ max => 8 });
$q->enqueue($_) for shuffle @urls;
#$q->enqueue("file://$RealBin/jacotei_livro.xml");
$q->start;

p Net::Curl::version_info;
