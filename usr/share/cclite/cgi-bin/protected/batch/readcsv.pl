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

print STDOUT "Content-type: text/html\n\n";

# this should result in errors printed in the status line of the management page
my $data = join( '', <DATA> );
eval $data;
if ($@) {
    print $@;
    exit 1;
}

__END__


=head3 readconfiguration

Read the configuration data and return a hash, this routine
also exists in ccserver.cgi


Skip comments marked with #
cgi parameters will override configuration file
information, always!

Included here, needs to be executed within BEGIN

Standard version, since batch scripts are now
within a cgi subdirectory

=cut



#-----------------------------------------------------------
# This is the batch program that reads comma separated variable files,
# processes them and unlinks them.
#
# On a linux system it will be run as a cron job..on some
# Windows, as an 'at' of some kind, I guess.
#
# Currently it is designed to read any file of form
# in the directory chosen for receiving csv files
#
# To install:
#
# Probably there'll be a batch
# file per registry, but currently this is not necessary. At the
# time Gpg is applied, it will probably become so.
#
# make sure that the html/out directory is writable or remove
# the logic that deals with that...






use strict;    # all this code is strict
use locale;
use lib '../../../lib' ;	
#-------------------------------------------------------------

#use Log::Log4perl;

use Ccu;
use Cccookie ;
use Ccinterfaces;
use Ccconfiguration;

my $token;
my $file;
my %configuration;

%configuration = readconfiguration();

#Log::Log4perl->init($configuration{'loggerconfig'});
#our $log = Log::Log4perl->get_logger("readcsv");

my $cookieref = get_cookie();
my %fields    = cgiparse();

# cron: hardwire the registry name into the script
my $registry = $$cookieref{registry} ;

# timestamp output files so that they don't get confused
my ($numeric_date,$time) = getdateandtime(time()) ;

#--------------------------------------------------------------
# change these two, if necessary, note that as of 2009, files are by registry

my $csv_dir = "$configuration{csvpath}/$registry" ;    # csv directory

if (-e $csv_dir && -w $csv_dir) {
} else {
  print "$csv_dir does not exist or is not writable\n";
  exit 1 ;
}

opendir( DIR, $csv_dir );

while ( defined( $file = readdir(DIR) ) ) {
    next if ( $file !~ /\056csv$/ );      # not a csv extension, small comfort!
    my $csv_file = "$csv_dir/$file";
    print "processing $csv_file\n" ;
    # registry and configuration passed into this now, paths per registry etc. 10/2009
    read_csv_transactions( 'local', $registry, 'om_trades', $csv_file,
        \%configuration,
        $token, "", "" );

    # give the input file a 'done' extension so that it doesn't get re-processed
    system("mv $csv_file $csv_file\056done\056$numeric_date$time");
}

closedir(DIR);
exit 0;

