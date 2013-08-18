package YADA::Worker;
# ABSTRACT: "Yet Another Download Accelerator Worker": alias for AnyEvent::Net::Curl::Queued::Easy

=head1 DESCRIPTION

Exactly the same thing as L<AnyEvent::Net::Curl::Queued::Easy>, however, with a more Perl-ish and shorter name.

=cut

use strict;
use utf8;
use warnings qw(all);

use Moo;
extends 'AnyEvent::Net::Curl::Queued::Easy';

# VERSION

## no critic (ProtectPrivateSubs)
after finish => sub { shift->queue->_shift_worker };

=head1 SEE ALSO

=for :list
* L<AnyEvent::Net::Curl::Queued>
* L<AnyEvent::Net::Curl::Queued::Easy>
* L<YADA>

=cut

1;
