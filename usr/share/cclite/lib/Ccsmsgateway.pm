
=head1 NAME

Ccsmsgateway.pm

=head1 SYNOPSIS

Transaction conversion interfaces inwards for sms, mail etc.
via commercial sms gateway this will have to be modified
for any new gateway supplier

=head1 DESCRIPTION

This contains the interface for a complete sms based payment
system with pins supplied in the sms messages. The allowed messages are:

This does a small parse of the incoming message:

gwNumber  	The destination number
originator 	The sender's number in format 447779159452
message 	The message body
smsTime 	Time when the sms was sent
		Format: YYYY-MM-DD HH:MM:SS
timeZone 	An integer, indicating time zone
		(eg: if timeZone is 1 then it means smsTime is GMT + 1)
network 	Name of the originating network.
		Will be replaced with an SMSC reference number if the network is not recognised
id 		A unique identifier for the message
time 		Time the message received by gateway (UK time)
		Format: YYYY-MM-DD HH:MM:SS
coding 		Message coding 7 (normal), 8 (binary) or 16 (unicode)
status 		0 - Normal Message
		1 - Concatenated message, sent unconcatenated
		2 - Indecipherable UDH (possibly corrupt message)

status added for error messages



and dispatches to the appropriate internal function

Pin number is always first thing...

SMS Transactions
-> Confirm pin         p123456 confirm-> Change pin          p123456 change p345678
-> Pay                 p123456 pay 5 to 07855 524667 for stuff (note need to change strip regex)
                       p123456 pay 5 to 07855524667 for other stuff
                       p123456 pay 5 to 4407855 524667 for stuff

-> Query Balance       p123456 balance (not implemented yet will use one credit!)


=head1 AUTHOR

Hugh Barnard



=head1 SEE ALSO

Cchooks.pm

=head1 COPYRIGHT

(c) Hugh Barnard 2005 - 2008 GPL Licenced
 
=cut

package Ccsmsgateway;
use strict;
use vars qw(@ISA @EXPORT);
use Exporter;
my $VERSION = 1.00;
@ISA = qw(Exporter);
use Cclite;
use Cclitedb;
use Ccu;
use Ccsecure;
use Ccconfiguration;    # new style configuration method

use Net::SMTP::SSL;

@EXPORT = qw(
  gateway_sms_transaction
);

=head3 messagehash

this is the provisional solution to the multilingual message fragments
later, it will go somewhere neater
to change these, just substitute a translated hash
 
=cut

# application specific globals
our %messages = readmessages("en");
our $registry = 'totnes';
our $currency = 'tpound';
our $log      = Log::Log4perl->get_logger("Ccsmsgateway");

=head3 gateway_sms_transaction

This does a validation (could move to ccvalidate) and
an initial parse of the incoming message and
then dispatches to the appropriate internal function

=cut

sub gateway_sms_transaction {

    my ( $configurationref, $fieldsref, $token ) = @_;

    my ( $offset, $limit );

    my $x = join( "|", %$fieldsref );
    $log->debug(
"\n---------------------------------------------------\nentering gateway:\n $x"
    );

    my ( $error, $fromuserref ) =
      get_where( 'local', $registry, 'om_users', 'userMobile',
        $$fieldsref{'originator'},
        $token, $offset, $limit );

    # log and exit if there's a problem with the received messaged
    if ( defined( $$fieldsref{'status'} ) && $$fieldsref{'status'} > 0 ) {
        $log->warn(
"$$fieldsref{'message'} from $$fieldsref{'originator'} rejected with status $$fieldsref{'status'}"
        );
        return;
    }

    # no originator, so no lookup or no message...reject
    if (   !length( $$fieldsref{'originator'} )
        || !length( $$fieldsref{'message'} ) )
    {
        $log->warn(
"$$fieldsref{'message'} from $$fieldsref{'originator'} rejected message or originator is blank"
        );
        return;
    }

    # initial parse to get transaction type
    my $input = lc( $$fieldsref{'message'} );    # canonical is lower case

    my $pin;
    my $transaction_type;

    # if it hasn't got a pin, not worth carrying on
    if ( $input =~ m/^\s*p*(\d+)\s+(\w+)/ ) {
        $pin              = $1;
        $transaction_type = $2;
    } else {
        $log->warn(
            "from: $$fieldsref{'originator'} $input -malformed transaction");
        my ($mail_error) =
          _send_sms_mail_message( 'local', $registry,
            "from: $$fieldsref{'originator'} $input -malformed transaction",
            $fromuserref );
    }

    # numbers are stored in database as 7855 667524 for example, no zero, no 44
    $$fieldsref{'originator'} =
      format_for_uk_mobile( $$fieldsref{'originator'} );

    # can be ok, locked, waiting, fail
    my $pin_status = _check_pin( $pin, $transaction_type, $fieldsref, $token );

    $log->debug("$pin $pin_status transaction type is $transaction_type");

    return if ( $pin_status ne 'ok' );

    # activation is done in _check_pin
    if ( $transaction_type eq 'confirm' ) {    #  p123456 confirm
        return $pin_status;
    } elsif ( $transaction_type eq 'change' ) {    # change pin
        _gateway_sms_pin_change( $fieldsref, $token );
    } elsif ( $transaction_type eq 'pay' ) {       # payment transaction
        _gateway_sms_pay( $configurationref, $fieldsref, $token );
    } elsif ( $transaction_type eq 'balance' )
    {    # balance transaction not implemented
            # fully yet
        _gateway_sms_send_balance( $fieldsref, $token );
    } else {
        $log->warn(
            "from: $$fieldsref{'originator'} $input -unrecognised transaction");
        return 'unrecognisable transaction';

        # this is a 'bad' transaction of some kind...
    }

    return;
}

=head3 _gateway_sms_pin_change
Change pin, same rules (three tries) about pin locking
=cut

sub _gateway_sms_pin_change {
    my ( $fieldsref, $token ) = @_;
    my ( $offset, $limit );
    my $input = lc( $$fieldsref{'message'} );    # canonical is lower case
    $input =~ m/^\s*p*(\d+)\s+change\s+p(\d+)\s*$/;
    my $new_pin    = $2;
    my $hashed_pin = text_to_hash($new_pin);

    my $message = $messages{'smspinchanged'};
    my ( $error, $fromuserref ) =
      get_where( 'local', $registry, 'om_users', 'userMobile',
        $$fieldsref{'originator'},
        $token, $offset, $limit );

    $$fromuserref{'userPin'}      = $hashed_pin;
    $$fromuserref{'userPinTries'} = 3;

    my ( $dummy, $home_ref, $dummy1, $html, $template, $dummy2 ) =
      update_database_record( 'local', $registry, 'om_users', 1, $fromuserref,
        $token );

    my ($mail_error) =
      _send_sms_mail_message( 'local', $registry, $message, $fromuserref );

    return;
}

=head3 _gateway_sms_pay

Specific transaction written for the pound
using the gateway messaging gateway


=cut

sub _gateway_sms_pay {
    my ( $configurationref, $fieldsref, $token ) = @_;
    my ( %fields, %transaction, $offset, $limit, $class, $pages, @status );
    %fields = %$fieldsref;

    my ( $error, $fromuserref ) =
      get_where( $class, $registry, 'om_users', 'userMobile',
        $fields{'originator'}, $token, $offset, $limit );

    # begin parse on whitespace
    my $input = lc( $fields{'message'} );    # canonical is lower case

    my ( $parse_type, $transaction_description_ref ) =
      _sms_message_parse($input);

    # sms pay message didn't parse, not worth proceeding
    if ( $parse_type == 0 ) {
        my $message =
"pay attempt from $fields{'originator'} to $$transaction_description_ref{'tomobilenumber'} : $messages{'smsinvalidsyntax'}";
        $log->warn($message);
        my ($mail_error) =
          _send_sms_mail_message( 'local',$registry, $message, $fromuserref );
        return;
    }

    # numbers are stored as 7855 667524 for example, no zero, no 44
    $$transaction_description_ref{'tomobilenumber'} =
      format_for_uk_mobile( $$transaction_description_ref{'tomobilenumber'} );

    my ( $error1, $touserref ) =
      get_where( $class, $registry, 'om_users', 'userMobile',
        $$transaction_description_ref{'tomobilenumber'},
        $token, $offset, $limit );

    $log->debug(
" $$transaction_description_ref{'tomobilenumber'} pin status is $$touserref{'userPinStatus'}"
    );

    # one of the above lookups fails, reject the whole transaction
    push @status, $messages{'smsnoorigin'}      if ( !length($fromuserref) );
    push @status, $messages{'smsnodestination'} if ( !length($touserref) );

    # recipient didn't confirm pin yet, transaction invalid
    push @status, 'receiving user has not confirmed'
      if ( $$touserref{'userPinStatus'} ne 'active' );
    $log->debug(
        "$$touserref{'userPinStatus'} $$touserref{'userId'} no confirmation bug"
    );
    my $errors = join( ':', @status );
    if ( scalar(@status) > 0 ) {
        _send_sms_mail_message( 'local',$registry, "$errors $input", $fromuserref );
        $log->warn(
"pay attempt from $fields{'originator'} to $$transaction_description_ref{'tomobilenumber'} : $errors"
        );
        return;
    }

    # convert to standard transaction input format, fields etc.
    #fromregistry : chelsea
    $transaction{fromregistry} = $registry;

    # no home, not a web transaction
    $transaction{home} = "";

    #subaction : om_trades
    $transaction{subaction} = 'om_trades';

    #toregistry : dalston
    $transaction{toregistry} = $registry;

    #tradeAmount : 23
    $transaction{tradeAmount} = $$transaction_description_ref{'quantity'};

 #tradeCurrency : if mentioned in sms overrides default: may not be a good idea?
    $transaction{tradeCurrency} = $$transaction_description_ref{'currency'}
      || $currency;

    #tradeDate : this is date of reception and processing, in fact
    my ( $date, $time ) = &Ccu::getdateandtime( time() );
    $transaction{tradeDate} = $date;

    #tradeTitle : added by this routine: now improved 12/2008
    $transaction{tradeTitle} =
"$messages{'smstransactiontitle'} $$fromuserref{'userLogin'} -> $$touserref{'userLogin'}";

    #tradeDescription
    $transaction{tradeDescription} =
      $$transaction_description_ref{'description'};

    #tradeDestination : ddawg
    $transaction{tradeDestination} = $$touserref{userLogin};

    #tradeSource : manager
    $transaction{tradeSource} = $$fromuserref{userLogin};

    # tradestatus from configured initial status
    $transaction{tradeStatus} = $fields{initialPaymentStatus};

    # FIXME: tradeItem not really identifiable from sms message
    $transaction{tradeItem} = 'other';

    # call ordinary transaction
    my $transaction_ref = \%transaction;

    #build explicative message
    my $message = <<EOT;
   $messages{'transactionaccepted'} to $transaction{tradeDestination} for value $transaction{tradeAmount}
EOT

    my ( $metarefresh, $home, $error3, $output_message, $page, $c ) =
      transaction( 'sms', $transaction{fromregistry},
        'om_trades', $transaction_ref, $pages, $token );
    _send_sms_mail_message( 'local',$registry, $message, $fromuserref );
    return;
}

=head3 _gateway_sms_send_balance

Send balance, via email at present, sms later...
To be done...

=cut

sub _gateway_sms_send_balance {

    my ( $fieldsref, $token ) = @_;
    my ( $offset, $limit, $balance_ref, $volume_ref );

    my ( $error, $fromuserref ) =
      get_where( 'local', $registry, 'om_users', 'userMobile',
        $$fieldsref{'originator'},
        $token, $offset, $limit );

    my %fields = ( 'userLogin', $$fromuserref{'userLogin'} );
    my $fieldsref = \%fields;

    # html to return html, values to return raw balances and volumes
    # for each currency
    ( $balance_ref, $volume_ref ) =
      show_balance_and_volume( 'local', $registry, 'om_trades', $fieldsref, "",
        $$fromuserref{'userLogin'},
        'values', $token, $offset, $limit );

    # current balance for this particular currency
    my $balance = $$balance_ref{$currency};
    my $balance_message =
      "The balance for $fromuserref->{userLogin} is $balance $currency" . "s";
    my ($mail_error) =
      _send_sms_mail_message( 'local',$registry, $balance_message, $fromuserref );
    $log->debug($balance_message);
    return;
}

=head3 sms_message_parse

This is now distinct from the transaction preparation etc.

Also, it returns a status, if the parse doesn't contain one
of the necessary elements for a successful transaction. In that
case the transaction -must- fail and it's not worth continuing

=cut

sub _sms_message_parse {

    my ($input) = @_;

    my %transaction_description;
    my $parse_type = 0;

# parse does not include currency word, single currency only, no description also allowed
    if ( $input =~
m/^\s*p*(\d+)\s+pay\s+(\d+)\s+to\s+(\d{10}|\d{4}\s+\d{6})\s+for\s+(.*)$/i
      )
    {

        $transaction_description{'quantity'}       = $2;
        $transaction_description{'tomobilenumber'} = $3;
        $transaction_description{'description'}    = $4;
        $parse_type                                = 1;    # no currency word
             # multiple currencies and currency word included,
    } elsif ( $input =~
m/^\s*p*(\d+)\s+pay\s+(\d+)\s+(\w+)\s+to\s+(\d{10}|\d{4}\s+\d{6})\s+for\s+(.*)$/i
      )
    {

        $transaction_description{'quantity'}       = $2;
        $transaction_description{'currency'}       = $3;
        $transaction_description{'tomobilenumber'} = $4;
        $transaction_description{'description'}    = $5;
        $parse_type                                = 2;    # currency word
    } elsif ( $input =~
        m/^\s*p*(\d+)\s+pay\s+(\d+)\s+to\s+(\d{10}|\d{4}\s+\d{6})\s*$/i )
    {
        $transaction_description{'quantity'}       = $2;
        $transaction_description{'tomobilenumber'} = $3;
        $transaction_description{'description'} =
          'sms transaction:no description';
        $parse_type = 3;    # no description/no currency word

    } else {
        $log->warn("unparsed pay transaction is: $input");
    }

    my $x = join( "|", %transaction_description );
    $log->debug("parsed transaction is: $x parse type is $parse_type");

    return ( $parse_type, \%transaction_description );

}

=item _check_pin

put the pin checking and locking processing into one place
used by every transansaction

returns:
ok 	- pin checks
locked 	- account is locked
waiting - account is not activated/transaction attempt
fail	- pin fail, counts down one off counter/locks if zero

less than 1 is test for try count, just-in-case
=cut

sub _check_pin {

    my ( $pin, $transaction_type, $fieldsref, $token ) = @_;
    my ( $offset, $limit, $mail_error );

    my $pin_status;
    my $message;
    my $hashed_pin = text_to_hash($pin);

    my ( $error, $fromuserref ) =
      get_where( 'local', $registry, 'om_users', 'userMobile',
        $$fieldsref{'originator'},
        $token, $offset, $limit );

    # already locked
    if ( $$fromuserref{'userPinStatus'} eq 'locked' ) {
        $message = $messages{'smslocked'};
        $mail_error = _send_sms_mail_message( 'local', $registry, $message, $fromuserref );
        return 'locked';
    }

    # ok, maybe need to reset pin tries though
    if ( $transaction_type ne 'confirm' ) {

        if ( $$fromuserref{'userPin'} eq $hashed_pin ) {
            $pin_status = 'ok';
            return $pin_status
              if ( $$fromuserref{'userPinTries'} == 3 ); # this is the main case
            $$fromuserref{'userPinTries'} = 3;    # reset to three otherwise
        } elsif ( $$fromuserref{'userPinTries'} > 1 ) {
            $pin_status = 'fail';
            $message    = $messages{'smspinfail'};
            $$fromuserref{'userPinTries'}--;      # used one pin attempt
        } elsif ( $$fromuserref{'userPinTries'} <= 1 ) {
            $pin_status                    = 'locked';
            $message                       = $messages{'smslocked'};
            $$fromuserref{'userPinStatus'} = 'locked';
            $$fromuserref{'userPinTries'}  = 0;
        }
    }

    # waiting and confirm
    if (   ( $$fromuserref{'userPinStatus'} ne 'locked' )
        && ( $transaction_type eq 'confirm' ) )
    {

        if ( $$fromuserref{'userPin'} eq $hashed_pin ) {
            $pin_status = 'ok';
            $message    = $messages{smspinactive};
            $$fromuserref{'userPinTries'} = 3;    # reset or set pin tries to 3
            $$fromuserref{'userPinStatus'} = 'active';
        } elsif ( $$fromuserref{'userPinTries'} > 1 ) {
            $pin_status = 'fail';
            $message    = $messages{'smspinfail'};
            $$fromuserref{'userPinTries'}--;      # used one pin attempt
        } elsif ( $$fromuserref{'userPinTries'} <= 1 ) {
            $pin_status                    = 'locked';
            $$fromuserref{'userPinTries'}  = 0;
            $message                       = $messages{'smslocked'};
            $$fromuserref{'userPinStatus'} = 'locked';
        }
    }
    $log->debug(
"in pin checking for user: $$fromuserref{'userId'} $$fromuserref{'userLogin'}"
    );

    # anything getting to here, needs to update the user record
    my ( $dummy, $home_ref, $dummy1, $html, $template, $dummy2 ) =
      update_database_record( 'local', $registry, 'om_users', 1, $fromuserref,
        $token );

    if ( length($message) ) {
        $mail_error = _send_sms_mail_message( 'local',$registry, $message, $fromuserref );
    }

    return $pin_status;
}

=item _send_sms_mail_message

wrapper for notify_by_mail in package Cclite
with notification type 4

=cut

sub _send_sms_mail_message {

    my ( $class, $registry, $message, $fromuserref ) = @_;
    my ( $mail_error, $urlstring, $hash, $smtp );

    my %configuration = readconfiguration();

    ###return ;

    my $mail_error = notify_by_mail(
	$class,
	$registry,
        $$fromuserref{'userName'},
        $$fromuserref{'userEmail'},
        $configuration{'systemmailaddress'},
        $configuration{'systemmailreplyaddress'},
        $$fromuserref{'userLogin'},
        $smtp,
        $urlstring,
        $message,
        4,
        $hash
    );

    return $mail_error;

}

1;

