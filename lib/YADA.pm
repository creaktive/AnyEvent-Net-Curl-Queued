package YADA;
# ABSTRACT: "Yet Another Download Accelerator": alias for AnyEvent::Net::Curl::Queued

=head1 SYNOPSIS

    #!/usr/bin/env perl
    use feature qw(say);
    use strict;
    use utf8;
    use warnings qw(all);

    use YADA;

    my $q = YADA->new;
    $q->append(
        YADA::Worker->new({
            initial_url => $_,
            on_finish   => sub {
                say $_[0]->final_url;
                say ${$_[0]->header};
            },
        })
    ) for qw(
        http://www.cpan.org/modules/by-category/02_Language_Extensions/
        http://www.cpan.org/modules/by-category/02_Perl_Core_Modules/
        http://www.cpan.org/modules/by-category/03_Development_Support/
        ...
        http://www.cpan.org/modules/by-category/27_Pragma/
        http://www.cpan.org/modules/by-category/28_Perl6/
        http://www.cpan.org/modules/by-category/99_Not_In_Modulelist/
    );
    $q->wait;

=head1 DESCRIPTION

Use L<AnyEvent::Net::Curl::Queued> with fewer keystrokes.
Also, the I<easy things should be easy> side of the package.
For the I<hard things should be possible> side, refer to the complete L<AnyEvent::Net::Curl::Queued> documentation.

=cut

use strict;
use utf8;
use warnings qw(all);

use Any::Moose;

extends 'AnyEvent::Net::Curl::Queued';

use YADA::Worker;

# VERSION

=head1 SEE ALSO

=for :list
* L<AnyEvent::Net::Curl::Queued>
* L<AnyEvent::Net::Curl::Queued::Easy>
* L<YADA::Worker>

=cut

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
