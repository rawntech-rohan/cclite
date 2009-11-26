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

=head1 NAME

ccupload.cgi

=head1 SYNOPSIS

upload for Cclite batch files

=head1 DESCRIPTION

This will probably be extended to allow upload of user content for example

=head1 AUTHOR

Hugh Barnard



=head1 SEE ALSO

cclite.cgi
=head1 COPYRIGHT

(c) Hugh Barnard 2005 GPL Licenced 

=cut

BEGIN {
    use CGI::Carp qw(fatalsToBrowser set_message);
    set_message(
"Please use the <a title=\"cclite google group\" href=\"http://groups.google.co.uk/group/cclite\">Cclite Google Group</a> for help, if necessary"
    );

}

use strict;
use lib "../../lib";

use Log::Log4perl;

use CGI;    # uses CGI, perhaps eliminate this?
use HTML::SimpleTemplate;
use Ccu;
use Cclite;
use Cccookie;
use Ccconfiguration;    # new 2009 style configuration supply...

my $cookieref = get_cookie();

my %configuration;
%configuration = readconfiguration();

Log::Log4perl->init( $configuration{'loggerconfig'} );
our $log = Log::Log4perl->get_logger("ccupload");

# note that uploads are per registry as of 10/2009
my $upload_dir = "$configuration{csvpath}/$$cookieref{registry}";

my $query = new CGI;

my ( $fieldsref, $refresh, $metarefresh, $error, $html, $token, $db, $cookies,
    $templatename, $registry_private_value );    # for the moment

my $language = $$cookieref{language} || "en";    # default is english
my %messages = readmessages($language);

#---------------------------------------------------------------
# A template object referencing a particular directory
#-------------------------------------------------------------------
# Change this if you change where the templates are...
#-------------------------------------------------------------------
my $pages     = new HTML::SimpleTemplate("$configuration{templates}/$language");
my $home      = $configuration{home};
my $user_home = $home;
$user_home =~ s/(\/protected)\/ccadmin.cgi/\/cclite.cgi/;

# since this uploads, need to be an admin and the cookies need to work
if ( $$cookieref{userLevel} ne 'admin' ) {
    display_template(
        "1",    $user_home,    "",         $messages{notanadmin},
        $pages, "result.html", $fieldsref, $cookies,
        $token
    );
    exit 0;
}

my $compare_token;

# there is a token but it's been modified or spoofed
if ( length( $$cookieref{token} ) && ( $compare_token != $$cookieref{token} ) )
{
    $log->warn(
"corrupt2 token or spoofing attempt from: $$cookieref{userLogin} $ENV{REMOTE_ADDR}\n"
    );
    $log->debug(
"corrupt token or spoofing attempt from:\n $$cookieref{token}) against\n $compare_token"
    );

    display_template( 0, "", "", "", $pages, "logon.html", $fieldsref, $cookies,
        $token );
    exit 0;
}

# A template object referencing a particular directory
$pages = new HTML::SimpleTemplate("$configuration{templates}/$language/admin");
my $upload_filehandle = $query->upload("batch");
my $filename          = $query->param("batch");
$filename =~ s/.*[\/\\](.*)/$1/;

if ( !length($filename) ) {
    display_template(
        $refresh,   $metarefresh,
        $error,     "no file name: try again",
        $pages,     "result.html",
        $fieldsref, $cookies,
        $token
    );
    exit 0;
}
if ( $filename !~ /\056csv$/i ) {
    display_template( $refresh, $metarefresh, $error,
        "not a csv extension file: try again",
        $pages, "result.html", $fieldsref, $cookies, $token );
    exit 0;
}

open UPLOADFILE, ">$upload_dir/$filename";
binmode UPLOADFILE;
while (<$upload_filehandle>) {
    print UPLOADFILE;
}

close UPLOADFILE;
display_template( $refresh, $metarefresh, $error,
    "file uploaded: processed within 1 hour",
    $pages, "result.html", $fieldsref, $cookies, $token );
exit 0;

