package AnyEvent::Net::Curl::Queued;
# ABSTRACT: Moo wrapper for queued downloads via Net::Curl & AnyEvent

=head1 SYNOPSIS

    #!/usr/bin/env perl

    package CrawlApache;
    use feature qw(say);
    use strict;
    use utf8;
    use warnings qw(all);

    use HTML::LinkExtor;
    use Moo;

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
                    CrawlApache->new($link);
                });
            }
        }
    };

    1;

    package main;
    use strict;
    use utf8;
    use warnings qw(all);

    use AnyEvent::Net::Curl::Queued;

    my $q = AnyEvent::Net::Curl::Queued->new;
    $q->append(sub {
        CrawlApache->new('http://localhost/manual/')
    });
    $q->wait;

=head1 DESCRIPTION

B<AnyEvent::Net::Curl::Queued> (a.k.a. L<YADA>, I<Yet Another Download Accelerator>) is an efficient and flexible batch downloader with a straight-forward interface capable of:

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
* L<AnyEvent>: the L<DBI> of event loops. L<Net::Curl> also provides a nice and well-documented example of L<AnyEvent> usage (L<03-multi-event.pl|Net::Curl::examples/Multi::Event>).

L<AnyEvent::Net::Curl::Queued> is a glue module to wrap it all together.
It offers no callbacks and (almost) no default handlers.
It's up to you to extend the base class L<AnyEvent::Net::Curl::Queued::Easy> so it will actually download something and store it somewhere.

=head2 ALTERNATIVES

As there's more than one way to do it, I'll list the alternatives which can be used to implement batch downloads:

=for :list
* L<WWW::Mechanize>: no (builtin) parallelism, no (builtin) queueing. Slow, but very powerful for site traversal;
* L<LWP::UserAgent>: no parallelism, no queueing. L<WWW::Mechanize> is built on top of LWP, by the way;
* L<LWP::Protocol::Net::Curl>: I<drop-in> replacement for L<LWP::UserAgent>, L<WWW::Mechanize> and their derivatives to use L<Net::Curl> as a backend;
* L<LWP::Curl>: L<LWP::UserAgent>-alike interface for L<WWW::Curl>. Not a I<drop-in>, no parallelism, no queueing. Fast and simple to use;
* L<HTTP::Tiny>: no parallelism, no queueing. Fast and part of CORE since Perl v5.13.9;
* L<HTTP::Lite>: no parallelism, no queueing. Also fast;
* L<Furl>: no parallelism, no queueing. B<Very> fast, despite being pure-Perl;
* L<Mojo::UserAgent>: capable of non-blocking parallel requests, no queueing;
* L<AnyEvent::Curl::Multi>: queued parallel downloads via L<WWW::Curl>. Queues are non-lazy, thus large ones can use many RAM;
* L<Parallel::Downloader>: queued parallel downloads via L<AnyEvent::HTTP>. Very fast and is pure-Perl (compiling event driver is optional). You only access results when the whole batch is done; so huge batches will require lots of RAM to store contents.

=head2 BENCHMARK

(see also: L<CPAN modules for making HTTP requests|http://neilb.org/reviews/http-requesters.html>)

Obviously, every download agent is (or, ideally, should be) I<I/O bound>.
However, it is not uncommon for large concurrent batch downloads to hog the processor cycles B<before> consuming the full network bandwidth.
The proposed benchmark measures the request rate of several concurrent download agents, trying hard to make all of them I<CPU bound> (by removing the I/O constraint).
On practice, this benchmark results mean that download agents with lower request rate are less appropriate for parallelized batch downloads.
On the other hand, download agents with higher request rate are more likely to reach the full capacity of a network link while still leaving spare resources for data parsing/filtering.

The script F<eg/benchmark.pl> compares L<AnyEvent::Net::Curl::Queued> (A.K.A. L<YADA>) against several other download agents.
Only L<AnyEvent::Net::Curl::Queued> itself, L<AnyEvent::Curl::Multi>, L<Parallel::Downloader>, L<Mojo::UserAgent> and L<lftp|http://lftp.yar.ru/> support concurrent downloads natively;
thus, L<Parallel::ForkManager> is used to reproduce the same behaviour for the remaining agents, while L<taskset|http://linux.die.net/man/1/taskset> avoids the skew on multiprocessor systems.

The download target is a copy of the L<Apache documentation|http://httpd.apache.org/docs/2.2/> on a local Apache server.
The test platform configuration:

=for :list
* Intel® Core™ i7-2600 CPU @ 3.40GHz with 8 GB RAM;
* Ubuntu 11.10 (64-bit);
* Perl v5.16.2 (installed via L<perlbrew>);
* libcurl/7.28.0 (without AsynchDNS, which slows down L<curl_easy_init()|http://curl.haxx.se/libcurl/c/curl_easy_init.html>).

The script F<eg/benchmark.pl> uses L<Benchmark::Forking> and L<Class::Load> to keep UA modules isolated and loaded only once.

    $ taskset 1 perl benchmark.pl --count 100 --parallel 8 --repeat 10

                              Request rate WWW::M LWP::UA L::P::N::C Mojo::UA HTTP::L HTTP::T lftp P::D AE::C::M YADA Furl curl wget LWP::C
    WWW::Mechanize v1.72             534/s     --    -32%       -61%     -63%    -80%    -82% -83% -84%     -85% -86% -94% -95% -97%   -97%
    LWP::UserAgent v6.04             782/s    46%      --       -42%     -46%    -71%    -73% -75% -76%     -77% -79% -92% -93% -95%   -95%
    LWP::Protocol::Net::Curl v0.011 1360/s   154%     74%         --      -6%    -50%    -53% -57% -59%     -61% -64% -86% -88% -91%   -91%
    Mojo::UserAgent v3.82           1450/s   171%     85%         7%       --    -46%    -50% -54% -56%     -58% -62% -85% -87% -91%   -91%
    HTTP::Lite v2.4                 2700/s   405%    245%        98%      86%      --     -7% -14% -18%     -22% -29% -71% -76% -82%   -83%
    HTTP::Tiny v0.025               2910/s   445%    272%       114%     101%      8%      --  -7% -11%     -16% -23% -69% -74% -81%   -81%
    lftp v4.3.1                     3140/s   488%    302%       131%     117%     17%      8%   --  -4%      -9% -17% -67% -72% -80%   -80%
    Parallel::Downloader v0.121560  3280/s   514%    319%       141%     127%     22%     13%   4%   --      -5% -13% -65% -70% -79%   -79%
    AnyEvent::Curl::Multi v1.1      3460/s   548%    342%       155%     139%     28%     19%  10%   5%       --  -9% -63% -69% -77%   -78%
    YADA v0.038                     3790/s   610%    385%       179%     162%     41%     30%  21%  16%      10%   -- -60% -66% -75%   -76%
    Furl v2.01                      9420/s  1663%   1104%       593%     550%    249%    223% 200% 187%     172% 148%   -- -15% -39%   -40%
    curl v7.28.0                   11100/s  1977%   1318%       716%     666%    311%    281% 253% 238%     221% 193%  18%   -- -28%   -29%
    wget v1.12                     15400/s  2777%   1864%      1031%     961%    470%    428% 389% 368%     344% 305%  63%  39%   --    -1%
    LWP::Curl v0.12                15600/s  2818%   1892%      1047%     976%    478%    435% 396% 375%     350% 311%  65%  40%   1%     --

    (output formatted to show module versions at row labels and keep column labels abbreviated)

=cut

use strict;
use utf8;
use warnings qw(all);

use AnyEvent;
use Carp qw(confess);
use Moo;
use MooX::Types::MooseLike::Base qw(
    ArrayRef
    Bool
    HashRef
    InstanceOf
    Int
    Num
    Object
    Str
    is_Int
);
use Net::Curl::Share;

use AnyEvent::Net::Curl::Queued::Multi;

# VERSION

=attr allow_dups

Allow duplicate requests (default: false).
By default, requests to the same URL (more precisely, requests with the same L<signature|AnyEvent::Net::Curl::Queued::Easy/sha> are issued only once.
To seed POST parameters, you must extend the L<AnyEvent::Net::Curl::Queued::Easy> class.
Setting C<allow_dups> to true value disables request checks.

=cut

has allow_dups  => (is => 'ro', isa => Bool, default => sub { 0 });

=attr common_opts

L<AnyEvent::Net::Curl::Queued::Easy/opts> attribute common to all workers initialized under the same queue.
You may define C<User-Agent> string here.

=cut

has common_opts => (is => 'ro', isa => HashRef, default => sub { {} });

=attr http_response

Encapsulate the response with L<HTTP::Response> (only when the scheme is HTTP/HTTPS); a global version of L<AnyEvent::Net::Curl::Queued::Easy/http_response>.
Default: disabled.

=cut

has http_response => (is => 'ro', isa => Bool, default => sub { 0 });

=attr completed

Count completed requests.

=method inc_completed

Increment the L</completed> counter.

=cut

has completed  => (
    is          => 'ro',
    isa         => Int,
    default     => sub { 0 },
    writer      => 'set_completed',
);

sub inc_completed {
    my ($self) = @_;
    return $self->set_completed($self->completed + 1);
}

=attr cv

L<AnyEvent> condition variable.
Initialized automatically, unless you specify your own.
Also reset automatically after L</wait>, so keep your own reference if you really need it!

=cut

has cv          => (is => 'ro', isa => Object, default => sub { AE::cv }, lazy => 1, writer => 'set_cv');

=attr max

Maximum number of parallel connections (default: 4; minimum value: 1).

=cut

has max         => (
    is          => 'rw',
    isa         => Int,
    coerce      => sub {
        confess 'At least 1 connection required'
            if not is_Int($_[0])
            or $_[0] < 1;
        return $_[0];
    },
    default     => sub { 4 },
);

=attr multi

L<Net::Curl::Multi> instance.

=cut

has multi       => (is => 'ro', isa => InstanceOf['AnyEvent::Net::Curl::Queued::Multi'], writer => 'set_multi');

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
    isa         => ArrayRef[Object],
    default     => sub { [] },
);

## no critic (RequireArgUnpacking)

sub queue_push      { return 0 + push @{shift->queue}, @_ }
sub queue_unshift   { return 0 + unshift @{shift->queue}, @_ }
sub dequeue         { return shift @{shift->queue} }
sub count           { return 0 + @{shift->queue} }

=attr share

L<Net::Curl::Share> instance.

=cut

has share       => (
    is      => 'ro',
    isa     => InstanceOf['Net::Curl::Share'],
    default => sub { Net::Curl::Share->new({ stamp => time }) },
    lazy    => 1,
);

=attr stats

L<AnyEvent::Net::Curl::Queued::Stats> instance.

=cut

has stats       => (is => 'ro', isa => InstanceOf['AnyEvent::Net::Curl::Queued::Stats'], default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);

=attr timeout

Timeout (default: 60 seconds).

=cut

has timeout     => (is => 'ro', isa => Num, default => sub { 60.0 });

=attr unique

Signature cache.

=cut

has unique      => (is => 'ro', isa => HashRef[Str], default => sub { {} });

=attr watchdog

The last resort against the non-deterministic chaos of evil lurking sockets.

=cut

has watchdog    => (is => 'ro', isa => Object, writer => 'set_watchdog', clearer => 'clear_watchdog', predicate => 'has_watchdog');

=for Pod::Coverage
BUILD
BUILDARGS
=cut

sub BUILD {
    my ($self) = @_;

    $self->set_multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            max         => $self->max,
            timeout     => $self->timeout,
        })
    );

    $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_COOKIE);   # 2
    $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_DNS);      # 3

    ## no critic (RequireCheckingReturnValueOfEval)
    eval { $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_SSL_SESSION) };

    return;
}

sub BUILDARGS {
    my $class = shift;
    if (@_ == 1 and q(HASH) eq ref $_[0]) {
        return shift;
    } elsif (@_ % 2 == 0) {
        return { @_ };
    } elsif (@_ == 1) {
        return { max => shift };
    } else {
        confess 'Should be initialized as ' . $class . '->new(Hash|HashRef|Int)';
    }
}

=method start()

Populate empty request slots with workers from the queue.

=cut

sub start {
    my ($self) = @_;

    # watchdog
    $self->set_watchdog(AE::timer 1, 1, sub {
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

    return;
}

=method empty()

Check if there are active requests or requests in queue.

=cut

sub empty {
    my ($self) = @_;

    AE::postpone { $self->cv->send }
        if
            $self->completed > 0
            and $self->count == 0
            and $self->multi->handles == 0;

    return;
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
    if ($self->allow_dups
        or $worker->force
        or ++$self->unique->{$worker->unique} == 1
    ) {
        # fire
        $self->multi->add_handle($worker);
    }

    return;
}

=method append($worker)

Put the worker (instance of L<AnyEvent::Net::Curl::Queued::Easy>) at the end of the queue.
For lazy initialization, wrap the worker in a C<sub { ... }>, the same way you do with the L<Moo> C<default =E<gt> sub { ... }>:

    $queue->append(sub {
        AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => 'http://.../' })
    });

=cut

sub append {
    my ($self, $worker) = @_;

    $self->queue_push($worker);
    $self->start;

    return;
}

=method prepend($worker)

Put the worker (instance of L<AnyEvent::Net::Curl::Queued::Easy>) at the beginning of the queue.
For lazy initialization, wrap the worker in a C<sub { ... }>, the same way you do with the L<Moo> C<default =E<gt> sub { ... }>:

    $queue->prepend(sub {
        AnyEvent::Net::Curl::Queued::Easy->new({ initial_url => 'http://.../' })
    });

=cut

sub prepend {
    my ($self, $worker) = @_;

    $self->queue_unshift($worker);
    $self->start;

    return;
}

=method wait()

Process queue.

=cut

## no critic (ProhibitBuiltinHomonyms)
sub wait {
    my ($self) = @_;

    # handle queue
    $self->cv->recv;

    # stop the watchdog
    $self->clear_watchdog;

    # reload
    $self->set_cv(AE::cv);

    return;
}

=head1 CAVEAT

=for :list
* Many sources suggest to compile L<libcurl|http://curl.haxx.se/> with L<c-ares|http://c-ares.haxx.se/> support. This only improves performance if you are supposed to do many DNS resolutions (e.g. access many hosts). If you are fetching many documents from a single server, C<c-ares> initialization will actually slow down the whole process!

=head1 SEE ALSO

=for :list
* L<AnyEvent>
* L<Moo>
* L<Net::Curl>
* L<WWW::Curl>
* L<AnyEvent::Curl::Multi>

=cut

1;
