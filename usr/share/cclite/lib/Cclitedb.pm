
=head1 NAME

Cclitedb.pm

=head1 SYNOPSIS

Database routines for Cclite

=head1 DESCRIPTION

This contains all the database routines and static SQL for cclite and some utility routines
to add a function:
 1.  add a routine to generate SQL here 
 2.  add it to the export list below
 3.  use it in on of the main programs
The token is calculated from session info, remote address and an internal registry
key. It diminishes session hijack risk
November 2004: Limit clauses added to _sqlgetwhere _sqlgetall _sqlfind
=head1 AUTHOR

Hugh Barnard

=head1 BUGS


=head1 SEE ALSO

Cclite.pm

=head1 COPYRIGHT

(c) Hugh Barnard 2005-2007 GPL Licenced 
=cut

package Cclitedb;
use strict;
use vars qw(@ISA @EXPORT);
use Exporter;
use DBI;
use Ccsecure;
use Ccconfiguration;

###DBI->trace( 4, '../debug/debug.dbi' );      # Database abstraction
use Ccu;    # for paging routine, at least
my $VERSION = 1.00;
@ISA = qw(Exporter);

our $log = Log::Log4perl->get_logger("Cclitedb");

#---------------------------------------------------------
# note the sql ones almost certainly shouldn't be exported!

@EXPORT = qw(check_db_and_version
  add_database_record
  add_database_record_dbh
  update_database_record
  modify_database_record
  modify_database_record2
  delete_database_record
  find_database_records
  makebutton
  makebox
  makelink
  makehome
  sqlget
  sqlgetall
  sqlcount
  get_where
  get_where_return_array
  get_where_multiple
  get_table_columns
  registry_connect
  server_hello
  show_record
  sqlinsert
  sqlupdate
  sqlgetpeople
  sqlfind
  sqlraw
  sqlraw_return_array
  sqldelete
  makecolumns);

=head3 add_database_record

Add a record to the cclite database
now very general should work out which fields to insert via 'describe'

=cut

sub add_database_record {
    my $rc;
    my $record_id;
    my ( $class, $db, $table, $fieldsref, $token ) = @_;

    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my $insert = _sqlinsert( $dbh, $table, $fieldsref, $token );
    my $sth    = $dbh->prepare($insert);
    my $rv     = $sth->execute();
    my $error  = $sth->errstr();
    $dbh->disconnect();
    return ( $error, $record_id );
}

=head3 add_database_record_dbh

Add a record to the cclite database
now very general should work out which fields to insert via 'describe'
Version to be used in transactions, connect is outside the routine

=cut

sub add_database_record_dbh {
    my $rc;
    my $record_id;
    my ( $class, $dbh, $table, $fieldsref, $token ) = @_;

    my $insert = _sqlinsert( $dbh, $table, $fieldsref, $token );
    my $sth    = $dbh->prepare($insert);
    my $rv     = $sth->execute();
    my $error  = $sth->errstr();
    $dbh->disconnect();
    return ( $error, $record_id );
}

=head3 show_record

show detail for a database record
very rudimentary at present, packs up record into table
and returns as result

=cut

sub show_record {
    my ( $class, $db, $table, $fieldsref, $token ) = @_;

    #---------------------------------------------------
    # Note kludge to deal with irregular id fields
    my %id_fields = qw(om_users userId om_trades tradeId);
    my $id        = "id";
    $id = $id_fields{$table} if ( exists $id_fields{$table} );

    #----------------------------------------------------
    my ( $status, $returnref ) =
      get_where( $class, $db, $table, $id, $$fieldsref{$id}, $token, "", "" );
    my $html;

    foreach my $key ( keys %$returnref ) {

        # disambiguate userLogin for display: duserLogin = display userLogin
        # hence this should be used in any display templates
        $$fieldsref{duserLogin} = $$returnref{userLogin}
          if ( $key eq "userLogin" );
        $html .= <<EOT;
   <tr><td class="pme-key-1">$key</td><td class="pme-value-1">$$returnref{$key}</td></tr>
EOT

    }
    $html = "<table><tbody class=\"stripy\">$html</tbody></table>";

    # default result.html is used, if no template is supplied
    my $template;
    if ( !length( $$fieldsref{resulttemplate} ) ) {
        $template = "result.html";
    } else {
        $template = $$fieldsref{resulttemplate};
    }
    return ( "", "", "", $html, $template, $fieldsref );
}

=head3 update_database_record

This is used by registry modification transaction, do not remove

Simplest one, but uses hash exclusively, will it work as a web service?
So far, we have:
update_database_record : raw
modify_database_record : produces form: keep and generalise
modify_database_record2 : where

Need to eliminate one of these!

=cut

sub update_database_record {

    # note useid is 1 for using the id field in where
    #               2 for using the user logon

    my ( $class, $db, $table, $useid, $fieldsref, $language, $token ) = @_;
    my ( $html, %messages, $messagesref );

    # deals with no language problem
    #FIXME: In Ccsmsgateway language delivers notused why is this?
    # duplicated language code with Ccu
    if ( !length($messagesref) ) {
        my $language = 'en' if ( !length($language) || $language eq 'notused' );
        %messages    = Ccu::readmessages($language);
        $messagesref = \%messages;
    }

    if ( $table eq 'om_users' && $$fieldsref{action} eq "update" ) {
        $$fieldsref{registry} = $db;
        my @status =
          Ccvalidate::validate_user( $class, $db, $fieldsref, $messagesref,
            $token, "", "" );

        # need to sort out status values throughout
        if ( $status[0] == -1 ) {
            shift @status;
            $html = join( "<br/>", @status );
            return ( "0", '', "", $html, "result.html", $fieldsref );
        }

        # hash password: corrected 18/10/2009 for 0 zero url type
        $$fieldsref{userPassword} =
          Ccsecure::hash_password( 0, $$fieldsref{userPassword} )
          if length( $$fieldsref{userPassword} );

        # unlock the password if administrator and Password changed
        if ( is_admin() && length( $$fieldsref{userPassword} ) ) {
            $$fieldsref{userPasswordTries}  = 3;
            $$fieldsref{userPasswordStatus} = 'active';
        }

        $$fieldsref{userPin} = text_to_hash( $$fieldsref{userPin} )
          if length( $$fieldsref{userPin} );
        $$fieldsref{userMobile} =
          format_for_uk_mobile( $$fieldsref{userMobile} )
          if length( $$fieldsref{userMobile} );

        # unlock the SMS PIN if administrator and PIN changed
        if ( is_admin() && length( $$fieldsref{userPin} ) ) {
            $$fieldsref{userPinTries}  = 3;
            $$fieldsref{userPinStatus} = 'active';
        }

    }

    
    my ( $rv, $rc, $record_id );
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my $update = _sqlupdate( $dbh, $table, $useid, $fieldsref, $token );
    
    $log->debug("update is $update") ;
    
    my $sth = $dbh->prepare($update);
    $sth->execute();

    #FIXME: Some tables still haven't literals
    my $table_literal = $messages{$table} || $table;

    $html = "$table_literal record $$fieldsref{id} $$fieldsref{action}";
    return ( 1, $$fieldsref{home}, "", $html, "result.html", $fieldsref );
}

=head3 delete_database_record

Delete a database record. Compensates for different ids
within tables due to use of tiki schema. Ugly at present
but functioning

=cut

sub delete_database_record {
    my ( $class, $db, $table, $fieldsref, $token ) = @_;
    my ( $error, $html, $record_id );
    my $id;

    # compensate for different id names in tables, ugly
    my %translate = qw(om_trades tradeId om_users userId);
    if ( exists $translate{$table} ) {
        $id = $translate{$table};
    } else {
        $id = "id";
    }
    my $delete = _sqldelete( $table, $id, $$fieldsref{$id} );
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my $sth = $dbh->prepare($delete);
    $sth->execute();
    my $error = $dbh->errstr();

    # this is not multilingual to be fixed
    $html = "$table record $$fieldsref{$id} deleted" if ( !length($error) );
    return ( "1", $$fieldsref{home}, $error, $html, "result.html", "" );
}

=head3 sqlcount

Count a set of records in the database, either to output
as a guide figure or to make pagination information

Can be done via sqlstring or where

This needs to return an error too

=cut

sub sqlcount {
    my ( $class, $db, $table, $sqlstring, $fieldname, $value, $token ) = @_;
    my ( $registryerror, $dbh ) = _registry_connect( $db, $token );

    # count all the transactions belonging to the current user
    my $sqlcount = _sqlcount( $table, $sqlstring, $fieldname, $value, $token );
    my $sth = $dbh->prepare($sqlcount);
    $sth->execute();
    my @row   = $sth->fetchrow_array;
    my $count = $row[0];
    return $count;
}

=head3 sqlraw

Sql raw a given piece of sql. 
Does not allow update or delete used for complex joins etc.
change to hash_ref, self-describing but problematic in soap calls

=cut

sub sqlraw {
    my ( $class, $db, $sqlstring, $id, $token ) = @_;
    my ( $rc, $rv, $hash_ref );

    # remove all modification attempts!
    $sqlstring =~ s/delete|insert|update//gi;
    my ( $registryerror, $dbh ) = _registry_connect( $db, $token );
    if ( length($dbh) ) {
        my $sth = $dbh->prepare($sqlstring);
        my $rv  = $sth->execute();
        $hash_ref = $sth->fetchall_hashref($id);
        $sth->finish();
    }

    # --- example of use---------------------------------
    # $hash_ref = $sth->fetchall_hashref('id');
    # print "Name for id 42 is $hash_ref->{42}->{name}\n";
    #----------------------------------------------------
    return ( $registryerror, $hash_ref );
}

=head3 sqlraw_return_array

returns an array, probably useful for web services
otherwise identical to sqlraw, probably should be
renamed to sql_raw_return_hash...

=cut

sub sqlraw_return_array {
    my ( $class, $db, $sqlstring, $id, $token ) = @_;
    my ( $rc, $rv, $array_ref );

    # remove all modification attempts!
    $sqlstring =~ s/delete|insert|update//gi;
    my ( $registryerror, $dbh );

    ( $registryerror, $dbh ) = _registry_connect( $db, $token );

    # cumulate any detail error with registry error 10/2009
    $registryerror .= $dbh->errstr() if length($dbh);
    ###$log->debug("$db $registryerror $sqlstring") ;
    if ( length($dbh) ) {
        my $sth = $dbh->prepare($sqlstring);
        my $rv  = $sth->execute();
        $array_ref = $sth->fetchall_arrayref();
        $sth->finish();
    }

    return ( $registryerror, $array_ref );
}

=head3 find_database_records

Find strings within a table
Makes a large OR using LIKE.
Very inefficient but works at present

This will now deliver all transactions into a find
that is done by the manager...be careful

=cut

sub find_database_records {
    my ( $class, $db, $table, $fieldsref, $cookieref, $token, $offset, $limit )
      = @_;
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my @columns = get_table_text_columns( $table, $dbh );
    my ( $count, $row_ref, $like, $string );

    # make a massive where statement for all textual columns
    foreach my $column (@columns) {
        $column = "$column LIKE \'%$$fieldsref{string}%\'";
    }
    $like = join( " or ", @columns );

    # constrain finds on om_trades to just the owner's records
    if ( $table eq "om_trades" && !is_admin() ) {

      # first select base set, only records for user, if not admin
      # debits and opening balances are user sourced, credits are remote sourced

        $like .= <<EOT;
and ((tradeSource = '$$cookieref{userLogin}' and (tradeType = 'debit' or tradeType = 'open'))
 or
 (tradeDestination = '$$cookieref{userLogin}' and  tradeType = 'credit')
)
EOT

    }

    # count all the transactions belonging to the current user
    # if om_trades otherwise count all records
    #
    $count =
      sqlcount( $class, $db, $table, $like, "tradeSource",
        $$cookieref{userLogin}, $token )
      if ( $table eq 'om_trades' );
    $count = sqlcount( $class, $db, $table, $like, "", "", $token )
      if ( $table ne 'om_trades' );

    # get the columns too
    my ( $registryerror, $column_array_ref ) =
      sqlraw_return_array( $class, $db, "describe $table", "", $token );

    my $find = _sqlfind( $table, $fieldsref, $like, "", $offset, $limit );

    my $sth = $dbh->prepare($find);
    $sth->execute();
    my $array_ref = $sth->fetchall_arrayref;

    $sth->finish();
    my $error = $dbh->errstr();
    return ( $registry_error, $count, $column_array_ref, $array_ref );
}

=head3 get_where

FIXME: This is throwing errors into the apache log
get a record via a single = field condition
should return one record only

=cut

sub get_where {
    my ( $class, $db, $table, $fieldname, $name, $token, $offset, $limit ) = @_;
    my $get =
      _sqlgetwhere( $name, $table, $fieldname, $token, $offset, $limit );

    my ( $rc, $rv, $hash_ref );
    my ( $registryerror, $dbh ) = _registry_connect( $db, $token );
    my ( $package, $filename, $line ) = caller;

   ###$log->debug("get_where:g:$get r:$registryerror p:$package, f:$filename, l:$line");

    if ( length($dbh) ) {
        my $sth = $dbh->prepare($get);
        my $rv  = $sth->execute();
        $hash_ref = $sth->fetchrow_hashref;
        $sth->finish();
    }
    return ( $registryerror, $hash_ref );
}

=head3 get_where_return_array

get a record via a single = field condition
returns an array for web services use

=cut

sub get_where_return_array {
    my ( $class, $db, $table, $fieldname, $name, $token, $offset, $limit ) = @_;
    my $get =
      _sqlgetwhere( $name, $table, $fieldname, $token, $offset, $limit );
    my ( $rc, $rv, @array );
    my ( $registryerror, $dbh ) = _registry_connect( $db, $token );
    if ( length($dbh) ) {
        my $sth = $dbh->prepare($get);
        my $rv  = $sth->execute();
        @array = $sth->fetchrow();
        $sth->finish();
    }
    $dbh->disconnect();
    return ( $registryerror, @array );
}

=head3 get_where_multiple

get multiple records via a field condition returns an array
this should completely replace get_where after a while
needs limit clause

=cut

sub get_where_multiple {
    my ( $class, $db, $table, $fieldname, $name, $token, $offset, $limit ) = @_;
    my $get =
      _sqlgetwhere( $name, $table, $fieldname, $token, $offset, $limit );
    my ( $rc, $rv, $array_ref );
    my ( $registryerror, $dbh ) = _registry_connect( $db, $token );
    my ( $package, $filename, $line ) = caller;
    ###$log->debug("get_where_multiple: g:$get $registryerror p:$package, f:$filename, l:$line");
    if ( length($dbh) ) {
        my $sth = $dbh->prepare($get);
        my $rv  = $sth->execute();
        $array_ref = $sth->fetchall_arrayref;
        $sth->finish();
    }
    return ( $registryerror, $array_ref );
}

=head3 sqlfind

sql find for a given piece of sql. This is sometimes the motor
for a given application. To some extent, this is a 'tramp' function
as defined in coding complete, but it hides _sqlfind too...

'order' param after $sqlstring isn't filled at present

=cut

sub sqlfind {
    my (
        $class, $db,    $table,  $fieldsref, $sqlstring,
        $order, $token, $offset, $limit
    ) = @_;
    my $get =
      _sqlfind( $table, $fieldsref, $sqlstring, $order, $offset, $limit );

    my ( $rc, $rv, $array_ref );
    my ( $registryerror, $dbh ) = _registry_connect( $db, $token );
    if ( length($dbh) ) {
        my $sth = $dbh->prepare($get);
        my $rv  = $sth->execute();
        $array_ref = $sth->fetchall_arrayref;
        $sth->finish();
    }
    return ( $registryerror, $array_ref );
}

=head3 modify_database_record

 Prepares to modify:
  - fetches a record by id
  - transfers fields to fieldsref
  - set up appropriate next action
  - display form if named, default if not
  - hardwired template logic probably needs to be moved

=cut

sub modify_database_record {

    my ( $class, $db, $table, $fieldsref, $cookieref, $pages, $token ) = @_;
    my ( $html, $key, $field, $home, $offset, $limit );

    # work out default template, results.html is not used nowadays
    my $default_template = $table;
    $default_template =~ s/om_//;
    $default_template .= "\056html";
    my $template = $$fieldsref{template} || $default_template;

    # compensate for different id names, needs to be stripped
    # out by version 2
    my %translate = qw(om_trades tradeId om_users userId);
    my $idname;
    if ( exists $translate{$table} ) {
        $idname = $translate{$table};
    } else {
        $idname = 'id';    # called id in all other tables
    }

    my $get;
    # FIXME: subtle bug in registry detail retrieve, therefore
    # get from table by name is safest currently 11/2009
     if ( $table eq 'om_users' ) {
        $get = _sqlgetwhere( $$cookieref{userId},
            $table, $idname, $token, $offset, $limit );
     } elsif ( $table eq 'om_registry' ) {
        $get = _sqlgetwhere( $$cookieref{registry},
        $table, 'name', $token, $offset, $limit ); 
    } else {
        $get = _sqlgetwhere( $$fieldsref{$idname},
        $table, $idname, $token, $offset, $limit );
    }
    $log->debug("get is $get") ;
    #
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my $sth = $dbh->prepare($get);
    $sth->execute();
    my $hash_ref = $sth->fetchrow_hashref;
    my $error    = $dbh->errstr();

    return ( 0, '', $error, $html, $pages, $template, $hash_ref, "", $token );
}

=head3 modify_database_record2

Did this never work? Just modified 2/5/2005 to produce
a where condition update.

Needs investigation and possible removal

=cut

sub modify_database_record2 {
    my (
        $class,     $db,    $table,    $name, $fieldname,
        $fieldsref, $pages, $pagename, $token
    ) = @_;

    my $html;
    my $field;
    my $offset;    # not used here
    my $limit;     # not used here
                   # this needs to be replaced by fetchrow_hashref...
    my $counter = 0;    # count the rows as they go by!
    my $get =
      _sqlgetwhere( $name, $table, $fieldname, $token, $offset, $limit );
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my $sth = $dbh->prepare($get);
    $sth->execute();
    $fieldsref = $sth->fetchrow_hashref;    # note fieldsref now comes from db
    $sth->finish();
    my $error = $dbh->errstr();
    return ( 0, '', $error, '', $pages, $pagename, $fieldsref, '', $token );
}

=head3 display_database_record

Generalised display a record from any table in the database
Returns html directly, is therefore single language

Needs to take a template as input to make multi-language

=cut

sub display_database_record {
    my ( $class, $db, $table, $fieldsref, $token ) = @_;
    my ( $html, @row, $home );
    my $counter = 0;                            # count the rows as they go by!
    my $get     = _sqlget( $$fieldsref{id} );
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my $sth = $dbh->prepare($get);
    $sth->execute();
    my @fieldnames = makecolumns();

    while ( @row = $sth->fetchrow_array ) {
        my $id = $row[0];
        foreach my $field (@row) {
            $html .= <<EOT;
         <tr><td  class="pme-key-1">$fieldnames[$counter]</td><td class="pme-key-1">$field</td></tr>
EOT

            $counter++;
        }
    }
    my $homelink = makehome();
    my $header   = <<EOT;
<tr><td class="pme-key-1" colspan="2">Record $$fieldsref{id}</td><td class="pme-key-1">$homelink</td></tr>
EOT

    $html = "<table width=\"80%\">$header $html</table>";
    $sth->finish();
    my $error = $dbh->errstr();
    return ( 0, $error, $html );
}

=head3 get_table_columns

Gets all the columns within a table via a
table describe. Used to prepare other operations

=cut

sub get_table_columns {
    my ( $table, $dbh ) = @_;
    my ( $sth, @columns, @row );
    my $show = "describe $table;";
    $sth = $dbh->prepare($show);
    my $rv = $sth->execute();
    while ( @row = $sth->fetchrow_array ) {
        push @columns, $row[0];
    }
    $sth->finish();
    my $error = $dbh->errstr();
    return (@columns);
}

=head3 check_db_and_version

checks for database password and no innodb problems
during install/configuration update

alpha quality code, new in December 2005

=cut

sub check_db_and_version {
    my ($token) = @_;

    #---------------------------------------------------------
    my ( $registryerror, $dbh ) = &Cclitedb::_registry_connect( "", $token );

    # return signature: $refresh,$metarefresh,$error,$html,$pagename,$cookies
    # no connection to database, return reason
    if ( length($registryerror) ) {
        return $registryerror;
    }

    # mysql version less than 4, no inno_db, return version
    my $sth = $dbh->prepare("show variables;");
    $sth->execute();
    my $m = 0;
    my @row;
    while ( @row = $sth->fetchrow_array() ) {
        last if ( $row[0] =~ /^have_innodb/i );
    }

    if ( $row[1] !~ /^YES/ ) {
        return "innodb  $row[1]";
    }

    # nothing comes back, ok
    return undef;
}

=head3 get_table_text_columns

gets text type columns via describe
probably refactor this as a mode of get_table_columns?

=cut

sub get_table_text_columns {
    my ( $table, $dbh ) = @_;
    my ( $sth, @columns, @row );
    my $show = "describe $table;";
    $sth = $dbh->prepare($show);
    my $rv = $sth->execute();
    while ( @row = $sth->fetchrow_array ) {
        push @columns, $row[0] if ( $row[1] =~ /varchar|text|enum/ );
    }
    $sth->finish();
    my $error = $dbh->errstr();
    return (@columns);
}

=head3 makecolumns

Make a list of columns, is this obsolete now?

=cut

sub makecolumns {
    my ( $mode, $columns_ref ) = @_;
    my @fields;
    my $fieldsstring = join( ",\n", @$columns_ref );
    if ( $mode == 1 ) {
        return $fieldsstring;
    } else {
        return @fields;
    }
}

=head3 _registry_connect

connect to database (therefore a registry) or database server 
(with blank $db, to create registries)

Note that all _ prefixed are inner routines, shouldn't be exposed

This needs review to pass the user and password inwards cleanly 12/2005

=cut

sub _registry_connect {

    my %configuration = readconfiguration();
    our $dbuser     = $configuration{dbuser};
    our $dbpassword = $configuration{dbpassword};

    my ( $db, $token ) = @_;

    #open connection to MySql database
    my $dbh = DBI->connect( "dbi:mysql:$db", $dbuser, $dbpassword );
    my $error = $DBI::errstr;
    return ( $error, $dbh );
}

=head3 registry_connect

FIXME: Exposed version of connect to database (therefore a registry) or database server 
(with blank $db, to create registries)

This is for the future with persistent database handles in mono-registry

=cut

sub registry_connect {

    my %configuration = readconfiguration();
    our $dbuser     = $configuration{dbuser};
    our $dbpassword = $configuration{dbpassword};

    my ( $db, $token ) = @_;

    #open connection to MySql database
    my $dbh = DBI->connect( "dbi:mysql:$db", $dbuser, $dbpassword );
    my $error = $DBI::errstr;
    return ( $error, $dbh );
}

=head3 _sqlfind

find record via string, orders output set
if order parameter is present

=cut

sub _sqlfind {
    my ( $table, $fieldsref, $sqlstring, $order, $offset, $limit ) = @_;
    my $sqlfind;
    my $limit_clause;

   # mild security don't deliver complete tables  unless admin 10.3.2007/06/2007
    return if ( ( $sqlstring == 1 || $sqlstring eq "1=1" ) && !is_admin() );

    if ( length($limit) ) {
        $offset = 0 if ( !length($offset) );
        $limit_clause = "LIMIT $offset,$limit";
    }

    if ( length($order) ) {
        $sqlfind = <<EOT;
   SELECT * from $table WHERE ($sqlstring) ORDER BY $order $limit_clause
EOT
    } else {
        $sqlfind = <<EOT;
   SELECT * from $table WHERE ($sqlstring) $limit_clause
EOT
    }

    return $sqlfind;
}

=head3 _sqlgetall

select all the records in a table
uses limit and offset, if present

=cut 

sub _sqlgetall {
    my ( $table, $offset, $limit ) = @_;
    my $limit_clause;

    if ( length($limit) ) {
        $offset = 0 if ( !length($offset) );
        $limit_clause = "LIMIT $offset,$limit";
    }

    my $sqlget = <<EOT;
   SELECT * 
   from $table $limit_clause
EOT

    return $sqlget;
}

=head3 _sqlgetwhere

Used for getting the registry via name, 
can be used for usernames, also

As of 06/2007 now needs tidying up

=cut

sub _sqlgetwhere {
    my ( $name, $table, $fieldname, $token, $offset, $limit ) = @_;
    my $sqlgetwhere;
    my $limit_clause;

    if ( length($limit) ) {
        $offset = 0 if ( !length($offset) );
        $limit_clause = "LIMIT $offset,$limit";
    }

    if ( $name ne "*" ) {
        if ( $table ne 'om_trades' ) {
            $sqlgetwhere = <<EOT;
    SELECT * FROM $table WHERE $fieldname = \'$name\' ORDER BY $fieldname $limit_clause 
EOT

        } else {
            $sqlgetwhere = <<EOT;
    SELECT * FROM $table WHERE $fieldname = \'$name\' ORDER BY tradeDate DESC $limit_clause 
EOT

        }

    } else {

        if ( $table ne 'om_trades' ) {
            $sqlgetwhere = <<EOT;
    SELECT * FROM $table WHERE 1 ORDER BY $fieldname $limit_clause
EOT

        } else {

            $sqlgetwhere = <<EOT;
    SELECT * FROM $table 1 ORDER BY tradeDate DESC $limit_clause 
EOT

        }

    }
    return $sqlgetwhere;
}

=head3 _sqldelete

delete record via id only

=cut

sub _sqldelete {
    my ( $table, $fieldname, $id ) = @_;
    my $sqldelete = <<EOT;
   DELETE FROM $table WHERE ($fieldname = $id)
EOT
    return $sqldelete;
}

=head3 _sqlinsert

Insert a record now made general, will insert into any table, 
column definitions are provided via 'describe table_name' done before this
note please stick to 'id' for an id/primary key, makes life simpler
this is inherited from Mose etc... userId, tradeId hence the complex
regex test below.

=cut

sub _sqlinsert {
    my ( $dbh, $tablename, $fieldsref, $token ) = @_;
    my %fields = %$fieldsref;
    my @values;
    my $value_string;
    my @columns = get_table_columns( $tablename, $dbh );
    my $fieldsstring = join( ",\n", @columns );
    foreach my $column_name (@columns) {
        next
          if ( $column_name =~ /^id|^Id|^userId|^tradeId/ )
          ;    # don't put id into this
        push @values, "'$fields{$column_name}'";
    }

    # string out the field values for the insert
    $value_string = join( ",\n", @values );
    my $sqlinsert = <<EOT;
   INSERT INTO $tablename (
     $fieldsstring
   ) VALUES (
    NULL,
    $value_string 
   )
EOT

    return $sqlinsert;
}

=head3 _sqlupdate

Update a record
only the fields supplied run into the update, unlike insert
in which ALL the columns are initialised.

=cut

sub _sqlupdate {
    my ( $dbh, $tablename, $useid, $fieldsref, $token ) = @_;
    my %fields = %$fieldsref;
    my $value_string;
    my $id_field;
    my @columns = get_table_columns( $tablename, $dbh );
    my $fieldsstring = join( ",\n", @columns );

    foreach my $column_name (@columns) {
        ( ( $id_field = $column_name ) && next )
          if ( $column_name =~ /^id|^userId|^tradeId/ && $useid == 1 )
          ;    # don't put id into this

        ( ( $id_field = $column_name ) && next )
          if ( $column_name =~ /userLogin/ && $useid == 2 )
          ;    # don't put id into this

        $value_string .= "$column_name \= \'$fields{$column_name}\',\n"

  #FIXME: ugly hack to zeroise commitlimit field in om_registry if blank 11/2008
          if ( length( $fields{$column_name} )
            || $fields{$column_name} =~ m/commitlimit/ );
    }

    #FIXME: ugly hack to blank latest_news field in om_registry if blank 11/2009
    #       prevented password change etc. badly expressed condition, watch this...
     if ($tablename eq 'om_registry') {
          if (  !length $fields{latest_news} || !defined $fields{latest_news}   ) {
            $value_string .= "latest_news \= \'\',\n"   
          }
     }


    $value_string =~ s/,$//;    # remove the last comma!
    ###$log->debug("value string is $value_string") ;
    my $sqlupdate = <<EOT;
   UPDATE $tablename 
   SET
   $value_string 
   WHERE ( $id_field = '$fields{$id_field}')
EOT

    return $sqlupdate;
}

=head3 _sqlcount

This is only tested for the transactions table at present
counts transactions for the logged in user.

=cut

sub _sqlcount {
    my ( $table, $sqlstring, $fieldname, $value, $token ) = @_;
    my $sqlcount;
    if ( !length($sqlstring) ) {

        $sqlcount = <<EOT;
     SELECT COUNT(*) FROM $table
      WHERE $fieldname = '$value'  GROUP BY $fieldname
EOT

    } else {

        $sqlcount = <<EOT;
    SELECT COUNT(*) FROM $table
     WHERE $sqlstring  
EOT

    }

    # removed group by fieldname from second statement
    return $sqlcount;
}

=head3 makebutton

Make button needs serious work, mixture of array for record
and extras_hash_ref for extra floating fields is very ugly

Values in extras override database values if there's
name collision. It's assumed that the extras are tailor made

it also currently isn't very multilingual - another problem
 
label is the label on the push button, action is the name
of the action in the controller.

=cut

sub makebutton {

    my ( $label, $class, $action, $db, $table, $arrayref, $fieldsref, $token ) =
      @_;
    my @row = @$arrayref;
    my ( $formfields, $x, $senddetected );
    my ( $registry_error, $dbh ) = _registry_connect( $db, $token );
    my @fieldnames = get_table_columns( $table, $dbh );
    $x = 0;
    foreach my $field (@fieldnames) {
        if ( $field !~ /Send|Go/ ) {

            # hack because of 'name' collision in currencies table
            $field = "cname" if ( $table eq 'om_currencies' && $x == 1 );
            $field = "dname" if ( $table eq 'om_partners'   && $x == 2 );

            #
            # only need id info within a delete button
            next if ( $action eq "delete" && $field !~ /id$/i );

            $formfields .= <<EOT;
 <input type="hidden" name="$field" value="$row[$x]">
EOT

        } else {
            $formfields .= <<EOT;
 <input  type="submit" name="$field" value="$field">
EOT
            $senddetected = 1;
        }    # endif
        $x++;
    }    # end foreach

    # add a template into resulttemplate
    if ( $action eq "display" || $action eq "template" ) {
        my $template = _choosetemplate( ( $action, $db, $table ) );
        $formfields .= $template;
    }

    if ( !$senddetected ) {
        $formfields .= <<EOT;
 <input type="hidden" name="subaction" value="$table">
 <input type="hidden" name="action" value="$action">
 <input class="$class" type="submit" name="go" value="\u$label">
EOT

    }
    my $button = <<EOT;
<form class="pme-form" action="$$fieldsref{home}" method="POST">
$formfields
</form>
EOT

    return $button;
}

=head3 _choosetemplate

Choose a template for display items when making
buttons. This is ugly, since choice of templates is
hardcoded into the code

=cut

sub _choosetemplate {
    my ( $action, $db, $table ) = @_;
    my %templates;
    my $template;
    if ( $action eq "display" ) {
        %templates = qw(om_yellowpages displayyellowpage.html
          om_trades displaytransaction.html
          om_users displayuser.html
        );
        $template = <<EOT;
 <input type="hidden" name="resulttemplate" value="$templates{$table}">
EOT
    }

    if ( $action eq "template" ) {
        %templates = qw(om_users users.html
          om_currencies modcurrency.html
          om_trades displaytransaction.html
          om_yellowpages modifyyellowpage.html
          om_partners modpartners.html
        );
        $template = <<EOT;
 <input type="hidden" name="name" value="$templates{$table}">
EOT
    }

    return $template;
}

=head3 makebox

make a tick box for deletions etc.
currently unused at 8/2005

=cut

sub makebox {

    my ( $url, $action_name, $db, $table, $id, $extras_hash_ref, $token ) = @_;

    my $formfields .= <<EOT;
 <input type="hidden" name="subaction" value="$table">
EOT

    foreach my $key ( keys %$extras_hash_ref ) {
        $formfields .= <<EOT;
 <input type="checkbox" name="$key" value="$id"> $action_name
EOT

    }

    return $formfields;
}

=head3 makelink

make a content rich link for emails etc.

=cut

sub makelink {

    my ( $url, $db, $table, $fieldsref, $token ) = @_;
    my %fields = %$fieldsref;
    my ( $formfields, $senddetected );

    foreach my $key ( keys %fields ) {
        $formfields .= <<EOT;
   $key=$fields{$key}&
EOT

    }    # end foreach

    my $button = <<EOT;
     $url?$formfields
EOT

    return $button;
}

1;

