#!/usr/bin/perl

=head1 description

write.rss writing news feeds for cclite adverts

THE cclite SOFTWARE IS PROVIDED TO YOU "AS IS," AND WE MAKE NO EXPRESS
OR IMPLIED WARRANTIES WHATSOEVER WITH RESPECT TO ITS FUNCTIONALITY, 
OPERABILITY, OR USE, INCLUDING, WITHOUT LIMITATION, 
ANY IMPLIED WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE, OR INFRINGEMENT. 
WE EXPRESSLY DISCLAIM ANY LIABILITY WHATSOEVER FOR ANY DIRECT, 
INDIRECT, CONSEQUENTIAL, INCIDENTAL OR SPECIAL DAMAGES, 
INCLUDING, WITHOUT LIMITATION, LOST REVENUES, LOST PROFITS, 
LOSSES RESULTING FROM BUSINESS INTERRUPTION OR LOSS OF DATA, 
REGARDLESS OF THE FORM OF ACTION OR LEGAL THEORY UNDER 
WHICH THE LIABILITY MAY BE ASSERTED, 
EVEN IF ADVISED OF THE POSSIBILITY OR LIKELIHOOD OF SUCH DAMAGES. 

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut

#

print STDOUT "Content-type: text/html\n\n";
my $data = join( '', <DATA> );
eval $data;
if ($@) {
    print $@;
    exit 1;
}

__END__

#-----------------------------------------------------------
# This is the batch program that writes rss files.
# When a new advert arrives it will be inlcuded in the rss
#
# On a linux system it will be run as a cron job..on some
# Windows, as an 'at' of some kind, I guess.
# 
#
# To install:
#
# Change the library path and the database array, since
# this is installation dependent. Probably, one mail file
# will belong to one registry
#
# use sudo apt-get install liferea for example to read the 
# resulting feeds which are at an url like:
# http://cclite.private.server/cclite/html/en/rss/limehouse.rdf
# for a registry called limehouse, for example

# use Log::Log4perl;
# Log::Log4perl->init($configuration{'loggerconfig'});
# our $log = Log::Log4perl->get_logger("writerss");


use lib "$configuration{librarypath}";	
use Ccu;
use Ccrss ;
use Cccookie ; # to get the registry token from the admin page...
use Ccconfiguration ;

my $token ;


# you'll have to hardcode these, if this is a cron
my $cookieref = get_cookie();
my $registry = $$cookieref{registry} ;
my $language = $$cookieref{language} ;

my  %configuration  = readconfiguration();

# these are the feed types, all ads, wanted ads, offered ads and matched ads, change this to the feeds that you need
my @types = (all, wanted, offered, match) ;

my %fields ;

# this is the path where the rss files are written
# needs to be writable by the server, rss is now by registry and by language

$fields{'rsspath'}  =   $configuration{'rsspath'} ;
$fields{'language'} =   $language ;

if (-e $fields{'rsspath'} ) {
} else {
   
  mkdir($fields{'rsspath'}, 0777) || print $!;
  exit 1 ;
}

my $email = $configuration{supportmail} ;

# simply loop around each registry creating an rdf file 
# for the type of advert for each one
 my $entry ;
 
foreach $type (@types) {
 
   $fields{type}	= $type ;
   my $fieldsref 	= \%fields ;
 my ($refresh,$metarefresh,$error,$html,$pagename,$cookies) 	= create_rss_feed('local',$configuration{'home'},'desc',$email,$registry,'om_yellowpages',$fieldsref,$token) ;
}

exit 0 ;

