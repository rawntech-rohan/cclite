
=head1 NAME

Ccdirectory.pm

=head1 SYNOPSIS

Ccdirectory main

=head1 DESCRIPTION

This is the the directory/yellow pages module for Cclite. It's now separated from
the transaction motor, so that custom directories can be built

These functions assume that all the local data has been validated
Probably this is done via Ccvalidate.pm. 
There are extra actions for remote registry checks already

=head1 AUTHOR

Hugh Barnard


=head1 COPYRIGHT

(c) Hugh Barnard 2004-2007 GPL Licenced 

=cut

package Ccdirectory;

use strict;
use vars qw(@ISA @EXPORT);
use Exporter;
use Ccu;
use Cclitedb;
use Ccvalidate;
use Ccsecure;

my $VERSION = 1.00;
@ISA    = qw(Exporter);
@EXPORT = qw(add_yellow
  show_yellow
  show_yellow_dir
  show_yellow_dir1
);

# read messages from literals file, this isn't fully multilingual yet
our %messages = readmessages("en");

=head3 add_yellow

add a yellow page, promoted from raw add_database_record to
do specific validations etc. needs fleshing out...
now added, parse of option fields so that the category, parent
category and keywords work out

=cut

sub add_yellow {
    my ( $class, $db, $table, $fieldsref, $token ) = @_;
    my ( $date, $time ) = &Ccu::getdateandtime( time() );
    $$fieldsref{date}   = $date;
    $$fieldsref{status} = 'active';

    # parse the option field
    ( $$fieldsref{category}, $$fieldsref{parent}, $$fieldsref{keywords} ) =
      $$fieldsref{classification} =~ /(\d{4})(\d{4})(.*)/;

    #
    my ( $refresh, $error, $html, $cookies ) =
      add_database_record( $class, $db, $table, $fieldsref, $token );
    return ( 1, $$fieldsref{home}, $error, $messages{directorypageadded},
        "result.html", "" );
}

=head3 show_yellow

Join the specific yellow pages record with the user
record to display telephone number and email etc.

Run show balance and volume to show balance and volume at 
bottom of ad. This is a pretty heavy operation and perhaps
should be done as a nightly batch to generate static html

This also contains SQL at present, goodbye n-tier purity!

=cut

sub show_yellow {
    my ( $class, $db, $table, $fieldsref, $token ) = @_;
    my $sqlstring = <<EOT;
  SELECT DISTINCT u.userEmail, y.id, y.subject, y.description, u.userMobile, u.userTelephone, y.fromuserid
  FROM om_yellowpages y, om_users u
  WHERE (
  y.fromuserid = u.userLogin AND y.id = '$$fieldsref{id}')
EOT

    # get equi-joined table
    my ( $error, $hash_ref ) = sqlraw( $class, $db, $sqlstring, 'id', $token );
    my %report;
    my $html;
    foreach my $hash_key ( keys %$hash_ref ) {

        # my $parent = "$hash_ref->{$hash_key}->{parent}" ;
        my $record_ref = $hash_ref->{$hash_key};
        foreach my $key ( keys %$record_ref ) {
            $html .= <<EOT;
   <tr><td class="pme-key-1">$key</td><td class="pme-value-1">$hash_ref->{$hash_key}->{$key}</td></tr>
EOT

        }
    }

    $html = "<table>$html</table>";
    my $template = "result.html" if ( !length( $$fieldsref{resulttemplate} ) );
    return ( "", $$fieldsref{home}, "", $html, $template, $fieldsref );
}

=head3 show_yellow_dir

Show yellow pages directory by category, based on the work done by Mary Fee
for Camden. Should work with any scheme that has categories and parent categories
only nested once, otherwise needs re-writing to be recursive

won't work as web service because it returns hashes!

=cut

sub show_yellow_dir {
    my (
        $class, $db,   $table, $fieldsref, $fieldname,
        $value, $type, $token, $offset,    $limit
    ) = @_;
    my ( $refresh, $metarefresh, $error, $html, $pagename, $cookies, $order );

    # stick the major categories equi-joined to the individual ads
    # whole directory
    #
    # next generation, join categories to itself and order
    # by the alphabetic description
    #
    # SELECT DISTINCT c1.description, c2.description, c1.category, c2.category
    # FROM om_categories c1, om_categories c2
    # WHERE (
    # c2.parent = c1.category
    # )
    # ORDER BY c1.description, c2.description
    # LIMIT 0 , 30
    #

    my $sqlstring;
    my $summary_flag = "no";    # set to yes if summary
    if ( !length( $$fieldsref{parent} ) && !length( $$fieldsref{category} ) ) {
        $summary_flag = "yes";
        $sqlstring    = <<EOT;
SELECT DISTINCT c.parent, c.description, y.id, y.subject, y.fromuserid
FROM om_yellowpages y, om_categories c
WHERE (
y.category = c.category
AND c.parent = y.parent
)
ORDER BY c.parent, c.description
EOT

        # one major category only
    } elsif ( length( $$fieldsref{parent} )
        && !length( $$fieldsref{category} ) )
    {

        $sqlstring = <<EOT;
SELECT DISTINCT c.parent, c.description, y.id, y.subject, y.fromuserid
FROM om_yellowpages y, om_categories c
WHERE (
y.category = c.category
AND c.parent = y.parent AND y.parent = $$fieldsref{parent}
)
ORDER BY c.parent, c.description
EOT

    } elsif ( length( $$fieldsref{parent} ) && length( $$fieldsref{category} ) )
    {

        # one specific category

        $sqlstring = <<EOT;
SELECT DISTINCT c.parent, c.description, y.id, y.subject, y.fromuserid
FROM om_yellowpages y, om_categories c
WHERE (
y.category = c.category
AND c.parent = y.parent AND y.parent = $$fieldsref{parent} AND y.category = $$fieldsref{category}
)
ORDER BY c.parent, c.description
EOT

    }

    my $row;
    my %counter;
    my $html;
    my ( $major, $save_major, $minor, $save_minor );
    my $first_pass = 1;

    # get equi-joined table
    my ( $error, $hash_ref ) = sqlraw( $class, $db, $sqlstring, 'id', $token );
    my %report;
    my ( $key, $categoryref );

    # for example print "Name for id 42 is $hash_ref->{42}->{name}\n";

    # once through to accumulate by category
    my %counter;    # hash to count each major category

    foreach my $hash_key ( keys %$hash_ref ) {
        my $parent = "$hash_ref->{$hash_key}->{parent}";
        my ( $error, $categoryref ) =
          get_where( $class, $db, 'om_categories', 'category', $parent, $token,
            $offset, $limit );

# must be revisited this is wrong! parasitic call to table because of fetchall_hashref!
        my ( $error, $hash_ref1 ) =
          get_where( $class, $db, 'om_yellowpages', 'id', $hash_key, $token,
            $offset, $limit );
        my $lower = lc( $$categoryref{description} );
        my $lower = "\u$lower";
        $counter{$lower}++;    # increment count for this category
        $key = "$lower---$hash_ref->{$hash_key}->{description}---$parent";
        my $login = "$hash_ref->{$hash_key}->{fromuserid}";

        # this gives an individual item number entry. It's red, if it's a want
        # it's yellow if for sale
        $report{$key} .= <<EOT;
<a class="pme-key-1" title="$$hash_ref1{majorclass} :: $$hash_ref1{type}::$hash_ref->{$hash_key}->{subject}"
 href="$ENV{SCRIPT_PATH}?subaction=$table&userLogin=$login&action=showuser">
<span >$login</span></a> -- 
EOT

        # these change the colour of individual items in the listing
        $report{$key} =~ s/key-1/key-debit/g
          if ( $$hash_ref1{type} eq 'wanted' );    # kludge for debits
        $report{$key} =~ s/key-1/key-sale/g
          if ( $$hash_ref1{majorclass} eq 'goods'
            && $$hash_ref1{type} eq 'offered' );    # kludge for for sale

    }    # end foreach

    my $save_major;
    my $html = <<EOT;
<h3>$messages{directorylisting}</h3>
 <span class="pme-key-1">$messages{offered}</span> 
 <span class="pme-key-debit">$messages{wanted}</span> 
 <span class="pme-key-sale">$messages{forsale}</span> 
&nbsp; &nbsp;<!-- <i>$messages{putcursoron}</i> -->
<br/>
EOT

    foreach my $key ( sort keys %report ) {
        my ( $major, $minor, $parent ) = split( /---/, $key );

        if ( $first_pass || ( $save_major ne $major ) ) {

            if ( !length( $$fieldsref{parent} ) ) {
                $html .= <<EOT;
<h4>
<a class="big" title="$major : $messages{clicktoexpand}"
 href="$ENV{SCRIPT_PATH}?subaction=$table&parent=$parent&action=showyellowdir">
+</a>&nbsp;$major ($counter{$major}) </h4>

EOT

            } else {

                $html .= <<EOT;

<h4>
<a class="big" title="$major : $messages{clicktocollapse}"
 href="$ENV{SCRIPT_PATH}?subaction=$table&action=showyellowdir">
-</a>&nbsp;$major ($counter{$major}) </h4>

EOT

            }    # endif

        }    # endif

        $report{$key} =~ s/\s--\s$//;

        $html .=
          "&nbsp;&nbsp;  $minor &nbsp;&nbsp;&nbsp;&nbsp;$report{$key}<br/>\n"
          if ( $summary_flag eq "no" );
        $save_major = $major;
        $first_pass = 0;
    }
    my $template = "result.html" if ( !length( $$fieldsref{resulttemplate} ) );
    return ( 0, "", $error, $html, $template, $cookies );

    # no remote access for this, put somewhere else?
}

=head3 show_yellow_dir1

Show yellow pages directory by category description, based on the work done by Mary Fee
for Camden. Should work with any scheme that has categories and parent categories
only nested once, otherwise needs re-writing to be recursive

Shows all lower level description in a big craiglist like table, will make a big
page when there lots of ads. 

Also this is a lot simpler that the first one with its expanding and contracting
display etc. 06/2007

=cut

sub show_yellow_dir1 {

    my ( $class, $db, $sqlstring, $fieldsref, $token, $offset, $limit ) = @_;

    my $interval = 1;    # if there are items a week or less in a category
                         # they'll show up as new

    my $sqldetail = <<EOT;

SELECT c.description, count( 1 ) AS 'major count', y.type, y.category
FROM om_yellowpages y, om_categories c
WHERE (
y.category = c.category
AND c.parent = y.parent
)
GROUP BY y.parent,y.category,y.type
ORDER BY c.description ASC
EOT

    # same data set as detail but count 'new' ads

    my $sqltestifnew = <<EOT;

SELECT y.category, count( 1 )
FROM om_yellowpages y, om_categories c
WHERE 
((y.date
BETWEEN DATE_SUB( CURDATE( ) , INTERVAL $interval
DAY )
AND CURDATE( ))
AND
y.category = c.category
AND c.parent = y.parent)
GROUP BY y.parent,y.category,y.type
ORDER BY c.description ASC
EOT

    my $sqlmajor = <<EOT;

SELECT  c.parent, count( 1 ) AS 'major count', y.type, y.category
FROM om_yellowpages y, om_categories c
WHERE (
y.category = c.category
AND c.parent = y.parent
)
GROUP BY y.parent
ORDER BY y.parent ASC
EOT

    my $sqlstring = $sqlmajor;

    $sqlstring = $sqldetail if ( $$fieldsref{getdetail} );

    # look up categories which have new ads
    my %newads;

    # get a list of categories which have received ads recently
    # put in a hash
    my ( $registryerror, $array_ref ) =
      sqlraw_return_array( $class, $db, $sqltestifnew, '', $token );

    foreach my $row_ref (@$array_ref) {
        $newads{ $$row_ref[0] } = "y";
    }

    my ( $registryerror, $array_ref ) =
      sqlraw_return_array( $class, $db, $sqlstring, '', $token );

    my $html        = "<tr>";
    my $width_count = 1;
    my $max_depth   = $$fieldsref{maxdepth}
      || 3;    # four cells wide as default if not specified
    my $item_count;
    foreach my $row_ref (@$array_ref) {
        $item_count = scalar(@$row_ref);
        my ( $error, $categoryref ) =
          get_where( $class, $db, 'om_categories', 'category', $$row_ref[0],
            $token, $offset, $limit );
        if ( !$$fieldsref{getdetail} ) {
            $$row_ref[0] =
              $$categoryref{description};    # replace category number with desc
        } else {
            $$row_ref[2] =
              $messages{ $$row_ref[2]
              };    # replace offered/wanted with multilingual message
        }
        $$row_ref[0] =
"<a href=\"/cgi-bin/cclite.cgi?action=showyellowbycat&string=$$row_ref[0]\">$$row_ref[0]</a>";

  # if there's recent ads in this category add a small 'New' flag in the listing
        $$row_ref[0] =
          "$$row_ref[0]<sup class=\"spaced\">$messages{'new'}</sup>"
          if ( $newads{ $$row_ref[3] } eq "y" );

        # numeric category does not appear in display
        delete $$row_ref[3];

        my $row = join( "</td><td class=\"offered\">", @$row_ref );
        my $row = "<td class=\"offered\">$row</td><td>&nbsp;</td>";
        $row =~ s/\=\"offered\"/\=\"wanted\"/g
          if ( $row =~ /wanted/ )
          ; # change class to wanted if wanted advert, means colour change on display
        if ( $width_count == $max_depth ) {
            $html .= "$row</tr>\n<tr>";
            $width_count = 1;
        } else {
            $html .= $row;
            $width_count++;
        }

    }

    # pad the end of the table, if necessary
    my $endtable =
      "<td></td>" x ( ( $max_depth - $width_count ) * $item_count );

    $html .= "$endtable</tr>" if ( $html !~ /<tr>$/ );
    $html = "<table><tbody class=\"stripy\">$html</tbody></table>";

    return ( 0, '', '', $html, "result.html", '', '', $token );

}

1;

