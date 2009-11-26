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
print STDOUT <<EOT;
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<meta name="description" content="cclite community currency system" />
<meta name="keywords" content="LETS CC" />
<meta name="author" content="hugh barnard" />

<link type="text/css" href="/styles/cc.css" rel="stylesheet">
<title>Cclite: Check and diagnose install</title></head>
<body>
<div id="page" align="left">
	<div id="page" align="center">
		<div id="toppage" align="center">
			<div id="date">
				<div class="smalltext" style="padding:13px;"><strong>Cclite Check Install</strong></div>
			</div>
			<div id="topbar">
				<div align="right" style="padding:12px;" class="smallwhitetext">
 
<input type=button value="Back" onClick="history.go(-1)">
<!-- menu here -->

</div>
			</div>
		</div>
		<div id="header" align="center">
			<div class="titletext" id="logo">
Cclite
                             <div align="right" style="padding:12px;" class="smalltext"></div>
				<div class="logotext" style="margin:30px"><span class="orangelogotext"></span></div> 
			</div>
			<div id="pagetitle">

				<div id="title" class="titletext" align="right"></div>
                                <span class="news"></span>
			</div>
		</div>
		<div id="content" align="center">
			<div id="menu" align="right">
				<div align="right" style="width:189px; height:8px;"><img src="/cclite/images/mnu_topshadow.gif" width="189" height="8" alt="mnutopshadow" /></div>
				<div id="linksmenu" align="center">

<!-- menu here -->
<!-- autocomplete search boxes -->
<!-- end of autocomplete search boxes -->


				</div>
				<div align="right" style="width:189px; height:8px;"><img src="/cclite/images/mnu_bottomshadow.gif" width="189" height="8" alt="mnubottomshadow" /></div>
			</div>

		<div id="contenttext">
 
			<div class="bodytext" style="padding:12px;" align="justify">

<div>Running Tests...</div>
EOT

use strict;
use Test::More qw(no_plan);

# check that all the perl modules are installed
# some of these are optional, there's a test at the end
print "<div class=\"system\">";
my $dbi = use_ok('DBI');
print " ";
my $mail = use_ok('Mail::Sendmail');
print " ";
my $sha2 = use_ok('Digest::SHA2');
print " ";
my $sha1 = use_ok('Digest::SHA1');
print " ";
my $soap = use_ok('SOAP::Lite');
print " ";
my $rss = use_ok('XML::RSS');
print " ";
my $xml = use_ok('XML::Simple');
print " ";
my $log = use_ok('Log::Log4perl');
print " ";
my $lwp = use_ok('LWP::Simple');
print " ";
my $carp = use_ok('CGI::Carp');
print " ";
my $mail1 = use_ok('Net::SMTP');
print " ";

#FIXME: add check for CGI modules used by ccupload at least!

# gd modules only needed for graphs
my $gd_main = use_ok('GD');
print " ";
my $gd_text = use_ok('GD::Text');
print " ";
my $gd_lines = use_ok('GD::Graph::lines');
print " ";
my $gd_bars = use_ok('GD::Graph::bars');
print "<br/></div>";

# end of perl module testing

my $gammu_found = `which gammu`;
my $sendmail    = '/usr/sbin/sendmail';

my $diagnosis;

if ( ( $log && $dbi && $mail && $carp ) && ( $sha1 || $sha2 ) ) {
    $diagnosis .= "<div class=\"system\"><b>cclite is usable</b></div>";
} else {
    $diagnosis .=
      "<div class=\"failedcheck\"><b>cclite is  not usable</b></div>";
}

if ( -e $sendmail ) {
    $diagnosis .=
      "<div class=\"system\">cclite can use local sendmail at $sendmail</div>";
} else {
    $diagnosis .=
"<div class=\"failedcheck\">$sendmail: cclite must use smtp server elsewhere</div>";
}

$diagnosis .=
  "<div class=\"system\">cclite can access mysql database from perl</div>"
  if ($dbi);
$diagnosis .= "<div class=\"system\">cclite can send mail from socket</div>"
  if ($mail);
$diagnosis .=
"<div class=\"system\">cclite can send mail from server,<i> this is preferred</i></div>"
  if ($mail1);
$diagnosis .= "<div class=\"system\">cclite can use sha1</div>" if ($sha1);
$diagnosis .=
"<div class=\"system\">cclite can use SOAP to update remote servers for SMS and transactions</div>"
  if ($soap);

$diagnosis .= "<div class=\"system\">cclite can produce rss</div>"
  if ( $rss && $xml );
$diagnosis .= "<div class=\"failedcheck\">cclite can't produce rss</div>"
  if ( !( $rss || $xml ) );
$diagnosis .=
"<div class=\"system\">cclite is sms capable with local phone: gammu found</div>"
  if ( length($gammu_found) );
$diagnosis .=
"<div class=\"failedcheck\">cclite can't use SOAP to update remote servers for SMS and transactions</div>"
  if ( !$soap );
$diagnosis .=
"<div class=\"failedcheck\">cclite can't use sms locally from an attached phone: need gammu</div>"
  if ( !length($gammu_found) );
$diagnosis .=
"<div class=\"system\">cclite can use sha2 and <i>this is preferred</i> over sha1</div>"
  if ($sha2);

# added carp for catching last ditch errors that would otherwise generate a 500
$diagnosis .=
"<div class=\"system\">cclite can use CGI::Carp to output fatal errors directly</div>"
  if ($carp);
$diagnosis .=
"<div class=\"failedcheck\">cclite needs CGI::Carp to output fatal errors directly</div>"
  if ( !$carp );

$diagnosis .=
"<div class=\"failedcheck\">cclite cannot send mail from server,<b> this is preferred to Mail::Sendmail</b></div>"
  if ( !$mail1 );

# added GD, but Cclite can work without this!
if ( $gd_main && $gd_text && $gd_lines && $gd_bars ) {
    $diagnosis .= "<div class=\"system\">cclite can use GD for graphing</div>";
} else {
    $diagnosis .=
      "<div class=\"failedcheck\">cclite cannot use GD for graphing</div>";
}

$diagnosis .=
"<div class=\"failedcheck\">cclite cannot send mail from server,<b> this is preferred</b></div>"
  if ( !$mail1 );

print <<EOT;


			</div>
			<div class="panel" align="justify">

<div>Analysis</div>				
$diagnosis
<!-- bottom text here-->
				<span class="bodytext">


			
</span>			</div>
			</div>
		</div>
		<div id="footer" class="smallgraytext" align="center">
			<a href="#">Home</a> | <a href="#">Contact Us</a><br />
			Cclite &copy; Hugh Barnard 2003-2009
		</div>
	</div>
</body>
</html>
EOT

exit 0;
