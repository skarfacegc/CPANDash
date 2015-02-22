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

my $DB_NAME = './poddb.sqlite';

my $uPAUSE     = "250000";    # How long to pause so as not to slam metacpan in usec
my $BATCH_SIZE = "100";       # How many items to process in a batch.
my $URL_BASE = "http://metacpan.org/pod/";



# used to give us some stats as to how many items we found links for
my $SKIPPED = 0;
my $STORED  = 0;
my $TOTAL   = 0;

my $DBH;  #tracks the database handle




main();

sub main
{
    createDB() if ( !-e $DB_NAME );
    getPods();
    validateDB();

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
sub getPods
{
    my $module;
    my $names;
    my $types;
    my $paths;
    my $i;

    my $mcpan = MetaCPAN::Client->new(
        ua_args => [agent => 'CPANDash'],
    );

    my $all_modules = $mcpan->all( 'modules', { fields => [ "name", "module" ] } );

    while ( $module = $all_modules->next )
    {

        my $mod_list = $module->module;

        next unless defined( $mod_list->[0]{name} );

        foreach my $mod ( @{$mod_list} )
        {

            push( @$names, $mod->{name} );
            push( @$types, "Package" );
            push( @$paths, $URL_BASE . $mod->{name} );

            $TOTAL++;
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

    print "** Inserted: $rows\n";
}

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
            print "\tSKIPPING ". $result->{name} . "\n";
            deleteByID($result->{id});
        }

        $counter++;

        # Pause every $BATHCSIZE iterations
        if($counter % $BATCH_SIZE == 0)
        {
            usleep($uPAUSE);
        }

    }
}

sub getDBH
{
    if(defined($DBH))
    {
        return $DBH;
    }
    else
    {
        $DBH = DBI->connect( "dbi:SQLite:dbname=$DB_NAME", '', '' );
        return $DBH;
    }
}

