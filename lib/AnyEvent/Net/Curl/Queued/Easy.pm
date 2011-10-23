package AnyEvent::Net::Curl::Queued::Easy;
# ABSTRACT: Net::Curl::Easy wrapped by Moose

=head1 SYNOPSIS

    package MyIEDownloader;
    use common::sense;

    use Moose;
    use Net::Curl::Easy qw(/^CURLOPT_/);

    extends 'AnyEvent::Net::Curl::Queued::Easy';

    after init => sub {
        my ($self) = @_;

        $self->setopt(CURLOPT_ENCODING,         '');
        $self->setopt(CURLOPT_FOLLOWLOCATION,   1);
        $self->setopt(CURLOPT_USERAGENT,        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)');
        $self->setopt(CURLOPT_VERBOSE,          1);
    };

    after finish => sub {
        my ($self, $result) = @_;

        if ($self->has_error) {
            printf "error downloading %s: %s\n", $self->final_url, $result;
        } else {
            printf "finished downloading %s: %d bytes\n", $self->final_url, length ${$self->data};
        }
    };

    around has_error => sub {
        my $orig = shift;
        my $self = shift;

        return 1 if $self->$orig(@_);
        return 1 if $self->getinfo(Net::Curl::Easy::CURLINFO_RESPONSE_CODE) =~ m{^5[0-9]{2}$};
    };

    no Moose;
    __PACKAGE__->meta->make_immutable;

    1;

=head1 DESCRIPTION

The class you should overload to fetch stuff your own way.

=cut

use common::sense;

use Carp qw(carp confess);
use Digest::SHA;
use HTTP::Response;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::NonMoose;
use URI;

extends 'Net::Curl::Easy';

use AnyEvent::Net::Curl::Const;
use AnyEvent::Net::Curl::Queued::Stats;

# VERSION

subtype 'AnyEvent::Net::Curl::Queued::Easy::URI'
    => as class_type('URI');

coerce 'AnyEvent::Net::Curl::Queued::Easy::URI'
    => from 'Any'
        => via { URI->new("$_") }
    => from 'URI'
        => via { $_ };

=attr curl_result

libcurl return code (C<Net::Curl::Easy::Code>).

=cut

has curl_result => (is => 'rw', isa => 'Net::Curl::Easy::Code');

=attr data

Receive buffer.

=cut

has data        => (is => 'rw', isa => 'Ref');

=attr header

Header buffer.

=cut

has header      => (is => 'rw', isa => 'Ref');

=attr http_response

Optionally encapsulate the response in L<HTTP::Response>.

=cut

has http_response => (is => 'ro', isa => 'Bool', default => 0);

=attr initial_url

URL to fetch (string).

=cut

has initial_url => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Easy::URI', coerce => 1, required => 1);

=attr final_url

Final URL (after redirections).

=cut

has final_url   => (is => 'rw', isa => 'AnyEvent::Net::Curl::Queued::Easy::URI', coerce => 1);

=attr queue

L<AnyEvent::Net::Curl::Queued> circular reference.

=cut

has queue       => (is => 'rw', isa => 'Ref', weak_ref => 1);

=attr sha

Uniqueness detection helper.
Setup via C<sign> and access through C<unique>.

=cut

has sha         => (is => 'ro', isa => 'Digest::SHA', default => sub { new Digest::SHA(256) }, lazy => 1);

=attr res

Encapsulated L<HTTP::Response> instance, if L</http_response> was set.

=cut

has res         => (is => 'rw', isa => 'HTTP::Response');

=attr retry

Number of retries (default: 5).

=cut

has retry       => (is => 'rw', isa => 'Int', default => 5);

=attr stats

L<AnyEvent::Net::Curl::Queued::Stats> instance.

=attr use_stats

Set to true to enable stats computation.
Note that extracting C<libcurl> time/size data degrades performance slightly.

=cut

has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);
has use_stats   => (is => 'ro', isa => 'Bool', default => 0);

=attr on_init

Callback you can define instead of extending the C<init> method.
Almost the same as C<after init =E<gt> sub { ... }>

=attr on_finish

Callback you can define instead of extending the C<finish> method.
Almost the same as C<after finish =E<gt> sub { ... }>

=cut

has [qw(on_init on_finish)] => (is => 'ro', isa => 'CodeRef');

=method unique()

Returns the unique signature of the request.
By default, the signature is derived from L<Digest::SHA> of the C<initial_url>.

=cut

sub unique {
    my ($self) = @_;

    # make URL-friendly Base64
    my $digest = $self->sha->clone->b64digest;
    $digest =~ tr{+/}{-_};

    # return the signature
    return $digest;
}

=method sign($str)

Use C<$str> to compute the C<unique> value.
Useful to successfully enqueue POST parameters.

=cut

sub sign {
    my ($self, $str) = @_;

    # add entropy to the signature
    $self->sha->add($str);
}

=method init()

Initialize the instance.
We can't use the default C<BUILD> method as we need the initialization to be done B<after> the instance is in the queue.

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub init {
    my ($self) = @_;

    # fragment mangling
    my $url = $self->initial_url->clone;
    $url->fragment(undef);
    $self->setopt(Net::Curl::Easy::CURLOPT_URL,         $url->as_string);

    # salt
    $self->sign(($self->meta->class_precedence_list)[0]);
    # URL; GET parameters included
    $self->sign($url->as_string);

    # common parameters
    if ($self->queue) {
        $self->setopt(Net::Curl::Easy::CURLOPT_SHARE,   $self->queue->share);
        $self->setopt(Net::Curl::Easy::CURLOPT_TIMEOUT, $self->queue->timeout);
    }

    # buffers
    my $data;
    $self->setopt(Net::Curl::Easy::CURLOPT_WRITEDATA,   \$data);
    $self->data(\$data);

    my $header;
    $self->setopt(Net::Curl::Easy::CURLOPT_WRITEHEADER, \$header);
    $self->header(\$header);

    # call the optional callback
    $self->on_init->(@_) if ref($self->on_init) eq 'CODE';
}

=method has_error()

Error handling: if C<has_error> returns true, the request is re-enqueued (until the retries number is exhausted).

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub has_error {
    my ($self) = @_;

    # very bad error
    return ($self->curl_result == Net::Curl::Easy::CURLE_OK) ? 0 : 1;
}

=method finish($result)

Called when the download is finished.
C<$result> holds the C<Net::Curl::Easy::Code>.

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.

=cut

sub _finish {
    my ($self, $result) = @_;

    # populate results
    $self->curl_result($result);
    $self->final_url($self->getinfo(Net::Curl::Easy::CURLINFO_EFFECTIVE_URL));

    # optionally encapsulate with HTTP::Response
    if ($self->http_response) {
        $self->res(
            HTTP::Response->parse(
                (${$self->header} // "\n")
                . (${$self->data} // '')
            )
        );

        if (my $msg = $self->res->message) {
            $msg =~ s/^\s+//s;
            $msg =~ s/\s+$//s;
            $self->res->message($msg);
        }
    }

    # wrap around the extendible interface
    $self->finish($result);

    # re-enqueue the request
    if ($self->has_error and $self->retry > 1) {
        $self->queue->unique->{$self->unique} = 0;
        $self->queue->queue_push($self->clone);
    }

    # update stats
    if ($self->use_stats) {
        $self->stats->sum($self);
        $self->queue->stats->sum($self);
    }

    # request completed (even if returned error!)
    $self->queue->inc_completed;

    # move queue
    $self->queue->start;
}

sub finish {
    my ($self, $result) = @_;

    # call the optional callback
    $self->on_finish->($self, $result) if ref($self->on_finish) eq 'CODE';
}

=method clone()

Clones the instance, for re-enqueuing purposes.

You are supposed to build your own stuff after/around/before this method using L<method modifiers|Moose::Manual::MethodModifiers>.
For example, to implement proper POST re-enqueuing:

    has method => (is => 'ro', isa => 'Str', default => 'GET');
    has post_content => (is => 'ro', isa => 'Str');

    ...;

    around clone => sub {
        my $orig = shift;
        my $self = shift;
        my $param = shift;

        $param->{method} = $self->method;
        $param->{post_content} = $self->post_content;

        return $self->$orig($param);
    };

=cut

sub clone {
    my ($self, $param) = @_;

    $param //= {};

    my $class = ($self->meta->class_precedence_list)[0];
    $param->{$_} = $self->$_()
        for qw(
            http_response
            initial_url
            on_finish
            on_init
            retry
            use_stats
        );
    --$param->{retry};

    return sub { $class->new($param) };
}

=method setopt(OPTION => VALUE [, OPTION => VALUE])

Extends L<Net::Curl::Easy> C<setopt()>, allowing option lists:

    $self->setopt(
        CURLOPT_ENCODING,         '',
        CURLOPT_FOLLOWLOCATION,   1,
        CURLOPT_USERAGENT,        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)',
        CURLOPT_VERBOSE,          1,
    );

Or even shorter:

    $self->setopt(
        encoding            => '',
        followlocation      => 1,
        useragent           => 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)',
        verbose             => 1,
    );

Complete list of options: L<http://curl.haxx.se/libcurl/c/curl_easy_setopt.html>

=cut

around setopt => sub {
    my $orig = shift;
    my $self = shift;

    if (@_) {
        my %param;
        if (scalar @_ % 2 == 0) {
            %param = @_;
        } elsif (ref($_[0]) eq 'HASH') {
            my $param = shift;
            %param = %{$param};
        } else {
            carp "setopt() expects OPTION/VALUE pair, OPTION/VALUE hash or hashref!";
        }

        while (my ($key, $val) = each %param) {
            $key = AnyEvent::Net::Curl::Const::opt($key);
            $self->$orig($key, $val) if defined $key;
        }
    } else {
        carp "Specify at least one OPTION/VALUE pair!";
    }
};

=method getinfo(VAR_NAME [, VAR_NAME])

Extends L<Net::Curl::Easy> C<getinfo()> so it is able to get several variables at once;
C<HashRef> parameter under void context will fill respective values in the C<HashRef>:

    my $x = {
        content_type    => 0,
        speed_download  => 0,
        primary_ip      => 0,
    };
    $self->getinfo($x);

C<HashRef> parameter will return another C<HashRef>:

    my $x = $self->getinfo({
        content_type    => 0,
        speed_download  => 0,
        primary_ip      => 0,
    });

C<ArrayRef> parameter will return a list:

    my ($content_type, $speed_download, $primary_ip) =
        $self->getinfo([qw(content_type speed_download primary_ip)]);

Complete list of options: L<http://curl.haxx.se/libcurl/c/curl_easy_getinfo.html>

=cut

around getinfo => sub {
    my $orig = shift;
    my $self = shift;

    given (ref($_[0])) {
        when ('ARRAY') {
            my @val;
            for my $name (@{$_[0]}) {
                my $const = AnyEvent::Net::Curl::Const::info($name);
                next unless defined $const;
                push @val, $self->$orig($const);
            }
            return @val;
        } when ('HASH') {
            my %val;
            for my $name (keys %{$_[0]}) {
                my $const = AnyEvent::Net::Curl::Const::info($name);
                next unless defined $const;
                $val{$name} = $self->$orig($const);
            }

            # write back to HashRef if called under void context
            unless (defined wantarray) {
                while (my ($k, $v) = each %val) {
                    $_[0]->{$k} = $v;
                }
                return;
            } else {
                return \%val;
            }
        } when ('') {
            my $const = AnyEvent::Net::Curl::Const::info($_[0]);
            return defined $const ? $self->$orig($const) : $const;
        } default {
            carp "getinfo() expects array/hash reference or string!";
            return;
        }
    }
};

=head1 SEE ALSO

=for :list
* L<Moose>
* L<MooseX::NonMoose>
* L<Net::Curl::Easy>

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;
