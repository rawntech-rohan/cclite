
=head1 NAME

Ccu.pm

=head1 SYNOPSIS

Utility routines for Cclite

=head1 DESCRIPTION

This is package of utilities for the Cclite package 
stuff to read configuration files, literals files, lightweight cgi parser
read in and localise web forms etc.

Problem with collect_items, in Cclite currently, should be moved...1/12/2005


=head1 AUTHOR

Hugh Barnard

=head1 COPYRIGHT

(c) Hugh Barnard 2005 GPL Licenced


=cut

package Ccu;

use strict;
use Cccookie;
use vars qw(@ISA @EXPORT);
use Exporter;

my $VERSION = 1.00;
@ISA = qw(Exporter);

@EXPORT = qw(debug
  cgiparse
  readmessages
  debug_soap
  readliterals
  display_template
  make_page_links
  edit_column_display
  displayengine
  getdirectoryentries
  checkstatus
  getdateandtime
  functiondoc
  error
  result
  printhead
  get_os_and_distribution
  check_paths
  format_for_uk_mobile);


$ENV{IFS} = '';

=head3 cgiparse

Lightweight cgi parser routine. Can be modified to not accept html,
possible system commands etc. 

=cut

sub cgiparse {
    my $key;
    my $value;
    my %fields;
    my $query;
    my @query;

    if ( $ENV{'REQUEST_METHOD'} eq 'POST' || $ENV{'REQUEST_METHOD'} eq 'post' )
    {
        sysread( STDIN, $query, $ENV{'CONTENT_LENGTH'} );
    } else {
        $query = $ENV{'QUERY_STRING'};
    }
    @query = split( /&/, $query );
    foreach (@query) {
        s/\+/ /g;
        s/%(..)/pack("c",hex($1))/ge;
        ( $key, $value ) = split(/=/);
        $value =~ s/[\<\>\,\;]//g;    # remove command separators etc.
        $fields{$key} = $value;

    }
    return %fields;
}

=head3 debug_soap

Debug SOAP calls. This doesn't seem to work very well?
Why o why!

=cut

sub debug_soap {
    my ($str) = @_;
    open( LOG, ">>../debug/debug.soap" );
    ###if (class($str) eq "HTTP::Request") {
    ### print LOG $str->contents if (length($str));
    ###}
    close LOG;
}

=head3 display_template

display html from template...
uses HTML::Template included with the package
note that the $html variable is badly named, it should be 'message' or something

=cut

sub display_template {

    my (
        $refresh,  $metarefresh, $error,   $html, $pages,
        $pagename, $fieldsref,   $cookies, $token
    ) = @_;

    if ($refresh) {
        $metarefresh = <<EOT;
<meta http-equiv="refresh" content="2;URL=$metarefresh">
EOT

    }

    # this is to generalise the passing of $fieldsref to the template
    # under many circumstances it'll include all the field data
    # probably need a convention to separate the two name spaces somewhat

    $$fieldsref{metarefresh} = $metarefresh;
    $$fieldsref{error}       = $error;
    $$fieldsref{html}        = $html;

    # display logon registry and language information
    my $cookieref = get_cookie();
    my ( $date, $time ) = getdateandtime( time() );

    # if not logging off, now transferred to cclite
    if ( $$fieldsref{action} ne "logoff" ) {

        ###      $$fieldsref{userLogin} = $$cookieref{userLogin}
        ###         if ( length( $$cookieref{userLogin} )
        ###              && $$cookieref{userLevel} ne "admin" );

        $$fieldsref{language} = $$cookieref{language}
          if ( length( $$cookieref{language} ) );

        $$fieldsref{registry} = $$cookieref{registry}
          if ( length( $$cookieref{registry} ) );

        $$fieldsref{date} = $date;
    }

    #
    #    $$fieldsref{jscript} = "javascript/validation.js"
    ;    # this is the non-language part of the validation script

    #
    # display logon if not logged on, otherwise display the trades form
    # needs modification to allow/disallow certain actions
    if ( length($pagename) ) {
        $$fieldsref{pagename} = $pagename;

        # this deals with the style rules for highlighting tabs
        # can't have . in style names
        $$fieldsref{substyle} = $pagename;
        $$fieldsref{substyle} =~ s/\056//;
    } elsif ( !length( $$cookieref{userLogin} ) ) {
        $$fieldsref{pagename} = "logon.html";
    } else {
        $$fieldsref{pagename} = "trades.html";
    }

    if ( length( $$cookieref{token} ) ) {
        ### if ( length( $$cookieref{userLogin} ) || $$fieldsref{action} eq "logon" ) {
        my $login = $$cookieref{userLogin} || $$fieldsref{userLogin};
        $$fieldsref{youare}     = "You are $login";
        $$fieldsref{atregistry} = "at $$fieldsref{registry}";
    }

    # collect currencies and partners, if a trade operation
    # always add a blank option as first to prevent unconscious defaults
    # don't do these unless registry defined,
    #

    my $blank_option = "<option value=\"\"></option>";

    if ( $pagename !~ /logon/ && length( $$cookieref{registry} ) ) {
        my $option_string =
          &Cclite::collect_items( 'local', $$fieldsref{registry},
            'om_currencies', $fieldsref, '1', 'select', $token );

        # this is the primary currency or the 'only' one

        $$fieldsref{selectcurrency} = <<EOT ;
<select class="required" name="tradeCurrency">$blank_option$option_string</select>\n    
EOT

        # this is the secondary currency in a split transaction operation

        $$fieldsref{sselectcurrency} = <<EOT ;
<select class="required" name="stradeCurrency">$blank_option$option_string</select>\n    
EOT

        # collect partners for registry operations, if multiregistry
        # add local registry to option string!
        # otherwise just present local registry as readonly field
        if ( $$fieldsref{multiregistry} eq "yes"
            && length( $$cookieref{registry} ) )
        {
            $option_string =
              &Cclite::collect_items( 'local', $$fieldsref{registry},
                'om_partners', $fieldsref, '2', 'select', $token );
            $option_string .=
"<option value=\"$$fieldsref{registry}\">\u$$fieldsref{registry}</option>";
            $$fieldsref{selectpartners} = <<EOT ;
<select class="required" name="toregistry">$blank_option$option_string</select>    
EOT

        } else {

            $$fieldsref{selectpartners} = <<EOT ;
<input class="grey"
 name="toregistry" class="required" readonly="readonly" size="30" maxlength="255" value="$$fieldsref{registry}" type="text">   
EOT

        }

    }

    # this is now changed to use om_categories, based on Camden LETS
    # rather than the SIC codes. should become 'pluggable' eventually.
    # the codes now have a tree structure, category and parent (category).

    if ( $pagename =~ /yellowpages/ && length( $$cookieref{registry} ) ) {

        # collect partners, if a trade operation
        # add local registry to option string!
        my $option_string =
          &Cclite::collect_items( 'local', $$fieldsref{registry},
            'om_categories', $fieldsref, '4', 'select', $token );
        $$fieldsref{selectclassification} = <<EOT ;
 <select type="required" name="classification">$blank_option$option_string</select>\n    
EOT

    }

    if ( $pagename =~ /category/ && length( $$cookieref{registry} ) ) {

        # collect major, if a category operation
        #
        my $option_string =
          &Cclite::collect_items( 'local', $$fieldsref{registry},
            'om_categories', $fieldsref, '2', 'select', $token );
        $$fieldsref{selectparent} = <<EOT ;
 <select class="required" name="parent">$blank_option$option_string</select>\n    
EOT

    }

    # get the latest news field from the registry for front page display

    $$fieldsref{latest_news} = &Cclite::get_news( 'local', $fieldsref, $token )
      if ( length( $$cookieref{registry} ) );

    ###$log->debug("news is $$fieldsref{latest_news}");

    # format it for user level users, admin needs to edit it
    $$fieldsref{latest_news} =
      "<span class=\"news\">$$fieldsref{latest_news}<\/span>"
      if ( $$cookieref{userLevel} ne "admin"
        && length( $$fieldsref{latest_news} ) );

    print <<EOT;
Content-type: text/html
$cookies
EOT

# index is the default template page
# added logic 8/2009 to return untemplated html, for 'foreign' systems
# this is the beginning of 'return for various representations, rss, json, csv etc.

    if ( !length( $$fieldsref{mode} ) || $$fieldsref{mode} eq 'html' ) {
        if ( !length( $$fieldsref{templatename} ) ) {
            $pages->Display( "index.html", $fieldsref );
        } else {
            $pages->Display( $$fieldsref{templatename}, $fieldsref );
        }
    } else {
        print $$fieldsref{html};
    }

    exit 0;
}

=head3 getdateandtime

Return the print formatted date and time of an input time, used by logging
and date stamping subroutines. 

There's a scope or duplicate problem with this currently 08/2005

=cut

sub getdateandtime {
    my ($input_time) = @_;

    # get today from the system and make a yyyymmdd (Y2k compliant!) date
    my ( $sec, $min, $hour, $mday, $lmon, $lyear, $wday, $yday, $isdst ) =
      localtime($input_time);
    my $time = sprintf( "%.2d%.2d%.2d", $hour, $min, $sec );
    $lmon++;
    my $numeric_day =
      sprintf( "%.4d%.2d%.2d", ( $lyear + 1900 ), $lmon, $mday );
    my $literal_date =
      sprintf( "%.2d/%.2d/%.4d", $mday, $lmon, ( $lyear + 1900 ) );
    return ( $numeric_day, $time );
}

=head3 edit_column_display

Prune a few columns on the display for various
tables. Do in sql later when settled down

Helps management to have this in one place.
Also admins may need to see more than users

=cut

sub edit_column_display {

    my ( $table, $columns, $row ) = @_;

    #-------------------------
    # delete for display depending on table type
    if ( $table eq 'om_trades' ) {
        delete @$columns[ 3, 4, 10 .. 14 ];

        # change to European style dates
        $$row[2] =~ s/(\d{4})-(\d{2})-(\d{2})/$3-$2-$1/;
    }

    #-------------------------
    #-------------------------
    # delete for display depending on table type
    if ( $table eq 'om_yellowpages' ) {
        delete @$columns[ 4, 6, 7, 9, 11 .. 18 ];

        # change to European style dates
        $$row[2] =~ s/(\d{4})-(\d{2})-(\d{2})/$3-$2-$1/;
    }

    #-------------------------
    #-------------------------
    # delete for display depending on table type
    if ( $table eq 'om_partners' ) {
        delete $$row[3];
        delete $$columns[3];
        delete $$row[4];
        delete $$columns[4];

        # change to European style dates
        $$row[1] =~ s/(\d{4})-(\d{2})-(\d{2})/$3-$2-$1/;
    }

    #-------------------------

    # delete for display depending on table type
    if ( $table eq 'om_users' ) {
        delete @$columns[ 0, 3, 4, 6 .. 15, 20 ];

        # change to European style dates
        $$row[19] =~ s/(\d{4})-(\d{2})-(\d{2})/$3-$2-$1/;
    }
    return ( $columns, $row );
}

=head3 functiondoc

Provide documentation about the package, reads through and looks for 
 
#  #------------------------------------------------------------------
#  #
#  sub {
#  constructs and prints them as html

This is being phased out and replaced by pod and codewalker

=cut

sub functiondoc {

    my ($start_path) = @_;
    my $find_command;
    my $docflag;
    my $testflag;
    my %document_page;
    my $text;
    my $total_line_count;
    chomp($start_path);
    opendir DIR, $start_path;
    my @file_names = readdir(DIR);
    closedir DIR;

    foreach my $file (@file_names) {

        next if ( $file !~ /\056pl|\056js|\056cgi|\056pm/i );

        open( INPUT, "$start_path/$file" );
        while (<INPUT>) {
            $total_line_count++ if ( $_ !~ /^\s*#/ );

            # start of something to document found
            if (/^\=item\s/) {

                $testflag = "";
                ###$testflag = "<font color=red>$1 :Not Validated</font> " if ($_ !~ /T/i) ;
                $docflag = 1;
                ###$text    	= "<br>Function in file: $file<br>\n" ;
            }
            if (/sub\s+(\w+)/)
            {    # subroutine header found end of thing to document
                my $lckey = $1;
                $lckey =~ lc($lckey);
                $document_page{$lckey} = <<EOT;
<a name="$lckey">
   <span class="pme-key-0">
              $lckey
   </span>
   <span class="pme-key-1"> 
       in file: $file $testflag
   </span>
</a>
<br>$text
EOT
                undef $text;
                $docflag = 0;
            }
            ###$docflag = 0 if (/^\s*[^#]/) ;
            $_ =~ s/\n//g;
            $_ = "<span class=\"printout\">$_</span>";
            $text .= "<br>\n$_" if $docflag;
        }
        close(INPUT);
    }

    print <<EOT;
Content-type: text/html

<html>
<head>
<link type="text/css" href="/styles/cc.css" rel="stylesheet">
<title>CCLite Function Documentation</title>
</head>
<body>

<h2>List of Functions in CCLite</h2>
Total Line Count is $total_line_count
<hr>
<a name="top">
<br>
EOT

    foreach my $key ( sort keys %document_page ) {
        my $grey;
        undef $grey;
        $grey = "color=\"grey\"" if ( $document_page{$key} =~ /deprecated/i );
        print "<a class=\"menu\" href=#$key>$key</a><br>\n";
    }
    foreach my $key ( sort keys %document_page ) {
        print "<hr>$document_page{$key}<br><br>\n";
        print "<a href=#top>Back to Top</a><br><br>\n";
    }
    print "</BODY></HTML>\n";
    exit 0;
###return 1 ;
}

=head3 error

Deal with unexpected errors
Should be used with try catch that is eval type constructs

=cut

sub error {

    my ( $language, $description, $support_mail, $support_literal ) = @_;
    my $problem_literal;
    my $mailto;
    my $tellwebmaster_literal;
    my $bgcolour;

    printhead();

    print <<EOT;
  <html>
  <head>
   <title>Problem $description</title>
  </head>
  <body bgcolor=$bgcolour>
   <H2>$description </H2>\n<PRE>
   $@
   </PRE>
   <a href=\"mailto:$support_mail?subject=$_[1]\">$support_literal</a>
  </body>
  </html>
EOT
    exit 0;
}

=head3 make_page_links

Make multi-page links at top of page for 'many' records

=cut

sub make_page_links {

    my ( $count, $offset, $limit ) = @_;

    # routine to make links for each page
    my $true_count = $count / $limit;
    my $page_count = int( $count / $limit );
    ###print "pc is $page_count<br>" ;
    # don't paginate single pages..

    #
    $page_count++ if ( ( $count / $limit ) > $page_count );
    return undef if ( $page_count <= 1 );
    my $x      = $count / $limit;
    my $script = "$ENV{SCRIPT_NAME}?$ENV{QUERY_STRING}";
    my $i;
    my $paging_html;

    for ( $i = 0 ; $i < $page_count ; $i++ ) {
        my $new_offset  = $i * $limit;
        my $page_number = $i + 1;
        my $link;
        if ( $new_offset != $offset ) {
            $link = <<EOT;
   &nbsp;<a class=\"pagelink\" href="$script\&offset=$new_offset\&limit=$limit">$page_number</a>
EOT

        } else {
            $link = "<span class=\"currentlink\">$page_number</span>";
        }

        $paging_html .= $link;
        undef $link;
    }

    return $paging_html;
}

=head3 printhead

Just print a content header
This is also probably dead code

=cut

sub printhead {
    print <<EOT;
Content-type: text/html

EOT
    return;
}

=head3 readmessages

Read the messages file for the given language

This has always been somewhat problematic, now finds file,
depending on the package or installation type:

0: linux commodity hosting, home directory
1: windows
2: debian or ubuntu packaged

=cut

sub readmessages {

    my ($language) = @_;

    $language = "en" if ( !length($language) );

    # deals with various directory structures
    my ( $os, $distribution, $package_type ) =
      get_os_and_distribution();    # see package type above
    my ( $error, $dir, $libpath ) =
      check_paths($package_type);    # check libraries exist/make base path

    my $messfile = "$dir/literals/literals\056$language";
    my %messages;

    if ( -e $messfile ) {
        open( MESS, $messfile );
        while (<MESS>) {
            s/\s$//g;
            next if /^#/;
            my ( $key, $value ) = split( /\=/, $_ );
            if ($value) {
                $key =~ lc($key);    #- make key canonic, all lower
                $messages{$key} = $value if ( length($value) );
            }
            $key   = "";
            $value = "";
        }
    } else {

        error(
            $language,
"Cannot find messages file:$error $messfile for $language may be missing?",
            "",
            ""
        );
    }
    return %messages;
}

=head3 format_for_uk_mobile

Make sure everything is in a consistent format
for smsgateway, both gateway and database records

Implies 1 country and may need to be changed for non UK...

=cut

sub format_for_uk_mobile {

    my ($input) = @_;

    # numbers are stored in database as 7855 667524 for example, no zero, no 44
    $input =~ s/^44//;
    $input =~ s/^0//;
    $input =~ s/(\d{4})(\d{5})/$1 $2/;
    $input =~ s/\s+$//;
    return $input;

}

=head3 debug

write things into debug file
which is hardcoded, this is due for review
to be replaced by log4perl 12/20008


sub debug {
    my ( $package, $caller, $line, $description, $value ) = @_;
    my ( $dir, $os );
    if ( $os =~ /^ms/i ) {
        $dir = `cwd`;
    } else {
        $dir = `pwd`;
    }
    $dir =~ s!/cgi-bin.*!!;
    my $default_debug = "$dir/debug/debug.txt";
    $default_debug =~ s/\s//g;
    open( DEBUG, ">>$default_debug" );
    print DEBUG "start----------------------------- \n";
    print DEBUG "$package,$caller,$line\n";
    print DEBUG "$description is $value \n\n";
    close(DEBUG);
}

=cut

=head3 get_os_and_distribution


FIXME: Duplicated in ccinstall.cgi

Now that the package is widening in application
Need a little precision about the platform
This is not infallible, btw...

If the package flag is set, then the supplied default
configuration should work...

package types
0 unpackaged *nix
1 windows
2 debian
3 probable cpanel guessed via public html

=cut

sub get_os_and_distribution {

    my ( $os, $distribution );
    my $checkdir;
    my $package_type = 0;    # 0 is unpackaged *nix, default tarball
    if ( $^O =~ /^ms/i ) {
        $os           = 'windows';
        $package_type = 1;           # 1 is windows
    } elsif ( $^O =~ /^linux/i ) {
        $os = 'linux';
    } elsif ( $^O =~ /^openbsd/i ) {
        $os = 'openbsd';
    } else {
        $os = 'nocurrentsupport';
    }

    # try and find out distribution
    if ( $os eq 'linux' ) {
        my $dist_string = `cat /proc/version`;
        $dist_string =~ m/(fedora|ubuntu|debian|red hat)/i;
        $distribution = lc($1);
    }

    # if ubuntu or debian, test whether packaged by looking
    # in /usr/share/cclite

    if ( $distribution eq 'ubuntu' || $distribution eq 'debian' ) {
        $checkdir     = `find /usr/share/cclite -prune -type d`;
        $package_type = 2
          if ( $checkdir =~ m!^/usr/share/cclite! );    # 2 is debian
    }

    # guessing at cpanel because the whole thing is under the document root
    my $path = `pwd` if ( $os eq 'linux' );
    if ( $path =~ /public_html/i && $os eq 'linux' ) {
        $distribution .= ' probably cpanel';
    }

    return ( $os, $distribution, $package_type );
}

=head3 check_paths

Checks that the path to the cclite libraries
exists and is readable. Returns message, if not.

Only necessary

=cut

sub check_paths {

    my ($package_type) = @_;
    my ( $message, $libpath, $base_directory );

    if ( $package_type == 0 ) {
        my @dir = `find ~ -name Cclite.pm`;
        $libpath = $dir[0];

        if ( length($libpath) ) {
            $libpath =~ s/\/Cclite.pm\s+$//;
            $base_directory = $libpath;
            $base_directory =~ s/\/lib//;    # usual base directory
            $base_directory =~ s/\s+$//;     #
        } else {
            $base_directory = `pwd`;
            $base_directory =~ s/\s+$//;           #
                                                   # if cgi called
            $base_directory =~ s/\/cgi-bin.*$//;

            # if batch called
            $base_directory =~ s/\/batch.*$//;
            $libpath = "$base_directory/lib";
        }

    } elsif ( $package_type == 1 ) {
        $base_directory = `cd`;
        $base_directory =~ s/\s+$//;
        $base_directory =~ s/.cgi-bin.*//;
        $libpath = "$base_directory\\lib";

    } elsif ( $package_type == 2 ) {
        $base_directory = '/usr/share/cclite';
        $libpath        = '/usr/share/cclite/lib';
    }

    if ( !length($libpath) ) {
        $message = <<EOT;
 <h5>Error 3:Ccinstall: Cclite installer</h5>
 Can't find or work out library path: $libpath 
 does not exist or unreadable?
 Please fix manually
EOT

    }

    return $message, $base_directory, $libpath;

}

1;

