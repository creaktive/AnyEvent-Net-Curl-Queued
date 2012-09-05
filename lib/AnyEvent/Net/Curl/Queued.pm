package AnyEvent::Net::Curl::Queued;
# ABSTRACT: Any::Moose wrapper for queued downloads via Net::Curl & AnyEvent

=head1 SYNOPSIS

    #!/usr/bin/env perl

    package CrawlApache;
    use strict;
    use utf8;
    use warnings qw(all);

    use HTML::LinkExtor;
    use Any::Moose;

    extends 'AnyEvent::Net::Curl::Queued::Easy';

    after finish => sub {
        my ($self, $result) = @_;

        say $result . "\t" . $self->final_url;

        if (
            not $self->has_error
            and $self->getinfo('content_type') =~ m{^text/html}
        ) {
            my @links;

            HTML::LinkExtor->new(sub {
                my ($tag, %links) = @_;
                push @links,
                    grep { $_->scheme eq 'http' and $_->host eq 'localhost' }
                    values %links;
            }, $self->final_url)->parse(${$self->data});

            for my $link (@links) {
                $self->queue->prepend(sub {
                    CrawlApache->new({ initial_url => $link });
                });
            }
        }
    };

    no Any::Moose;
    __PACKAGE__->meta->make_immutable;

    1;

    package main;
    use strict;
    use utf8;
    use warnings qw(all);

    use AnyEvent::Net::Curl::Queued;

    my $q = AnyEvent::Net::Curl::Queued->new;
    $q->append(sub {
        CrawlApache->new({ initial_url => 'http://localhost/manual/' })
    });
    $q->wait;

=head1 DESCRIPTION

Efficient and flexible batch downloader with a straight-forward interface:

=for :list
* create a queue;
* append/prepend URLs;
* wait for downloads to end (retry on errors).

Download init/finish/error handling is defined through L<Moose's method modifiers|Moose::Manual::MethodModifiers>.

=head2 MOTIVATION

I am very unhappy with the performance of L<LWP>.
It's almost perfect for properly handling HTTP headers, cookies & stuff, but it comes at the cost of I<speed>.
While this doesn't matter when you make single downloads, batch downloading becomes a real pain.

When I download large batch of documents, I don't care about cookies or headers, only content and proper redirection matters.
And, as it is clearly an I/O bottleneck operation, I want to make as many parallel requests as possible.

So, this is what L<CPAN> offers to fulfill my needs:

=for :list
* L<Net::Curl>: Perl interface to the all-mighty L<libcurl|http://curl.haxx.se/libcurl/>, is well-documented (opposite to L<WWW::Curl>);
* L<AnyEvent>: the L<DBI> of event loops. L<Net::Curl> also provides a nice and well-documented example of L<AnyEvent> usage (L<03-multi-event.pl|Net::Curl::examples/Multi::Event>);
* L<MooseX::NonMoose>: L<Net::Curl> uses a Pure-Perl object implementation, which is lightweight, but a bit messy for my L<Moose>-based projects. L<MooseX::NonMoose> patches this gap.

L<AnyEvent::Net::Curl::Queued> is a glue module to wrap it all together.
It offers no callbacks and (almost) no default handlers.
It's up to you to extend the base class L<AnyEvent::Net::Curl::Queued::Easy> so it will actually download something and store it somewhere.

=head2 ALTERNATIVES

As there's more than one way to do it, I'll list the alternatives which can be used to implement batch downloads:

=for :list
* L<WWW::Mechanize>: no (builtin) parallelism, no (builtin) queueing. Slow, but very powerful for site traversal;
* L<LWP::UserAgent>: no parallelism, no queueing. L<WWW::Mechanize> is built on top of LWP, by the way;
* L<LWP::Curl>: L<LWP::UserAgent>-alike interface for L<WWW::Curl>. No parallelism, no queueing. Fast and simple to use;
* L<HTTP::Tiny>: no parallelism, no queueing. Fast and part of CORE since Perl v5.13.9;
* L<HTTP::Lite>: no parallelism, no queueing. Also fast;
* L<Furl>: no parallelism, no queueing. B<Very> fast;
* L<AnyEvent::Curl::Multi>: queued parallel downloads via L<WWW::Curl>. Queues are non-lazy, thus large ones can use many RAM;
* L<Parallel::Downloader>: queued parallel downloads via L<AnyEvent::HTTP>. Very fast and is pure-Perl (compiling event driver is optional). You only access results when the whole batch is done; so huge batches will require lots of RAM to store contents.

=head2 BENCHMARK

Obviously, the bottleneck of any kind of download agent is the connection itself.
However, socket handling and header parsing add a lots of overhead.

The script F<eg/benchmark.pl> compares L<AnyEvent::Net::Curl::Queued> against several other download agents.
Only L<AnyEvent::Net::Curl::Queued> itself, L<AnyEvent::Curl::Multi>, L<Parallel::Downloader> and L<lftp|http://lftp.yar.ru/> support parallel connections natively;
thus, L<Parallel::ForkManager> is used to reproduce the same behaviour for the remaining agents.
Both L<AnyEvent::Curl::Multi> and L<LWP::Curl> are frontends for L<WWW::Curl>.
L<Parallel::Downloader> uses L<AnyEvent::HTTP> as it's backend.

The download target is a copy of the L<Apache documentation|http://httpd.apache.org/docs/2.2/> on a local Apache server.
The test platform configuration:

=for :list
* Intel® Core™ i7-2600 CPU @ 3.40GHz with 8 GB RAM;
* Ubuntu 11.10 (64-bit);
* Perl v5.16.2 (installed via L<perlbrew>);
* libcurl 7.26.0 (without AsynchDNS, which slows down L<curl_easy_init()|http://curl.haxx.se/libcurl/c/curl_easy_init.html>).

                              Request rate   W::M    LWP  AE::C::M  H::Lite  H::Tiny  P::D  YADA  lftp  Furl  wget  curl  L::Curl
    WWW::Mechanize v1.72             265/s     --   -61%      -86%     -86%     -87%  -90%  -91%  -91%  -95%  -96%  -97%     -97%
    LWP::UserAgent v6.04             674/s   154%     --      -63%     -64%     -67%  -75%  -77%  -78%  -88%  -89%  -91%     -91%
    AnyEvent::Curl::Multi v1.1      1850/s   596%   174%        --      -1%     -10%  -31%  -38%  -39%  -66%  -71%  -76%     -77%
    HTTP::Lite v2.4                 1860/s   601%   176%        1%       --      -9%  -31%  -38%  -39%  -66%  -71%  -76%     -77%
    HTTP::Tiny v0.017               2040/s   670%   203%       11%      10%       --  -24%  -31%  -33%  -63%  -68%  -74%     -74%
    Parallel::Downloader v0.121560  2680/s   909%   297%       45%      44%      31%    --  -10%  -12%  -51%  -58%  -65%     -66%
    YADA v0.025                     2980/s  1023%   342%       61%      60%      46%   11%    --   -2%  -45%  -53%  -61%     -62%
    lftp v4.3.1                     3030/s  1041%   349%       64%      63%      48%   13%    2%    --  -45%  -53%  -61%     -62%
    Furl v0.40                      5460/s  1959%   710%      196%     194%     168%  104%   83%   80%    --  -15%  -29%     -31%
    wget v1.12                      6400/s  2312%   849%      247%     244%     213%  139%  115%  111%   17%    --  -17%     -19%
    curl v7.26.0                    7720/s  2809%  1044%      318%     315%     278%  188%  159%  155%   41%   21%    --      -3%
    LWP::Curl v0.12                 7930/s  2890%  1076%      330%     327%     288%  196%  166%  162%   45%   24%    3%       --

=cut

use strict;
use utf8;
use warnings qw(all);

use AnyEvent;
use Any::Moose;
use Any::Moose qw(::Util::TypeConstraints);
use Net::Curl::Share;

use AnyEvent::Net::Curl::Queued::Multi;

# VERSION

=attr allow_dups

Allow duplicate requests (default: false).
By default, requests to the same URL (more precisely, requests with the same L<signature|AnyEvent::Net::Curl::Queued::Easy/sha> are issued only once.
To seed POST parameters, you must extend the L<AnyEvent::Net::Curl::Queued::Easy> class.
Setting C<allow_dups> to true value disables request checks.

=cut

has allow_dups  => (is => 'ro', isa => 'Bool', default => 0);

=attr completed

Count completed requests.

=cut

has completed  => (
    traits      => ['Counter'],
    is          => 'ro',
    isa         => 'Int',
    default     => 0,
    handles     => {qw{
        inc_completed inc
    }},
);

=attr cv

L<AnyEvent> condition variable.
Initialized automatically, unless you specify your own.
Also reset automatically after L</wait>, so keep your own reference if you really need it!

=cut

has cv          => (is => 'rw', isa => 'Ref | Undef', default => sub { AE::cv }, lazy => 1);

=attr max

Maximum number of parallel connections (default: 4; minimum value: 1).

=cut

subtype 'MaxConn'
    => as Int
    => where { $_ >= 1 };
has max         => (is => 'rw', isa => 'MaxConn', default => 4);

=attr multi

L<Net::Curl::Multi> instance.

=cut

has multi       => (is => 'rw', isa => 'AnyEvent::Net::Curl::Queued::Multi');

=attr queue

C<ArrayRef> to the queue.
Has the following helper methods:

=attr queue_push

Append item at the end of the queue.

=attr queue_unshift

Prepend item at the top of the queue.

=attr dequeue

Shift item from the top of the queue.

=attr count

Number of items in queue.

=cut

has queue       => (
    is          => 'ro',
    isa         => 'ArrayRef[Any]',
    default     => sub { [] },
);

# Mouse traits are utterly broken!!!

sub queue_push      { push @{shift->queue}, @_ }
sub queue_unshift   { unshift @{shift->queue}, @_ }
sub dequeue         { shift @{shift->queue} }
sub count           { scalar @{shift->queue} }

=attr share

L<Net::Curl::Share> instance.

=cut

has share       => (is => 'ro', isa => 'Net::Curl::Share', default => sub { Net::Curl::Share->new }, lazy => 1);

=attr stats

L<AnyEvent::Net::Curl::Queued::Stats> instance.

=cut

has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);

=attr timeout

Timeout (default: 60 seconds).

=cut

has timeout     => (is => 'ro', isa => 'Num', default => 60.0);

=attr unique

Signature cache.

=cut

has unique      => (is => 'rw', isa => 'HashRef[Str]', default => sub { {} });

=attr watchdog

The last resort against the non-deterministic chaos of evil lurking sockets.

=cut

has watchdog    => (is => 'rw', isa => 'Ref | Undef');

sub BUILD {
    my ($self) = @_;

    $self->multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            max         => $self->max,
            timeout     => $self->timeout,
        })
    );

    $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_COOKIE);   # 2
    $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_DNS);      # 3
    eval { $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_SSL_SESSION) };
}

=method start()

Populate empty request slots with workers from the queue.

=cut

sub start {
    my ($self) = @_;

    # watchdog
    $self->watchdog(AE::timer 1, 1, sub {
        $self->multi->perform;
        $self->empty;
    });

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
            $self->completed > 0
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
    if (not $self->allow_dups and not $worker->force) {
        return if ++$self->unique->{$worker->unique} > 1;
    }

    # fire
    $self->multi->add_handle($worker);
}

=method append($worker)

Put the worker (instance of L<AnyEvent::Net::Curl::Queued::Easy>) at the end of the queue.
For lazy initialization, wrap the worker in a C<sub { ... }>, the same way you do with the L<Moose> C<default =E<gt> sub { ... }>:

    $queue->append(sub {
        AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => 'http://.../' })
    });

=cut

sub append {
    my ($self, $worker) = @_;

    $self->queue_push($worker);
    $self->start;
}

=method prepend($worker)

Put the worker (instance of L<AnyEvent::Net::Curl::Queued::Easy>) at the beginning of the queue.
For lazy initialization, wrap the worker in a C<sub { ... }>, the same way you do with the L<Moose> C<default =E<gt> sub { ... }>:

    $queue->prepend(sub {
        AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => 'http://.../' })
    });

=cut

sub prepend {
    my ($self, $worker) = @_;

    $self->queue_unshift($worker);
    $self->start;
}

=method wait()

Process queue.

=cut

sub wait {
    my ($self) = @_;

    # handle queue
    $self->cv->recv;

    # stop the watchdog
    $self->watchdog(undef);

    # reload
    $self->cv(AE::cv);
    $self->multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            max         => $self->max,
            timeout     => $self->timeout,
        })
    );
}

=head1 CAVEAT

The I<"Attempt to free unreferenced scalar: SV 0xdeadbeef during global destruction."> message on finalization is mostly harmless.

=head1 SEE ALSO

=for :list
* L<AnyEvent>
* L<Any::Moose>
* L<Net::Curl>
* L<WWW::Curl>
* L<AnyEvent::Curl::Multi>

=cut

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
