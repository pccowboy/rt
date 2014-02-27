# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2014 Best Practical Solutions, LLC
#                                          <sales@bestpractical.com>
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
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
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

package RT::Interface::Email::Action::Defaults;

use strict;
use warnings;

use Role::Basic 'with';
with 'RT::Interface::Email::Role';

use RT::Interface::Email;

sub _HandleCreate {
    my %args = (
        ErrorsTo    => undef,
        Subject     => undef,
        Message     => undef,
        Ticket      => undef,
        Queue       => undef,
        @_,
    );

    my $head = $args{Message}->head;

    my @Cc;
    my @Requestors = ( $args{Ticket}->CurrentUser->id );
    if (RT->Config->Get('ParseNewMessageForTicketCcs')) {
        my $user = $args{Ticket}->CurrentUser->UserObj;
        my $current_address = lc $user->EmailAddress;

        @Cc =
            grep $_ ne $current_address && !RT::EmailParser->IsRTAddress( $_ ),
            map lc $user->CanonicalizeEmailAddress( $_->address ),
            map RT::EmailParser->CleanupAddresses( Email::Address->parse( $head->get( $_ ) ) ),
            qw(To Cc);
    }

    $head->replace('X-RT-Interface' => 'Email');

    # ExtractTicketId may have been overridden, and edited the Subject
    my $subject = $head->get('Subject');
    chomp $subject;

    my ( $id, $Transaction, $ErrStr ) = $args{Ticket}->Create(
        Queue     => $args{Queue}->Id,
        Subject   => $subject,
        Requestor => \@Requestors,
        Cc        => \@Cc,
        MIMEObj   => $args{Message},
    );
    return if $id;

    MailError(
        To          => $args{ErrorsTo},
        Subject     => "Ticket creation failed: $args{Subject}",
        Explanation => $ErrStr,
        MIMEObj     => $args{Message},
    );
    FAILURE("Ticket creation failed: $ErrStr", $args{Ticket} );
}

sub HandleComment {
    _HandleEither( @_, Action => "Comment" );
}

sub HandleCorrespond {
    _HandleEither( @_, Action => "Correspond" );
}

sub _HandleEither {
    my %args = (
        Action      => undef,
        ErrorsTo    => undef,
        Message     => undef,
        Subject     => undef,
        Ticket      => undef,
        TicketId    => undef,
        Queue       => undef,
        @_,
    );

    return _HandleCreate(@_) unless $args{TicketId};

    unless ( $args{Ticket}->Id ) {
        my $error = "Could not find a ticket with id " . $args{TicketId};
        MailError(
            To          => $args{ErrorsTo},
            Subject     => "Message not recorded: $args{Subject}",
            Explanation => $error,
            MIMEObj     => $args{Message}
        );
        FAILURE( $error );
    }

    my $action = ucfirst $args{Action};
    my ( $status, $msg ) = $args{Ticket}->$action( MIMEObj => $args{Message} );
    return if $status;
}

1;

