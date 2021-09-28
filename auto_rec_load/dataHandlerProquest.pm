#!/usr/bin/perl

package dataHandlerProquest;

use lib qw(./);


use pQuery;
use Try::Tiny;
use Data::Dumper;
use parent dataHandler;

our @downloadPageStrings = ("MARC Record Set","");

sub scrape
{
    my ($self) = shift;
    $self->{log}->addLine("Getting " . $self->{URL});
    $self->{driver}->get($self->{URL});
    $self->takeScreenShot('pageload');
    $self->addTrace("scrape","login");
    my $continue = $self->handleLoginPage("id","username","password","Incorrect username or password. Please try again.");
    print "Continue: $continue\n";
    if($continue)
    {
        $continue = $self->handleAnchorClick("MARC Updates","MARC Record Set");
        print "Continue: $continue\n";
    }
    if($continue) # we're on the download page
    {
        my @downloadPages = @{getDownloadPages($self)};

    }
}

sub getDownloadPages
{
    my $self = shift;
    my $tableHTML = $self->getCorrectTableHTML("MARC Record Set");
    my %dedupe = {};
    my @ret = ();
    pQuery("tr",$tableHTML)->find("a")->each(sub {
        shift;
        print pQuery($_)->text();
        exit;
    });
}

sub createKeyString
{
    my $self = shift;
    my $tableRow = shift;

    
}

sub decideDownload
{
    my $self = shift;
    my $keyString = shift;
    $keyString = $self->escapeData($keyString);

    my $query = "select id from $self->{prefix}"."_file_track file
    where name = '$keyString'";
    my @results = @{$self->{dbHandler}->query($query)};
    if($#results == -1)
    {
        return 1;
    }
    return 0;
}

sub readDataDownloadTable
{
    my $self = shift;
    my $body = $self->getHTMLBody();
    
    my $rowNum = 0;
    my $correctTable = 0;
    pQuery("tr",$body)->each(sub {
        
        print pQuery($_)->text();
        exit;
        # my $i = shift;
        # my $row = $_;
        # my $colNum = 0;
        # my $owningLib = '';
        # pQuery("td",$row)->each(sub {
            # shift;
            # if($rowNum == 1) # Header row - need to collect the borrowing headers
            # {
                # push @borrowingLibs, pQuery($_)->text();
            # }
            # else
            # {
                # if($colNum == 0) # Owning Library
                # {
                    # $owningLib = pQuery($_)->text();
                # }
                # elsif ( length(@borrowingLibs[$colNum]) > 0  && (pQuery($_)->text() ne '0') )
                # {
                    # if(!$borrowingMap{$owningLib})
                    # {   
                        # my %newmap = ();
                        # $borrowingMap{$owningLib} = \%newmap;
                    # }
                    # my %thisMap = %{$borrowingMap{$owningLib}};
                    # $thisMap{@borrowingLibs[$colNum]} = pQuery($_)->text();
                    # $borrowingMap{$owningLib} = \%thisMap;
                # }
            # }
            # $colNum++;
        # });
         
        $rowNum++;
    });

}



1;