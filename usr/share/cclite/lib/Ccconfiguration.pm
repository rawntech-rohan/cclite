#!/usr/bin/perl -w

=head1 NAME

Ccconfiguration.pm

=head1 SYNOPSIS

Read configuration information

=head1 DESCRIPTION

Read configuration and supply hash

WARNING

If this doesn't work, nothing will work!

=head1 AUTHOR

Hugh Barnard


=head1 SEE ALSO


=head1 COPYRIGHT

(c) Hugh Barnard 2005-2009 GPL Licenced
 
=cut

package Ccconfiguration;

use strict;
use vars qw(@ISA @EXPORT);
use Exporter;
my $VERSION = 1.00;
@ISA = qw(Exporter);

@EXPORT = qw(
  readconfiguration
);

=head3 readconfiguration

Read the configuration data and return a hash


Skip comments marked with #
cgi parameters will override configuration file
information, always!

Included here, needs to be executed within BEGIN

Revised 1/2009 for Windows...
=cut

sub readconfiguration {

    my ($force_configuration_path) = @_;
    my $os = $^O;
    my $dir;
    my $default_config;

=item debug new config method

    my ( $package, $filename, $line ) = caller;
    print STDOUT "Content-type: text/html\n\n";
    print "p:$package, f:$filename, l:$line <br/>" ;
    ( $package, $filename, $line ) = caller (2);
    print "p:$package, f:$filename, l:$line <br/> " ;
    ( $package, $filename, $line ) = caller (3);
    print "p:$package, f:$filename, l:$line </br>" ;
        ( $package, $filename, $line ) = caller (4);
    print "p:$package, f:$filename, l:$line </br>" ;


=cut

    # if it's windows use cd to find the directory
    if ( $os =~ /^ms/i ) {
        $dir = `cd`;
    } else {
        $dir = `pwd`;
    }

    # make an informed guess at the config file not explictly supplied
    $dir =~ s/\bcgi-bin.*//;
    $default_config = "${dir}config/cclite.cf";
    $default_config =~ s/\s//g;

    # either supply it explicitly with full path or it will guess..
    my $configfile = $force_configuration_path || $default_config;

    my %configuration;
    if ( -e $configfile ) {
        open( CONFIG, $configfile );
        while (<CONFIG>) {
            s/\s$//g;
            next if /^#/;
            my ( $key, $value ) = split( /\=/, $_ );
            if ($value) {
                $key =~ lc($key);    #- make key canonic, all lower
                $configuration{$key} = $value if ( length($value) );
            }
            $key   = "";
            $value = "";
        }
    } else {
        print <<EOT;
Content-type: text/html

<head>
<title>No configuration file</title>
<link type="text/css" href="/styles/cc.css" rel="stylesheet">
</head>
<br/><br/>
<pre> 
   Cannot find configuration file file:
    <div class="failedcheck"> $configfile </div> 
    may be missing? Please use <a href="/cgi-bin/protected/ccinstall.cgi">the installer</a> to create it.
   <br/><br/>
    <a href="http://groups.google.co.uk/group/cclite">Ask for Help at the Cclite Group</a>
</pre>
EOT

        exit 0;

    }
    return %configuration;
}

1;
