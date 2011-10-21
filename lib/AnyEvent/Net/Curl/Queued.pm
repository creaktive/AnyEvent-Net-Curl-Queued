package AnyEvent::Net::Curl::Queued;
# ABSTRACT: Moose wrapper for queued downloads via Net::Curl & AnyEvent

=head1 SYNOPSIS

    #!/usr/bin/env perl

    package CrawlApache;
    use common::sense;

    use HTML::LinkExtor;
    use Moose;

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

    no Moose;
    __PACKAGE__->meta->make_immutable;

    1;

    package main;
    use common::sense;

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

=head2 OVERHEAD

Obviously, the bottleneck of any kind of download agent is the connection itself.
However, socket handling and header parsing add a lots of overhead.
The script F<eg/benchmark.pl> compares L<AnyEvent::Net::Curl::Queued> against several other download agents.
Only L<AnyEvent::Net::Curl::Queued> itself, L<AnyEvent::Curl::Multi> and L<lftp|http://lftp.yar.ru/> support parallel connections;
thus, L<forks|AnyEvent::Util/fork_call> are used to reproduce the same behaviour for the remaining agents.
Both L<AnyEvent::Curl::Multi> and L<LWP::Curl> are frontends for L<WWW::Curl>.
The download target is a local copy of the L<Apache documentation|http://httpd.apache.org/docs/2.2/>.

                                 URL/s WWW::Mechanize LWP::UserAgent HTTP::Lite AnyEvent::Net::Curl::Queued HTTP::Tiny AnyEvent::Curl::Multi  lftp AnyEvent::HTTP  curl LWP::Curl  wget
    WWW::Mechanize                 198             --           -60%       -80%                        -84%       -85%                  -86%  -88%           -92%  -97%      -97% -100%
    LWP::UserAgent                 493           148%             --       -51%                        -59%       -63%                  -65%  -69%           -80%  -93%      -93% -100%
    HTTP::Lite                    1004           406%           104%         --                        -17%       -24%                  -29%  -37%           -59%  -85%      -86%  -99%
    AnyEvent::Net::Curl::Queued   1213           511%           146%        21%                          --        -8%                  -14%  -24%           -51%  -82%      -83%  -99%
    HTTP::Tiny                    1324           567%           168%        32%                          9%         --                   -6%  -17%           -46%  -80%      -82%  -99%
    AnyEvent::Curl::Multi         1410           610%           186%        40%                         16%         6%                    --  -12%           -43%  -79%      -81%  -99%
    lftp                          1603           708%           225%        60%                         32%        21%                   14%    --           -35%  -76%      -78%  -98%
    AnyEvent::HTTP                2458          1136%           398%       144%                        102%        85%                   74%   53%             --  -63%      -66%  -98%
    curl                          6613          3237%          1243%       560%                        446%       400%                  370%  313%           170%    --       -9%  -93%
    LWP::Curl                     7355          3587%          1384%       629%                        503%       453%                  419%  356%           198%   10%        --  -93%
    wget                        100376         50428%         20241%      9892%                       8167%      7476%                 7020% 6156%          3987% 1414%     1271%    --

L<AnyEvent::Curl::Multi> really has less overhead at the cost of very primitive queue manager
(no retries and large queues waste too much RAM due to lack of lazy initialization).

=cut

use common::sense;

use AnyEvent;
use Moose;
use Moose::Util::TypeConstraints;
use Net::Curl::Share;

use AnyEvent::Net::Curl::Queued::Multi;

# VERSION

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

=cut

has cv          => (is => 'ro', isa => 'AnyEvent::CondVar', default => sub { AE::cv }, lazy => 1);

=attr max

Maximum number of parallel connections (default: 4; minimum value: 1).

=cut

subtype 'MaxConn'
    => as Int
    => where { $_ >= 1 };
has max         => (is => 'ro', isa => 'MaxConn', default => 4);

=attr multi

L<Net::Curl::Multi> instance.

=cut

has multi       => (is => 'rw', isa => 'AnyEvent::Net::Curl::Queued::Multi');

=attr queue

C<ArrayRef> to the queue.
Has the following helper methods:

=for :list
* queue_push: append item at the end of the queue;
* queue_unshift: prepend item at the top of the queue;
* dequeue: shift item from the top of the queue;
* count: number of items in queue.

=cut

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

=attr share

L<Net::Curl::Share> instance.

=cut

has share       => (is => 'ro', isa => 'Net::Curl::Share', default => sub { Net::Curl::Share->new }, lazy => 1);

=attr stats

L<AnyEvent::Net::Curl::Queued::Stats> instance.

=cut

has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);

=attr timeout

Timeout (default: 10 seconds).

=cut

has timeout     => (is => 'ro', isa => 'Num', default => 10.0);

=attr unique

C<HashRef> to store request unique identifiers to prevent repeated accesses.

=cut

has unique      => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

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
}

=method start()

Populate empty request slots with workers from the queue.

=cut

sub start {
    my ($self) = @_;

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
    if (my $unique = $worker->unique) {
        return if ++$self->unique->{$unique} > 1;
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

Shortcut to C<$queue-E<gt>cv-E<gt>recv>.

=cut

sub wait {
    my ($self) = @_;

    $self->cv->recv;
}

=head1 SEE ALSO

=for :list
* L<AnyEvent>
* L<Moose>
* L<Net::Curl>
* L<WWW::Curl>
* L<AnyEvent::Curl::Multi>

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;
