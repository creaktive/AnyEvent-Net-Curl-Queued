package AnyEvent::Net::Curl::Queued;
# ABSTRACT: Any::Moose wrapper for queued downloads via Net::Curl & AnyEvent

=head1 SYNOPSIS

    #!/usr/bin/env perl

    package CrawlApache;
    use feature qw(say);
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
                    CrawlApache->new($link);
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

The script F<eg/benchmark.pl> compares L<AnyEvent::Net::Curl::Queued> against several other download agents.
Only L<AnyEvent::Net::Curl::Queued> itself, L<AnyEvent::Curl::Multi>, L<Parallel::Downloader>, L<Mojo::UserAgent> and L<lftp|http://lftp.yar.ru/> support concurrent downloads natively;
thus, L<Parallel::ForkManager> is used to reproduce the same behaviour for the remaining agents.

The download target is a copy of the L<Apache documentation|http://httpd.apache.org/docs/2.2/> on a local Apache server.
The test platform configuration:

=for :list
* Intel® Core™ i7-2600 CPU @ 3.40GHz with 8 GB RAM;
* Ubuntu 11.10 (64-bit);
* Perl v5.16.2 (installed via L<perlbrew>);
* libcurl/7.28.0 (without AsynchDNS, which slows down L<curl_easy_init()|http://curl.haxx.se/libcurl/c/curl_easy_init.html>).

The script F<eg/benchmark.pl> uses L<Benchmark::Forking> and L<Class::Load> to keep UA modules isolated and loaded only once.

    $ perl benchmark.pl --count 100 --parallel 8 --repeat 10

                             Request rate WWW::M LWP::UA Mojo::UA HTTP::Lite HTTP::Tiny AE::C::M lftp P::D YADA Furl curl wget LWP::Curl
    WWW::Mechanize v1.72            231/s     --    -59%     -85%       -87%       -89%     -90% -93% -93% -94% -97% -98% -98%      -98%
    LWP::UserAgent v6.04            567/s   145%      --     -64%       -68%       -72%     -77% -82% -83% -85% -92% -94% -95%      -96%
    Mojo::UserAgent v3.54          1590/s   589%    181%       --       -10%       -22%     -34% -49% -53% -59% -76% -83% -87%      -88%
    HTTP::Lite v2.4                1770/s   666%    213%      11%         --       -13%     -27% -44% -48% -54% -74% -81% -85%      -86%
    HTTP::Tiny v0.024              2030/s   779%    259%      28%        15%         --     -16% -36% -40% -48% -70% -78% -83%      -84%
    AnyEvent::Curl::Multi v1.1     2430/s   952%    329%      53%        37%        20%       -- -23% -29% -37% -64% -74% -80%      -81%
    lftp v4.3.1                    3150/s  1262%    456%      98%        78%        55%      30%   --  -8% -19% -53% -66% -74%      -75%
    Parallel::Downloader v0.121560 3410/s  1375%    502%     114%        92%        68%      40%   8%   -- -12% -49% -64% -72%      -73%
    YADA v0.036                    3880/s  1579%    585%     144%       119%        91%      60%  23%  14%   -- -42% -59% -68%      -70%
    Furl v1.00                     6700/s  2795%   1082%     320%       278%       229%     175% 113%  96%  72%   -- -29% -45%      -48%
    curl v7.28.0                   9380/s  3953%   1554%     488%       429%       361%     285% 197% 175% 141%  40%   -- -23%      -27%
    wget v1.12                    12100/s  5139%   2038%     661%       584%       496%     398% 285% 255% 212%  81%  29%   --       -5%
    LWP::Curl v0.12               12800/s  5418%   2152%     701%       620%       528%     425% 305% 274% 229%  91%  36%   5%        --

    (output formatted to show module versions at row labels and keep column labels abbreviated)

=cut

use strict;
use utf8;
use warnings qw(all);

use AnyEvent;
use Any::Moose;
use Any::Moose qw(::Util::TypeConstraints);
use Carp qw(confess);
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

=attr common_opts

L<AnyEvent::Net::Curl::Queued::Easy/opts> attribute common to all workers initialized under the same queue.
You may define C<User-Agent> string here.

=cut

has common_opts => (is => 'ro', isa => 'HashRef', default => sub { {} });

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

has cv          => (is => 'ro', isa => 'Maybe[Ref]', default => sub { AE::cv }, lazy => 1, writer => 'set_cv');

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

has multi       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Multi', writer => 'set_multi');

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

has share       => (
    is      => 'ro',
    isa     => 'Net::Curl::Share',
    default => sub { Net::Curl::Share->new({ stamp => time }) },
    lazy    => 1,
);

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

has unique      => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

=attr watchdog

The last resort against the non-deterministic chaos of evil lurking sockets.

=cut

has watchdog    => (is => 'ro', isa => 'Maybe[Ref]', writer => 'set_watchdog', clearer => 'clear_watchdog', predicate => 'has_watchdog');

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
    eval { $self->share->setopt(Net::Curl::Share::CURLSHOPT_SHARE, Net::Curl::Share::CURL_LOCK_DATA_SSL_SESSION) };
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
    if (
        $self->allow_dups
        or $worker->force
        or ++$self->unique->{$worker->unique} == 1
    ) {
        # fire
        $self->multi->add_handle($worker);
    }
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
    $self->clear_watchdog;

    # reload
    $self->set_cv(AE::cv);
    $self->set_multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            max         => $self->max,
            timeout     => $self->timeout,
        })
    );
}

=head1 CAVEAT

=for :list
* Many sources suggest to compile L<libcurl|http://curl.haxx.se/> with L<c-ares|http://c-ares.haxx.se/> support. This only improves performance if you are supposed to do many DNS resolutions (e.g. access many hosts). If you are fetching many documents from a single server, C<c-ares> initialization will actually slow down the whole process!

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
