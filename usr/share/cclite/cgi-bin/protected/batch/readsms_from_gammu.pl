#!/usr/bin/perl 
#---------------------------------------------------------------------------
#THE cclite SOFTWARE IS PROVIDED TO YOU "AS IS," AND WE MAKE NO EXPRESS
#OR IMPLIED WARRANTIES WHATSOEVER WITH RESPECT TO ITS FUNCTIONALITY,
#OPERABILITY, OR USE, INCLUDING, WITHOUT LIMITATION,
#ANY IMPLIED WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE, OR INFRINGEMENT.
#WE EXPRESSLY DISCLAIM ANY LIABILITY WHATSOEVER FOR ANY DIRECT,
#INDIRECT, CONSEQUENTIAL, INCIDENTAL OR SPECIAL DAMAGES,
#INCLUDING, WITHOUT LIMITATION, LOST REVENUES, LOST PROFITS,
#LOSSES RESULTING FROM BUSINESS INTERRUPTION OR LOSS OF DATA,
#REGARDLESS OF THE FORM OF ACTION OR LEGAL THEORY UNDER
#WHICH THE LIABILITY MAY BE ASSERTED,
#EVEN IF ADVISED OF THE POSSIBILITY OR LIKELIHOOD OF SUCH DAMAGES.
#---------------------------------------------------------------------------
#

=head3 description

This is the batch program that reads files created by gammu, 
see http://www.gammu.org/wiki/index.php?title=Gammu:SMSD
processes them and unlinks them.

 On a linux system it can be run as a cron job
 or in a default form as a button controlled cgi
 
 Currently it is designed to read unicode format gammu sms files
 in the directory configured below

 If the data is not unicode, then removing
 
   $sms_data =~ s/\376\377// ; # remove binary stuff at start
   $sms_data = decode('UCS-2',lc($sms_data));                 

will probably work...ymmv...

 To install as cron:

 change lib path and hardcode registry name, for example

 This is the format for the input file name from gammu, contains
 date, time and phone number:
 IN20081112_114152_00_+447779159452_00.txt 

 Note:

=cut

#-------------------------------------------------------------

use strict;
use locale;
use lib '../../../lib';

# use Log::Log4perl;
# Log::Log4perl->init($configuration{'loggerconfig'});
# our $log = Log::Log4perl->get_logger("readfromgammu");

use Ccadmin;
use Cccookie;
use Ccu;
use Ccconfiguration;
use Ccinterfaces;

my %configuration = readconfiguration();

#FIXME: Only need SOAP if non-local update...
# fixed needs testing
if ( !$configuration{'smslocal'} ) {
    use SOAP::Lite;
}

my $token;
my $file;

# -----------------------change these if necessary-----------------------------------

my $cookieref = get_cookie();
my %fields    = cgiparse();

# for cron: hardcode registry, cannot be read from web cookie
my $registry = $$cookieref{registry};

my $local = $configuration{'smslocal'
  }; # set local = 1 if this script is on the same computer as the rest of cclite
my $domain =
  $configuration{'domain'};    # remote domain if the script is not local

my $sms_dir = "$configuration{'smspath'}/$registry"
  ;    # sms inbox for gammu, now divided by registry 11/2009
my $sms_done_dir = "$configuration{'smsout'}/$registry";

#------------------------------------------------------------------------------------

#$log->info("read_from_gammu started: $local $sms_dir") ;

opendir( DIR, $sms_dir );

while ( defined( $file = readdir(DIR) ) ) {

    next
      if ( $file !~ /\056txt$/ );  # not a txt extension, standard for gammu sms
    my $sms_file  = "$sms_dir/$file";
    my $file_done = "$sms_done_dir/$file";

# parse file name and extract timing data and phone number, timing not used at present
# but useful if, for example, interface is off-lined

    # IN20081203_211658_00_+447779159452_00.txt

    $sms_file =~
m/IN(\d{4})(\d{2})(\d{2})\_(\d{2})(\d{2})(\d{2})\_00\_\+(\d{2})(\d+)\_00\.txt/;

    my ( $sms_year, $sms_month, $sms_day, $sms_hour, $sms_minute, $sms_second,
        $sms_int_code, $sms_phone_number )
      = ( $1, $2, $3, $4, $5, $6, $7, $8 );

    my $full_telephone_number = $sms_int_code . $sms_phone_number;

    open( SMS, $sms_file );

    my $sms_data;    # holds message text

    while (<SMS>) {
        $sms_data .= $_;
    }
    close SMS;

    $sms_data =~ s/\376\377//;    # remove binary stuff at start

    # convert to current gateway format
    $fields{'originator'} = $sms_phone_number;
    $fields{'message'}    = $sms_data;
    $fields{'status'}     = 0;                   # status is forced

    my ( $status, $class, $array_ref, $soap, $token );

# remote transactions are transported via soap, local ones use the local library...
    if ( !$local ) {
        eval {
            $soap =
              SOAP::Lite->uri("http://$domain/Ccinterfaces")
              ->proxy("http://$domain/cgi-bin/ccserver.cgi")
              ->gateway_sms_transaction( \%configuration, \%fields, $token );
        };
        die $soap->faultstring if $soap->fault;
        ( $class, $status, $array_ref ) = $soap->paramsout;

    } else {
        gateway_sms_transaction( 'local', \%configuration, \%fields, $token );
    }

    # move the processed file to a done directory, don't process twice
    system("mv $sms_file $file_done");
}

closedir(DIR);
exit 0;

