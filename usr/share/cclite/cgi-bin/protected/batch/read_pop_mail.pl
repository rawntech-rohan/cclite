#!/usr/bin/perl -w

sub _mail_message_parse {

    my ($input) = @_;

    my %transaction_description;
    my $parse_type = 0;

# send 4 duckets to unknown at dalston for barking lessons
# parse does include currency word, single currency only, no description also allowed
    if ( $input =~
        /send\s+(\d+)\s+(\w+)\s+to\s+(\w+)\s+at\s+(\w+)\s+for\s+(.*)/i )
    {

        $transaction_description{'amount'}      = $1;
        $transaction_description{'currency'}    = $2;
        $transaction_description{'destination'} = $3;
        $transaction_description{'registry'}    = $4;
        $transaction_description{'description'} = $5;
        $parse_type                             = 1;    # no currency word

        my $x = join( "|", %transaction_description );
        print MAIL
          "parsed mail transaction is: $x parse type is $parse_type\n\n";

    } else {
        print MAIL "unparsed pay transaction is: $input";
    }

    return ( $parse_type, \%transaction_description );

}

# --- start of main script ---#

use strict;
use Net::POP3;

use lib '../../../lib';

use Ccconfiguration;
use Ccmailgateway;
use Cclite;
use Ccinterfaces;
use Cccookie;
use Ccu;

BEGIN {
    use CGI::Carp qw(fatalsToBrowser set_message);
    set_message(
"Please use the <a title=\"cclite google group\" href=\"http://groups.google.co.uk/group/cclite\">Cclite Google Group</a> for help, if necessary"
    );

}

my %configuration = readconfiguration;

my %fields = cgiparse();

# for cron, replace these with hardcoded registry name
# my $registry  = 'dogtown' ;
my $cookieref = get_cookie();
my $registry  = $$cookieref{registry};

#FIXME: needs slightly higher barrier than this...
exit unless ( length($registry) );

# read the current registry to pick up per-registry email values
my ( $error, $registryref ) =
  get_where( $class, $registry, 'om_registry', 'name', $registry, $token, '', '' );
my $username = $registryref->{postemail};
my $password = $registryref->{postpass};
my $host     = $username;

# get the domain part as postbox...
$host =~ s/^(.*?)\@(.*)$/$2/;

###my $username = "cclite.dalston\@cclite.cclite.k-hosting.co.uk" ;
###my $password = 'caca' ;

my $file = '/home/hbarnard/cclite-support-files/mailtesting/mail.txt';

open( MAIL, ">$file" );

# Constructors
#my  $pop = Net::POP3->new('cclite.cclite.k-hosting.co.uk');
my $pop = Net::POP3->new( $host, Timeout => 60, Debug => 1 );

if ( $pop->login( $username, $password ) > 0 ) {
    my $msgnums = $pop->list;    # hashref of msgnum => size
    foreach my $msgnum ( keys %$msgnums ) {
        my $msg = $pop->get($msgnum);
        my ( $from, $to );

        # make a message object
        foreach my $part (@$msg) {
            ###print MAIL "$part ---------------------------\n" ;

            if ( $part =~ /From:\s.*?\W([\.-\w]+@([-\w]+\.)+[A-Za-z]{2,4})\W/ )
            {
                $from = $1;
                print MAIL "from is $1\n";

            } elsif ( $part =~ /To:\s.*?\W([^@]+@([-\w]+\.)+[A-Za-z]{2,4})\W/ )
            {
                $to = $1;
                print MAIL "to is $1\n";

# want the send line but not twice if multipart/alternate, so reject if html fragments
            } elsif ( $part =~ /(send.*?)/i && $part !~ /\</ ) {
                print MAIL "send is $part";
                my ( $parse_type, $transaction_description_ref ) =
                  mail_message_parse( 'local', $registry, $from, $to, $part );
                my $output_message;
                if ( !length( $transaction_description_ref->{error} ) ) {
                    $output_message =
                      mail_transaction($transaction_description_ref);

                } else {
                    $output_message = $transaction_description_ref->{error};
                }
                notify_by_mail( 'local', $registry, '', $username, $username,
                    $username, $accountname, $smtp, '', $output_message, 5,
                    '' );

            }

                    $pop->delete($msgnum);
        }
    }

    $pop->quit;

    # close MAIL ;

