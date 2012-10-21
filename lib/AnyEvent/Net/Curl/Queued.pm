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
* L<LWP::Curl>: L<LWP::UserAgent>-alike interface for L<WWW::Curl>. No parallelism, no queueing. Fast and simple to use;
* L<HTTP::Tiny>: no parallelism, no queueing. Fast and part of CORE since Perl v5.13.9;
* L<HTTP::Lite>: no parallelism, no queueing. Also fast;
* L<Furl>: no parallelism, no queueing. B<Very> fast;
* L<Mojo::UserAgent>: capable of non-blocking parallel requests, no queueing;
* L<AnyEvent::Curl::Multi>: queued parallel downloads via L<WWW::Curl>. Queues are non-lazy, thus large ones can use many RAM;
* L<Parallel::Downloader>: queued parallel downloads via L<AnyEvent::HTTP>. Very fast and is pure-Perl (compiling event driver is optional). You only access results when the whole batch is done; so huge batches will require lots of RAM to store contents.

=head2 BENCHMARK

(see also: L<CPAN modules for making HTTP requests|http://neilb.org/reviews/http-requesters.html>)

Obviously, the bottleneck of any kind of download agent is the connection itself.
However, socket handling and header parsing add a lots of overhead.

The script F<eg/benchmark.pl> compares L<AnyEvent::Net::Curl::Queued> against several other download agents.
Only L<AnyEvent::Net::Curl::Queued> itself, L<AnyEvent::Curl::Multi>, L<Parallel::Downloader>, L<Mojo::UserAgent> and L<lftp|http://lftp.yar.ru/> support parallel connections natively;
thus, L<Parallel::ForkManager> is used to reproduce the same behaviour for the remaining agents.
Both L<AnyEvent::Curl::Multi> and L<LWP::Curl> are frontends for L<WWW::Curl>.
L<Parallel::Downloader> uses L<AnyEvent::HTTP> as it's backend.

The download target is a copy of the L<Apache documentation|http://httpd.apache.org/docs/2.2/> on a local Apache server.
The test platform configuration:

=for :list
* Intel® Core™ i7-2600 CPU @ 3.40GHz with 8 GB RAM;
* Ubuntu 11.10 (64-bit);
* Perl v5.16.1 (installed via L<perlbrew>);
* libcurl 7.27.0 (without AsynchDNS, which slows down L<curl_easy_init()|http://curl.haxx.se/libcurl/c/curl_easy_init.html>).

The script F<eg/benchmark.pl> uses L<Benchmark::Forking> and L<Class::Load> to keep UA modules isolated and loaded only once.

    $ perl benchmark.pl --count 100 --parallel 4 --repeat 5

                             Request rate WWW::M LWP::UA Mojo::UA HTTP::Tiny HTTP::Lite AE::C::M P::D lftp YADA Furl wget curl LWP::Curl
    WWW::Mechanize v1.72            303/s     --    -65%     -80%       -82%       -85%     -86% -91% -91% -93% -95% -96% -96%      -97%
    LWP::UserAgent v6.04            873/s   187%      --     -44%       -48%       -58%     -60% -74% -74% -79% -87% -89% -89%      -90%
    Mojo::UserAgent v3.39          1558/s   412%     78%       --        -7%       -24%     -29% -54% -54% -63% -76% -80% -80%      -82%
    HTTP::Tiny v0.017              1672/s   451%     92%       8%         --       -19%     -24% -51% -51% -60% -74% -79% -79%      -81%
    HTTP::Lite v2.4                2058/s   577%    136%      32%        23%         --      -6% -39% -39% -51% -68% -74% -74%      -77%
    AnyEvent::Curl::Multi v1.1     2203/s   624%    152%      41%        31%         7%       -- -35% -35% -47% -66% -72% -72%      -75%
    Parallel::Downloader v0.121560 3378/s  1015%    288%     118%       102%        65%      54%   --  -0% -19% -48% -57% -57%      -61%
    lftp v4.3.1                    3401/s  1018%    289%     118%       103%        65%      55%   0%   -- -19% -48% -57% -57%      -61%
    YADA v0.027                    4167/s  1276%    379%     169%       150%       103%      90%  23%  23%   -- -36% -47% -47%      -52%
    Furl v0.40                     6502/s  2041%    645%     318%       288%       216%     196%  92%  91%  56%   -- -17% -18%      -26%
    wget v1.12                     7874/s  2493%    803%     406%       371%       283%     258% 133% 132%  88%  21%   --  -0%      -10%
    curl v7.27.0                   7899/s  2501%    806%     408%       372%       284%     260% 133% 133%  89%  22%   0%   --      -10%
    LWP::Curl v0.12                8757/s  2780%    902%     462%       423%       326%     298% 158% 158% 109%  35%  11%  11%        --

    (output formatted to show module versions at row labels and keep column labels abbreviated)

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

our %share; # PLEASE, MAKE IT STOP!!! IT HURTS MY BRAIN!!!
has share       => (
    is      => 'ro',
    isa     => 'Net::Curl::Share',
    default => sub {
        my $share = Net::Curl::Share->new;
        $share{$share} = $share;
    },
    lazy    => 1,
    weak_ref=> 1,
);

#sub DEMOLISH {
#    # Y U NO DEFINED HERE?!?!
#    delete $share{$_[0]->share};
#}

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
