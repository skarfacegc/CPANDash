#!/usr/bin/env perl

use strict;
use warnings;

use MetaCPAN::Client;
use Data::Printer;
use Data::Dumper;
use FileHandle;
use DBI;
use Time::HiRes qw( usleep );
use HTTP::Tiny;
use File::Path qw(make_path);

my $DB_NAME = './poddb.sqlite';

my $uPAUSE     = "250000";                     # How long to pause so as not to slam metacpan in usec
my $BATCH_SIZE = "100";                        # How many items to process in a batch.
my $URL_BASE   = "http://metacpan.org/pod/";
my $BASE_DIR = "./HTMLDocs";

# used to give us some stats as to how many items we found links for
my $SKIPPED = 0;
my $STORED  = 0;
my $TOTAL   = 0;

my $DBH;                                       #tracks the database handle

main();

sub main
{
    createDB() if ( !-e $DB_NAME );
    getModules();
    getDocs();

    print "Stored: $STORED\n";
    print "Skipped: $SKIPPED\n";
    print "TOTAL: $TOTAL\n";
    print "Skip %: " . int( ( $SKIPPED / $TOTAL ) * 100 ) . "\n";
}

#
# Get the list of all of the availble modules
# The loop through all of the packages(?) in the module
# and build a list of names
#
sub getModules
{
    my $module;
    my $names;
    my $types;
    my $paths;
    my $i;

    my $mcpan = MetaCPAN::Client->new( ua_args => [ agent => 'CPANDash' ] );

    my $all_modules = $mcpan->all( 'modules', { fields => [ "name", "module" ] } );

    while ( $module = $all_modules->next )
    {

        my $mod_list = $module->module;

        next unless defined( $mod_list->[0]{name} );

        foreach my $mod ( @{$mod_list} )
        {

            push( @$names, $mod->{name} );
            push( @$types, "Package" );
            push( @$paths, buildPath( $mod->{name} ) . "/" . $mod->{name} . ".html" );
        }

        $i++;

        # store these in batches of $BATCH_SIZE
        if ( $i % $BATCH_SIZE == 0 )
        {
            storeData( $names, $paths, $types );
            undef $names;
            undef $paths;
            undef $types;
        }
    }

    # now store any that are left
    storeData( $names, $paths, $types );
}

# Write a doc row to the database
sub storeData
{
    my ( $names, $paths, $types ) = @_;
    my $rows;

    my $dbh = getDBH();
    my $sql = qq{
        INSERT OR IGNORE INTO searchIndex(name, path, type) VALUES (?,?,?);
    };

    my $sth = $dbh->prepare($sql);
    ( undef, $rows ) = $sth->execute_array( {}, $names, $paths, $types ) or die 'failed to insert:' . $DBI::errstr;
}

# Delete a row from the db
sub deleteByID
{
    my ($row_id) = @_;

    my $dbh = getDBH();
    my $sql = qq{
        DELETE FROM searchIndex WHERE id = $row_id ;
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute() or die "error deleting:" . $DBI::errstr;

}

#
# Now that we have all of the package names, go through the
# DB and try to find docs for each package.  if the doc
# exists, write it to disk, otherwise remove the row from the DB
#
sub getDocs
{
    my $result;
    my $dbh = getDBH();
    my $sql = qq{
        SELECT * FROM searchIndex
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute() or die 'Error loading: ' . $DBI::errstr;

    while ( $result = $sth->fetchrow_hashref )
    {
        $TOTAL++;
        my $pod;

        eval{ $pod = getPod( $result->{name} ) };

        # If we get a pod, store it
        if ( defined($pod) && $pod ne "" )
        {
            $STORED++;
            print "STORE: " . $result->{name} . " " . $result->{id} . "\n";
            writePod( $result->{name}, $pod );
        }

        # otherwise remove the entry from the database
        else
        {
            $SKIPPED++;
            print "\tSKIPPING: " . $result->{name} . " " . $result->{id} . "\n";
            deleteByID( $result->{id} );
        }
    }
}

# Get the pod in html form and return it.
sub getPod
{
    my ($package) = @_;

    my $mcpan = MetaCPAN::Client->new( ua_args => [ agent => 'CPANDash' ] );

    my $pod = $mcpan->pod($package)->html;

    return $pod;
}

# WRite the pod to disk creating path as needed
sub writePod
{
    my ( $package, $pod ) = @_;

    my $mkdir_error;
    my $path_name = buildPath($package);
    my $filename  = $package . ".html";

    make_path("$BASE_DIR/$path_name");

    my $fh = FileHandle->new("> $BASE_DIR/$path_name/$filename") or die "Couldn't open file for write: $!";
    print $fh $pod;
    $fh->close;
}

# Construct the path string
sub buildPath
{
    my ($package) = @_;

    $package =~ s/::/\//g;
    return $package;
}

# Creates the database
sub createDB
{
    my $dbh = getDBH();

    my $schema = qq{
        CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
    };

    my $index = qq{
        CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
    };

    my $sths = $dbh->prepare($schema) or die 'failed to prepare:' . $DBI::errstr;

    $sths->execute();

    my $sthi = $dbh->prepare($index) or die 'failed to prepare:' . $DBI::errstr;

    $sthi->execute();
}

# gets the database handle
sub getDBH
{
    if ( defined($DBH) )
    {
        return $DBH;
    }
    else
    {
        $DBH = DBI->connect( "dbi:SQLite:dbname=$DB_NAME", '', '' );
        return $DBH;
    }
}

#
# These two methods were for URL validation
# not used for pod retreival. Left here for no good reason
#

sub validateDB
{
    my $result;
    my $counter;

    my $dbh = getDBH();
    my $sql = qq{
        SELECT * FROM searchIndex;
    };

    my $sth = $dbh->prepare($sql) or die 'failed to prepare:' . $DBI::errstr;
    $sth->execute();

    while ( $result = $sth->fetchrow_hashref() )
    {
        my $url = checkURL( $result->{name} );

        if ( defined($url) )
        {
            $STORED++;
            print "OK " . $result->{name} . "\n";
        }
        else
        {
            $SKIPPED++;
            print "\tSKIPPING " . $result->{name} . "\n";
            deleteByID( $result->{id} );
        }

        $counter++;

        # Pause every $BATHCSIZE iterations
        if ( $counter % $BATCH_SIZE == 0 )
        {
            usleep($uPAUSE);
        }

    }
}

sub checkURL
{
    my ($pod_name) = @_;

    my $http = HTTP::Tiny->new();

    # Check to see if there are docs where we expect them on metacpan
    # use a head request to conserve bandwidth
    my $resp = $http->head( $URL_BASE . $pod_name );

    if ( $resp->{success} == 1 )
    {
        return $URL_BASE . $pod_name;
    }
    else
    {
        return;
    }
}

