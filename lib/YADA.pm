package YADA;
# ABSTRACT: "Yet Another Download Accelerator": alias for AnyEvent::Net::Curl::Queued

=head1 SYNOPSIS

    #!/usr/bin/env perl
    use common::sense;

    use YADA;

    YADA->new->append(
        [qw[
            http://www.cpan.org/modules/by-category/02_Language_Extensions/
            http://www.cpan.org/modules/by-category/02_Perl_Core_Modules/
            http://www.cpan.org/modules/by-category/03_Development_Support/
            ...
            http://www.cpan.org/modules/by-category/27_Pragma/
            http://www.cpan.org/modules/by-category/28_Perl6/
            http://www.cpan.org/modules/by-category/99_Not_In_Modulelist/
        ]] => sub {
            say $_[0]->final_url;
            say ${$_[0]->header};
        },
    )->wait;

=head1 DESCRIPTION

Use L<AnyEvent::Net::Curl::Queued> with fewer keystrokes.
Also, the I<easy things should be easy> side of the package.
For the I<hard things should be possible> side, refer to the complete L<AnyEvent::Net::Curl::Queued> documentation.

=head1 USAGE

The example in L</SYNOPSIS> is equivalent to:

    #!/usr/bin/env perl
    use common::sense;

    use AnyEvent::Net::Curl::Queued;
    use AnyEvent::Net::Curl::Queued::Easy;

    my $q = AnyEvent::Net::Curl::Queued->new;
    $q->append(sub {
        AnyEvent::Net::Curl::Queued::Easy->new({
            initial_url => $_,
            on_finish   => sub {
                say $_[0]->final_url;
                say ${$_[0]->header};
            },
        })
    }) for qw(
        http://www.cpan.org/modules/by-category/02_Language_Extensions/
        http://www.cpan.org/modules/by-category/02_Perl_Core_Modules/
        http://www.cpan.org/modules/by-category/03_Development_Support/
        ...
        http://www.cpan.org/modules/by-category/27_Pragma/
        http://www.cpan.org/modules/by-category/28_Perl6/
        http://www.cpan.org/modules/by-category/99_Not_In_Modulelist/
    );
    $q->wait;

As you see, L<YADA> overloads C<append>/C<prepend> from L<AnyEvent::Net::Curl::Queued>, adding implicit constructor for the worker object.
It also makes both methods return a reference to the queue object, so (almost) everything gets chainable.
The implicit constructor is triggered only when C<append>/C<prepend> receives multiple arguments.
The order of arguments (mostly) doesn't matter.
Their meaning is induced by their reference type:

=for :list
* String (non-reference) or L<URI>: assumed as L<AnyEvent::Net::Curl::Queued::Easy/initial_url> attribute. Passing several URLs will construct & enqueue several workers;
* Array: process a batch of URLs;
* Hash: attributes set for each L<AnyEvent::Net::Curl::Queued::Easy> instantiated. Passing several hashes will merge them, overwriting values for duplicate keys;
* C<sub { ... }>: assumed as L<AnyEvent::Net::Curl::Queued::Easy/on_finish> attribute;
* C<sub { ... }, sub { ... }>: the first block is assumed as L<AnyEvent::Net::Curl::Queued::Easy/on_init> attribute, while the second one is assumed as L<AnyEvent::Net::Curl::Queued::Easy/on_finish>.

=head2 Beware!

L<YADA> tries to follow the I<principle of least astonishment>, at least when you play nicely.
All the following snippets have the same meaning:

    $q->append(
        { retry => 3 },
        'http://www.cpan.org',
        'http://metacpan.org',
        sub { $_[0]->setopt(verbose => 1) }, # on_init placeholder
        \&on_finish,
    );

    $q->append(
        [qw[
            http://www.cpan.org
            http://metacpan.org
        ]],
        { retry => 3, opts => { verbose => 1 } },
        \&on_finish,
    );

    $q->append(
        URI->new($_) => \&on_finish,
        { retry => 3, opts => { verbose => 1 } },
    ) for qw[
        http://www.cpan.org
        http://metacpan.org
    ];

    $q->append(
        [qw[
            http://www.cpan.org
            http://metacpan.org
        ]] => {
            retry       => 3,
            opts        => { verbose => 1 },
            on_finish   => \&on_finish,
        }
    );

However, B<you will be astonished> if you specify multiple distinct C<on_init> and C<on_finish> or try to sneak in C<initial_url> through attributes!
At least, RTFC if you seriously attempt to do that.

=cut

use feature qw(switch);
use strict;
use utf8;
use warnings qw(all);

use Moo;

extends 'AnyEvent::Net::Curl::Queued';

use YADA::Worker;

no if ($] >= 5.017010), warnings => q(experimental);

# VERSION

# serious DWIMmery ahead!
around qw(append prepend) => sub {
    my $orig = shift;
    my $self = shift;

    if (1 < scalar @_) {
        my (%init, @url);
        for my $arg (@_) {
            for (ref $arg) {
                when ($_ eq '' or m{^URI::}x) {
                    push @url, $arg;
                } when ('ARRAY') {
                    push @url, @{$arg};
                } when ('CODE') {
                    unless (exists $init{on_finish}) {
                        $init{on_finish} = $arg;
                    } else {
                        @init{qw{on_init on_finish}} = ($init{on_finish}, $arg);
                    }
                } when ('HASH') {
                    $init{$_} = $arg->{$_}
                        for keys %{$arg};
                }
            }
        }

        for my $url (@url) {
            my %copy = %init;
            $copy{initial_url} = $url;
            $orig->($self => sub { YADA::Worker->new(\%copy) });
        }
    } else {
        $orig->($self => @_);
    }

    return $self;
};

=head1 SEE ALSO

=for :list
* L<AnyEvent::Net::Curl::Queued>
* L<AnyEvent::Net::Curl::Queued::Easy>
* L<YADA::Worker>

=cut

1;
