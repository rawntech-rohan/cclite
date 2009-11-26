#!/usr/bin/perl -w

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

=head1 NAME
 
cclite.cgi


=head1 SYNOPSIS

Controller for user side Cclite

=head1 DESCRIPTION

Controller to find and dispatch various actions
 this is the version 2 controller for cclite:

 - multiple registry, registry passed in %fields
 - multiple transaction, logon and transfer can be one operation
 - maximum simplicity, nearly everything is passed as %fields
 - sha1, ip + user + value based hashing
 - internal key never transmitted over network
 - mysql based database + DBI + ODBC (can even be access, for example)
 - web services retained
 - multilingual elements provided by translating screens + cookie
 - maximum use of static html for lightweight running
 - Taint flag should be on in final version, anyway


=head1 AUTHOR

Hugh Barnard


=head1 COPYRIGHT

(c) Hugh Barnard 2005 GPL Licenced 

=cut

use lib "../../lib";
use strict;    # all this code is strict
use locale;

use HTML::SimpleTemplate;    # templating for HTML

use Log::Log4perl;

use Ccu;                     # utilities + config + multilingual messages
use Cccookie;                # use the cookie module
use Ccvalidate;              # use the validation and javascript routines
use Cclite;                  # use the main motor
use Cchooks;                 # API hooks, pretty empty at present
use Ccdirectory;             # yellow pages directory etc.
use Ccsecure;                # security and hashing
use Cclitedb;                # this probably should be delegated
use Ccinterfaces;            # don't need this for sms gateway?
use Ccsmsgateway;            # sms gateway specific processing
use Ccconfiguration;         # new 2009 style configuration

$ENV{IFS} = " ";             # modest security

my ( $fieldsref, $refresh, $metarefresh, $error, $html, $token, $db, $cookies,
    $templatename, $registry_private_value );    # for the moment

my $cookieref = get_cookie();
my %fields    = cgiparse();

# our because it's shared with the Ccsmsgateway package
our %configuration;
our $configurationref;
%configuration    = readconfiguration();
$configurationref = \%configuration;

# no soap and associated modules required,
# if you declare multiregistry=no in cclite.cf
if ( $configuration{multiregistry} eq "yes" ) {
    require SOAP::Lite;    # uses this for remote lookups etc.
    import SOAP::Lite;
}

Log::Log4perl->init( $configuration{'loggerconfig'} );
our $log = Log::Log4perl->get_logger("ccsmsgateway");

#  this should use the version modules, but that makes life more
# complex for intermediate users

$fields{version} = $configuration{version};

#  this is part of conversion to transaction engine use. web mode, which
#  is the default will deliver html etc. engine mode will deliver data
#  as hash references, for example. There are quite a few things called 'mode'
#  in Cclite.pm, needs sorting out.

$fields{mode} = 'html';

#  this is the remote address from the client. It acts as a simple check in a direct
#  pay transaction from the REST interface. This is obviously not sufficient and
#  will get upgraded in the future

$fields{client_ip} = $ENV{REMOTE_ADDR};

#---------------------------------------------------------------------------
#
( $fields{home}, $fields{domain} ) =
  get_server_details();    # this is in Ccsecure, may need extra measures

$fields{initialPaymentStatus}   = $configuration{initialpaymentstatus};
$fields{systemMailAddress}      = $configuration{systemmailaddress};
$fields{systemMailReplyAddress} = $configuration{systemmailreplyaddress};

#--------------------------------------------------------------------
# This is the token that is to be carried everywhere, preventing
# session hijack etc. It's probably going to be a GnuPg public key
# anyway it's a public key of some king related to the cclite installations
# private key, not transmitted and protected by passphrase
#
$token = $registry_private_value =
  $configuration{registrypublickey};    # for the moment, calculated later
my $fieldsref = \%fields;

gateway_sms_transaction( $configurationref, $fieldsref, $token )
  ;                                     # mobile number + raw string

# this is mainly to make Selenium etc. work...
print "Content-type: text/html\n\nrunning\n";

exit 0;

