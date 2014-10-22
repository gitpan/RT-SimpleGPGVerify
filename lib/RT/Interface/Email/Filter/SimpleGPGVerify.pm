# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2007 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/copyleft/gpl.html.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
#
package RT::Interface::Email::Filter::SimpleGPGVerify;
use Mail::GnuPG;

=head2 GetCurrentUser

To use the GPG signature verification, you need to do the following:

Set up a gnupg key directory with a pubring containing only the keys
you care about and specify the following in your SiteConfig.pm

Set($RT::GPGKeyDir, "/path/to/keyring-directory");
@RT::MailPlugins = qw(Auth::MailFrom Filter::SimpleGPGVerify);

You'll also want to have a configuration file (gpg.conf) that looks like this in your GPG keyring directory:

 keyserver pgp.mit.edu
 keyserver-options honor-http-proxy,auto-key-retrieve


=cut

sub _safe_run_child (&) {
    local @ENV{'LANG', 'LC_ALL'} = ('C', 'C');

    return shift->() if $ENV{'MOD_PERL'};

    # We need to reopen stdout temporarily, because in FCGI
    # environment, stdout is tied to FCGI::Stream, and the child
    # of the run3 wouldn't be able to reopen STDOUT properly.
    my $stdin = IO::Handle->new;
    $stdin->fdopen( 0, 'r' );
    local *STDIN = $stdin;

    my $stdout = IO::Handle->new;
    $stdout->fdopen( 1, 'w' );
    local *STDOUT = $stdout;
    
    my $stderr = IO::Handle->new;
    $stderr->fdopen( 2, 'w' );
    local *STDERR = $stderr;
    
    return shift->();
}


sub GetCurrentUser {
    my %args = (
        Message     => undef,
        RawMessageRef     => undef,
        CurrentUser => undef,
        AuthLevel   => undef,
        Ticket      => undef,
        Queue       => undef,
        Action      => undef,
        @_
    );

    my ( $val, $key, $address,$gpg );
        $args{'Message'}->head->set('RT-PGP-Status-A' => '1');
    eval {
        my $parser = RT::EmailParser->new();
        $parser->SmartParseMIMEEntityFromScalar(Message => ${$args{'RawMessageRef'}}, Decode => 0);
        $gpg = Mail::GnuPG->new( keydir => $RT::GPGKeyDir );
        my $entity = $parser->Entity;
        _safe_run_child {( $val, $key, $address ) = $gpg->verify( $parser->Entity)};
      };
        if (my $msg = $@) { $RT::Logger->error($msg); }
        $args{'Message'}->head->set('RT-PGP-Status-B' => '1');

        $args{'Message'}->head->set('RT-PGP-Status' => '');

        if (defined $val) {
            if ($address) {
                $args{'Message'}->head->set('RT-PGP-Status' => 'Good signature from '. $address);


                    # GOOD SIGNATURE
            }
            else {
                $args{'Message'}->head->set('RT-PGP-Status' => 'BAD GPG signature');
                # BAD SIGNATURE
                 }
        }
        else { 
                $args{'Message'}->head->set('RT-PGP-Status' => 'NO GPG signature');
            # NO SIGNATURE;
            
        }
        $args{'Message'}->head->set('RT-PGP-Status-C' => '1');
        return ( $args{'CurrentUser'}, $args{'AuthLevel'} );

}

eval "require RT::Interface::Email::Auth::GnuPG_Vendor";
die $@
  if ( $@
    && $@ !~ qr{^Can't locate RT/Interface/Email/Auth/GnuPG_Vendor.pm} );
eval "require RT::Interface::Email::Auth::GnuPG_Local";
die $@
  if ( $@
    && $@ !~ qr{^Can't locate RT/Interface/Email/Auth/GnuPG_Local.pm} );

1;
