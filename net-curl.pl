#!/usr/bin/env perl

package AnyEvent::Net::Curl::Queued::Multi;

use common::sense;

use Moose;
use MooseX::NonMoose;

extends 'Net::Curl::Multi';

use AnyEvent;
use Net::Curl::Multi qw(/^CURL_POLL_/ /^CURL_CSELECT_/);

has pool    => (is => 'ro', isa => 'HashRef[Ref]', default => sub { {} });
has timer   => (is => 'rw', isa => 'Any');

sub BUILD {
    my ($self) = @_;

    $self->setopt(Net::Curl::Multi::CURLMOPT_SOCKETFUNCTION    => \&_cb_socket);
    $self->setopt(Net::Curl::Multi::CURLMOPT_TIMERFUNCTION     => \&_cb_timer);
}

# socket callback: will be called by curl any time events on some
# socket must be updated
sub _cb_socket {
    my ($self, $easy, $socket, $poll) = @_;
    #warn "on_socket($socket => $poll)\n";

    # Right now $socket belongs to that $easy, but it can be
    # shared with another easy handle if server supports persistent
    # connections.
    # This is why we register socket events inside multi object
    # and not $easy.

    # deregister old io events
    delete $self->pool->{"r$socket"};
    delete $self->pool->{"w$socket"};

    # AnyEvent does not support registering a socket for both
    # reading and writing. This is rarely used so there is no
    # harm in separating the events.

    # register read event
    if (($poll == CURL_POLL_IN) or ($poll == CURL_POLL_INOUT)) {
        $self->pool->{"r$socket"} = AE::io $socket, 0, sub {
            $self->socket_action($socket, CURL_CSELECT_IN);
        };
    }

    # register write event
    if (($poll == CURL_POLL_OUT) or ($poll == CURL_POLL_INOUT)) {
        $self->pool->{"w$socket"} = AE::io $socket, 1, sub {
            $self->socket_action($socket, CURL_CSELECT_OUT);
        };
    }

    return 1;
}

# timer callback: It triggers timeout update. Timeout value tells
# us how soon socket_action must be called if there were no actions
# on sockets. This will allow curl to trigger timeout events.
sub _cb_timer {
    my ($self, $timeout_ms) = @_;
    #warn "on_timer($timeout_ms)\n";

    # deregister old timer
    $self->timer(undef);

    my $cb = sub {
        $self->socket_action(Net::Curl::Multi::CURL_SOCKET_TIMEOUT);
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

        $self->timer(AE::timer 10, 10, $cb)
            if $self->handles;
    } else {
        # This will trigger timeouts if there are any.
        $self->timer(AE::timer $timeout_ms / 1000, 0, $cb);
    }

    return 1;
}

around socket_action => sub {
    my $orig = shift;
    my $self = shift;

    my $active = $self->$orig(@_);

    while (my ($msg, $easy, $result) = $self->info_read) {
        if ($msg == Net::Curl::Multi::CURLMSG_DONE) {
            $self->remove_handle($easy);
            $easy->finish($result);
        } else {
            die "I don't know what to do with message $msg.\n";
        }
    }
};

# add one handle and kickstart download
sub add_handle {
    my ($self, $easy) = @_;
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
        $self->socket_action;
    };

    $self->SUPER::add_handle($easy);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package AnyEvent::Net::Curl::Queued::Easy;

use common::sense;

use Moose;
use MooseX::NonMoose;

extends 'Net::Curl::Easy';

use Net::Curl::Easy qw(/^CURLOPT_/);

has data        => (is => 'rw', isa => 'Ref');
has header      => (is => 'rw', isa => 'Ref');
has queue       => (is => 'rw', isa => 'Ref');
has share       => (is => 'rw', isa => 'Net::Curl::Share');
has unique      => (is => 'rw', isa => 'Str');
has url         => (is => 'rw', isa => 'Str', required => 1);

sub BUILD {
    my ($self) = @_;
    $self->init;
}

sub init {
    my ($self) = @_;

    my $data;
    $self->setopt(CURLOPT_WRITEDATA,        \$data);
    $self->data(\$data);

    my $header;
    $self->setopt(CURLOPT_WRITEHEADER,      \$header);
    $self->header(\$header);
}

sub finish {
    my ($self, $result) = @_;

    $self->queue->cv->end;

    $self->queue->dec_active;
    $self->queue->start;

}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package AnyEvent::Net::Curl::Queued;

use AnyEvent;
use Moose;
use Net::Curl::Share qw(:constants);

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
has multi       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Multi', default => sub { AnyEvent::Net::Curl::Queued::Multi->new }, lazy => 1);
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
has unique      => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

sub BUILD {
    my ($self) = @_;

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

    if ($worker->unique) {
        return if ++$self->unique->{$worker->unique} > 1;
    }

    $worker->queue($self);
    $worker->share($self->share);

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

package MyDownloader;
use common::sense;
use Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

use Net::Curl::Easy qw(/^CURLOPT_/);

after init => sub {
    my $self = shift;

    $self->setopt(CURLOPT_AUTOREFERER,      1);
    #$self->setopt(CURLOPT_ENCODING,         '');
    $self->setopt(CURLOPT_FILETIME,         1);
    $self->setopt(CURLOPT_FOLLOWLOCATION,   1);
    $self->setopt(CURLOPT_MAXREDIRS,        5);
    $self->setopt(CURLOPT_NOSIGNAL,         1);
    $self->setopt(CURLOPT_SHARE,            $self->share);
    $self->setopt(CURLOPT_TIMEOUT,          10);
    $self->setopt(CURLOPT_UNRESTRICTED_AUTH,1);
    $self->setopt(CURLOPT_URL,              $self->url);
    $self->setopt(CURLOPT_USERAGENT,        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)');
    #$self->setopt(CURLOPT_VERBOSE,          1);
};

after finish => sub {
    my $self = shift;
    my $result = shift;
    printf "%-30s finished downloading %s: %d bytes\n", $result, $self->url, length ${$self->data};
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;

use AnyEvent;
use DDP;
use List::Util qw(shuffle);

my $cv = AE::cv;
my $q = AnyEvent::Net::Curl::Queued->new({
    cv      => $cv,
    max     => 16,
});

open(my $fh, '<', 'localhost.txt') or die "erro: $!";

$cv->begin;
my $reader; $reader = AE::io $fh, 0, sub {
    if (eof($fh)) {
        undef $reader;
        $cv->end;
    } else {
        my $url = <$fh>;
        chomp $url;

        $q->prepend(
            MyDownloader->new({
                url     => $url,
            })
        );
    }
};

$cv->wait;

p Net::Curl::version_info;
