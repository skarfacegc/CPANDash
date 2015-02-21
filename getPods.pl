#!/usr/bin/env perl

use strict;
use warnings;

use MetaCPAN::Client;
use Data::Printer;
use Data::Dumper;
use FileHandle;
use DBI;

my $DB_NAME = './poddb.sqlite';

main();

sub main
{
    if(-e $DB_NAME)
    {
        die("$DB_NAME exists.  Remove to rebuild");
    }
    createDB() if(! -e $DB_NAME);
    getPods();
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

    my $mcpan = MetaCPAN::Client->new();
    my $all_modules = $mcpan->all( 'modules', { fields => [ "name", "module" ] } );

    while ( $module = $all_modules->next )
    {
        my $mod_list = $module->module;
        next unless defined( $mod_list->[0]{name} );

        foreach my $mod ( @{$mod_list} )
        {
            push( @$names, $mod->{name} );
            push( @$types, "Package" );
            push( @$paths, "PATH/" . $mod->{name} );
        }

        $i++;

        # store these in batches of 100
        if ( $i % 100 == 0 )
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
        CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
    };

    my $sth = $dbh->prepare($schema) or die 'failed to prepare:' . $DBI::errstr;

    $sth->execute();
}

sub storeData
{
    my ( $names, $paths, $types ) = @_;



    my $dbh = getDBH();
    my $sql = qq{
        INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES (?,?,?);
    };

    my $sth = $dbh->prepare($sql);
    my ( undef, $rows ) = $sth->execute_array( {}, $names, $paths, $types ) or die 'failed to insert:' . $DBI::errstr;

    warn "Inserted: $rows";

}



sub getDBH
{
    return DBI->connect( "dbi:SQLite:dbname=$DB_NAME", '', '' );
}

