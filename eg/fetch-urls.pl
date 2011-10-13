#!/usr/bin/env perl

package MyDownloader;
use common::sense;

use Moose;

extends 'AnyEvent::Net::Curl::Queued::Easy';

after init => sub {
    my ($self) = @_;

    $self->setopt(
        encoding            => '',
        verbose             => 1,
    );
};

after finish => sub {
    my ($self, $result) = @_;

    if ($self->has_error) {
        say "ERROR: $result";
    } else {
        printf "Finished downloading %s: %d bytes\n", $self->final_url, length ${$self->data};
    }
};

around has_error => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->$orig(@_);
    return 1 if $self->getinfo('response_code') =~ m{^5[0-9]{2}$};
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package main;
use common::sense;
use lib qw(lib);

use Data::Printer;

use AnyEvent::Net::Curl::Queued;

my $q = AnyEvent::Net::Curl::Queued->new({
    max     => 8,
    timeout => 30,
});

while (my $url = <DATA>) {
    chomp $url;

    $q->append(sub {
        MyDownloader->new({
            initial_url => $url,
            retry       => 10,
        })
    });
}
$q->wait;

p $q->stats;

__DATA__
http://localhost/manual/en/bind.html
http://localhost/manual/en/caching.html
http://localhost/manual/en/configuring.html
http://localhost/manual/en/content-negotiation.html
http://localhost/manual/en/custom-error.html
http://localhost/manual/en/developer/API.html
http://localhost/manual/en/developer/debugging.html
http://localhost/manual/en/developer/documenting.html
http://localhost/manual/en/developer/filters.html
http://localhost/manual/en/developer/hooks.html
http://localhost/manual/en/developer/index.html
http://localhost/manual/en/developer/modules.html
http://localhost/manual/en/developer/request.html
http://localhost/manual/en/developer/thread_safety.html
http://localhost/manual/en/dns-caveats.html
http://localhost/manual/en/dso.html
http://localhost/manual/en/env.html
http://localhost/manual/en/faq/index.html
http://localhost/manual/en/filter.html
http://localhost/manual/en/glossary.html
http://localhost/manual/en/handler.html
http://localhost/manual/en/howto/access.html
http://localhost/manual/en/howto/auth.html
http://localhost/manual/en/howto/cgi.html
http://localhost/manual/en/howto/htaccess.html
http://localhost/manual/en/howto/index.html
http://localhost/manual/en/howto/public_html.html
http://localhost/manual/en/howto/ssi.html
http://localhost/manual/en/index.html
http://localhost/manual/en/install.html
http://localhost/manual/en/invoking.html
http://localhost/manual/en/license.html
http://localhost/manual/en/logs.html
http://localhost/manual/en/misc/index.html
http://localhost/manual/en/misc/password_encryptions.html
http://localhost/manual/en/misc/perf-tuning.html
http://localhost/manual/en/misc/relevant_standards.html
http://localhost/manual/en/misc/rewriteguide.html
http://localhost/manual/en/misc/security_tips.html
http://localhost/manual/en/mod/beos.html
http://localhost/manual/en/mod/core.html
http://localhost/manual/en/mod/directive-dict.html
http://localhost/manual/en/mod/directives.html
http://localhost/manual/en/mod/event.html
http://localhost/manual/en/mod/index.html
http://localhost/manual/en/mod/mod_actions.html
http://localhost/manual/en/mod/mod_alias.html
http://localhost/manual/en/mod/mod_asis.html
http://localhost/manual/en/mod/mod_auth_basic.html
http://localhost/manual/en/mod/mod_auth_digest.html
http://localhost/manual/en/mod/mod_authn_alias.html
http://localhost/manual/en/mod/mod_authn_anon.html
http://localhost/manual/en/mod/mod_authn_dbd.html
http://localhost/manual/en/mod/mod_authn_dbm.html
http://localhost/manual/en/mod/mod_authn_default.html
http://localhost/manual/en/mod/mod_authn_file.html
http://localhost/manual/en/mod/mod_authnz_ldap.html
http://localhost/manual/en/mod/mod_authz_dbm.html
http://localhost/manual/en/mod/mod_authz_default.html
http://localhost/manual/en/mod/mod_authz_groupfile.html
http://localhost/manual/en/mod/mod_authz_host.html
http://localhost/manual/en/mod/mod_authz_owner.html
http://localhost/manual/en/mod/mod_authz_user.html
http://localhost/manual/en/mod/mod_autoindex.html
http://localhost/manual/en/mod/mod_cache.html
http://localhost/manual/en/mod/mod_cern_meta.html
http://localhost/manual/en/mod/mod_cgid.html
http://localhost/manual/en/mod/mod_cgi.html
http://localhost/manual/en/mod/mod_charset_lite.html
http://localhost/manual/en/mod/mod_dav_fs.html
http://localhost/manual/en/mod/mod_dav.html
http://localhost/manual/en/mod/mod_dav_lock.html
http://localhost/manual/en/mod/mod_dbd.html
http://localhost/manual/en/mod/mod_deflate.html
http://localhost/manual/en/mod/mod_dir.html
http://localhost/manual/en/mod/mod_disk_cache.html
http://localhost/manual/en/mod/mod_dumpio.html
http://localhost/manual/en/mod/mod_echo.html
http://localhost/manual/en/mod/mod_env.html
http://localhost/manual/en/mod/mod_example.html
http://localhost/manual/en/mod/mod_expires.html
http://localhost/manual/en/mod/mod_ext_filter.html
http://localhost/manual/en/mod/mod_file_cache.html
http://localhost/manual/en/mod/mod_filter.html
http://localhost/manual/en/mod/mod_headers.html
http://localhost/manual/en/mod/mod_ident.html
http://localhost/manual/en/mod/mod_imagemap.html
http://localhost/manual/en/mod/mod_include.html
http://localhost/manual/en/mod/mod_info.html
http://localhost/manual/en/mod/mod_isapi.html
http://localhost/manual/en/mod/mod_ldap.html
http://localhost/manual/en/mod/mod_log_config.html
http://localhost/manual/en/mod/mod_log_forensic.html
http://localhost/manual/en/mod/mod_logio.html
http://localhost/manual/en/mod/mod_mem_cache.html
http://localhost/manual/en/mod/mod_mime.html
http://localhost/manual/en/mod/mod_mime_magic.html
http://localhost/manual/en/mod/mod_negotiation.html
http://localhost/manual/en/mod/mod_nw_ssl.html
http://localhost/manual/en/mod/mod_proxy_ajp.html
http://localhost/manual/en/mod/mod_proxy_balancer.html
http://localhost/manual/en/mod/mod_proxy_connect.html
http://localhost/manual/en/mod/mod_proxy_ftp.html
http://localhost/manual/en/mod/mod_proxy.html
http://localhost/manual/en/mod/mod_proxy_http.html
http://localhost/manual/en/mod/mod_proxy_scgi.html
http://localhost/manual/en/mod/mod_reqtimeout.html
http://localhost/manual/en/mod/mod_rewrite.html
http://localhost/manual/en/mod/mod_setenvif.html
http://localhost/manual/en/mod/mod_so.html
http://localhost/manual/en/mod/mod_speling.html
http://localhost/manual/en/mod/mod_ssl.html
http://localhost/manual/en/mod/mod_status.html
http://localhost/manual/en/mod/mod_substitute.html
http://localhost/manual/en/mod/mod_suexec.html
http://localhost/manual/en/mod/module-dict.html
http://localhost/manual/en/mod/mod_unique_id.html
http://localhost/manual/en/mod/mod_userdir.html
http://localhost/manual/en/mod/mod_usertrack.html
http://localhost/manual/en/mod/mod_version.html
http://localhost/manual/en/mod/mod_vhost_alias.html
http://localhost/manual/en/mod/mpm_common.html
http://localhost/manual/en/mod/mpm_netware.html
http://localhost/manual/en/mod/mpmt_os2.html
http://localhost/manual/en/mod/mpm_winnt.html
http://localhost/manual/en/mod/prefork.html
http://localhost/manual/en/mod/quickreference.html
http://localhost/manual/en/mod/worker.html
http://localhost/manual/en/mpm.html
http://localhost/manual/en/new_features_2_0.html
http://localhost/manual/en/new_features_2_2.html
http://localhost/manual/en/platform/ebcdic.html
http://localhost/manual/en/platform/index.html
http://localhost/manual/en/platform/netware.html
http://localhost/manual/en/platform/perf-hp.html
http://localhost/manual/en/platform/win_compiling.html
http://localhost/manual/en/platform/windows.html
http://localhost/manual/en/programs/ab.html
http://localhost/manual/en/programs/apachectl.html
http://localhost/manual/en/programs/apxs.html
http://localhost/manual/en/programs/configure.html
http://localhost/manual/en/programs/dbmmanage.html
http://localhost/manual/en/programs/htcacheclean.html
http://localhost/manual/en/programs/htdbm.html
http://localhost/manual/en/programs/htdigest.html
http://localhost/manual/en/programs/htpasswd.html
http://localhost/manual/en/programs/httpd.html
http://localhost/manual/en/programs/httxt2dbm.html
http://localhost/manual/en/programs/index.html
http://localhost/manual/en/programs/logresolve.html
http://localhost/manual/en/programs/other.html
http://localhost/manual/en/programs/rotatelogs.html
http://localhost/manual/en/programs/suexec.html
http://localhost/manual/en/rewrite/index.html
http://localhost/manual/en/rewrite/rewrite_flags.html
http://localhost/manual/en/rewrite/rewrite_guide_advanced.html
http://localhost/manual/en/rewrite/rewrite_guide.html
http://localhost/manual/en/rewrite/rewrite_intro.html
http://localhost/manual/en/rewrite/rewrite_tech.html
http://localhost/manual/en/sections.html
http://localhost/manual/en/server-wide.html
http://localhost/manual/en/sitemap.html
http://localhost/manual/en/ssl/index.html
http://localhost/manual/en/ssl/ssl_compat.html
http://localhost/manual/en/ssl/ssl_faq.html
http://localhost/manual/en/ssl/ssl_howto.html
http://localhost/manual/en/ssl/ssl_intro.html
http://localhost/manual/en/stopping.html
http://localhost/manual/en/suexec.html
http://localhost/manual/en/upgrading.html
http://localhost/manual/en/urlmapping.html
http://localhost/manual/en/vhosts/details.html
http://localhost/manual/en/vhosts/examples.html
http://localhost/manual/en/vhosts/fd-limits.html
http://localhost/manual/en/vhosts/index.html
http://localhost/manual/en/vhosts/ip-based.html
http://localhost/manual/en/vhosts/mass.html
http://localhost/manual/en/vhosts/name-based.html
