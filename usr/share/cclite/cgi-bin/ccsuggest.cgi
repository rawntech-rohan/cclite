#!/usr/bin/perl 

=head3 get_sql

Get the sql statement for the appropriate autosuggest type
All this depends on cclite.js which fires various bits of jquery

=cut

sub get_sql {

    my ( $level, $userLogin, $type, $query_string ) = @_;
    my $sql;

    # deals with suggesting destination for trade or user search

    if ( $type eq 'user' ) {

        $sql = <<EOT;
SELECT userLogin FROM `om_users` 
 WHERE (userLogin LIKE \'\%$query_string\%\'
        AND userLevel <> \'sysaccount\' 
        AND userLogin <> \'$userLogin\' )
 LIMIT 0 , 10; 
                
EOT

    }

    # suggest yellowpages responding to search

    elsif ( $type eq 'ad' ) {

        $sql = <<EOT;
SELECT subject FROM `om_yellowpages` 
                        WHERE ( type LIKE \'\%$query_string\%\' 
                        OR category LIKE \'\%$query_string\%\' 
                        OR keywords LIKE \'\%$query_string\%\'
                        OR subject LIKE \'\%$query_string\%\' )
LIMIT 0 , 10 ;

EOT

    }

    # suggests replies to trade search

    elsif ( $type eq 'trade' ) {

        # admin can search for any trade
        if ( $level eq 'admin' ) {
            $sql = <<EOT;
SELECT tradeTitle,tradeStatus FROM `om_trades` 
         WHERE (tradeTitle LIKE \'\%$query_string\%\' 
                OR tradeHash LIKE \'\%$$query_string\%\' 
                OR tradeStatus LIKE \'\%$query_string\%\') 
LIMIT 0 , 10 ;
 

EOT

            # non admin can search within trades that concern them
        } else {
            $sql = <<EOT;
SELECT tradeTitle,tradeStatus FROM `om_trades` 
         WHERE ((tradeTitle LIKE \'\%$query_string\%\' 
                OR tradeHash LIKE \'\%$query_string\%\' 
                OR tradeStatus LIKE \'\%$query_string\%\') 
                AND (tradeSource = \'$userLogin\' OR tradeDestination = \'$userLogin\'))
LIMIT 0 , 10 ;
 

EOT

        }

        # special case, will produce a reply when new user name is unique

    } elsif ( $type eq 'newuser' ) {
        $sql =
"SELECT userLogin FROM `om_users` WHERE userLogin LIKE \'\%$query_string\%\' LIMIT 0 , 10";

    }

    return $sql;
}

BEGIN {
    use CGI::Carp qw(fatalsToBrowser set_message);
    set_message(
"Please use the <a title=\"cclite google group\" href=\"http://groups.google.co.uk/group/cclite\">Cclite Google Group</a> for help, if necessary"
    );
    print STDOUT "Content-type: text/html\n\n";
}

use lib '../lib';

use strict;    # all this code is strict
use locale;

# logger must be before Cc modules, since loggers are
# defined within those modules...
use Log::Log4perl;
use Ccu;           # utilities + config + multilingual messages
use Cccookie;      # use the cookie module
use Ccvalidate;    # use the validation and javascript routines
use Cclite;        # use the main motor
use Ccsecure;      # security and hashing
use Cclitedb;      # this probably should be delegated

$ENV{IFS} = " ";   # modest security

my ( $fieldsref, $refresh, $metarefresh, $error, $html, $token, $db, $cookies,
    $templatename, $registry_private_value, $sql, $newuser, $search_type )
  ;                # for the moment

my $cookieref = get_cookie();

# registry1 is filled for newuser suggest, this is ugly but it avoids the untraceable
# bug where the value of the registry cookie is cumulated. Exists on mailing lists but
# no-one seems to have solved it 10/2009

my $db       = $$cookieref{registry} || $$cookieref{registry1};
my %fields   = cgiparse();
my %messages = readmessages();

$fields{'version'} = '0.6.0';

# $fields{'q'} is the query string
# $fields{'type'} is the type of query and therefore table used etc.
# all this supplied by jquery now via cclite.js as of 10/2009

# return if there's no token and we're not finding a unique name for a new user
# don't want to expose the interior of the database to non-logged on users
# FIXME: this token should be recalculated and compared...

if ( !length( $$cookieref{'token'} ) ) {

    #FIXME: Message should go in message file
    ###print $messages{'loginfirst'} ;
    if ( $fields{'type'} ne 'newuser' ) {
        print "log in first!";
        exit 0;
    }
}

#FIXME:  Problem with registry name, last character delivered by cookie in this case...
if ( $fields{'type'} eq 'newuser' ) {
    $db = substr $db, 0, -1;
}

# get the sql string corresponding to the autosuggest
my $sql =
  get_sql( $$cookieref{userLevel}, $$cookieref{userLogin}, $fields{'type'},
    $fields{'q'} );

my ( $registryerror, $array_ref ) =
  sqlraw_return_array( 'local', $db, $sql, '', $token );

my $menu_select;
my $menu_count = 0;

foreach my $row_ref (@$array_ref) {
    my $menu_item;
    $menu_count++;
    $menu_item = substr( $$row_ref[0], 0, 15 );
    $menu_select .= "$menu_item\n";

}

# normal search suggest output

if ( $fields{'type'} ne 'newuser' ) {
    print $menu_select ;
}

# output for new user

else {
    if ( $fields{'q'} !~ /[^\w]/ ) {
        print "$fields{'q'} is a valid/unique account name"
          if ( $menu_count == 0 );
    } else {
        print "$fields{'q'} must contain a-z, 1-9 only" if ( $menu_count == 0 );
    }
}

exit 0;
