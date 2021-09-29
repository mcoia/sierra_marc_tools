#!/usr/bin/perl

package dataHandlerProquest;

use lib qw(./);


use pQuery;
use Try::Tiny;
use Data::Dumper;
use parent dataHandler;
use Archive::Zip;

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
        my $startingPage = $self->{driver}->get_current_url();
        my $firstRun = 0;
        foreach(@downloadPages)
        {
            if(!$firstRun)
            {
                $self->{driver}->get($startingPage);
                $self->waitForPageLoad();
            }
            $firstRun++;
            $self->handleAnchorClick($_, "Last Download", 1); #click Anchor tag based upon matching href
            $self->waitForPageLoad();
            my %downloads = %{parseFinalDownloadGrid($self)};
            my %downloaded = ();
            while ( (my $key, my $value) = each(%downloads) )
            {
                if(decideDownload($key))
                {
                    $self->readSaveFolder(1); # read the contents of the download folder to get a baseline
                    $self->handleAnchorClick($value, 0, 1);
                    my $newFile = 0;
                    while(!$newFile)
                    {
                        $newFile = $self->seeIfNewFile();
                        print "Waiting for file to download\n";
                        sleep 1;
                    }
                    $downloaded{$key} = $newFile;
                }
            }
            while ( (my $key, my $filename) = each(%downloaded) )
            {
                processDownloadedFile($self, $key, $filename);
            }
        }
    }
}

sub getDownloadPages
{
    my $self = shift;
    my $tableHTML = $self->getCorrectTableHTML("MARC Record Set");
    $self->addTrace("getDownloadPages","Reading Table");
    my %dedupe = ();
    my @ret = ();
    pQuery("tr",$tableHTML)->find("a")->each(sub {
        shift;
        $self->addTrace("getDownloadPages","Reading anchor tag");
        my $thishref = $self->getHrefFromAnchorHTML(pQuery($_)->toHtml());
        $dedupe{$thishref} = 1;
    });
    while ( (my $key, my $value) = each(%dedupe) )
    {
        push(@ret, $key);
    }
    print Dumper(\@ret);
    return \@ret;
}

sub parseFinalDownloadGrid
{
    my $self = shift;
    my $downloadGrid = $self->getCorrectTableHTML("Last Download");
    $self->addTrace("parseFinalDownloadGrid","init");
    my %downloads = ();
    pQuery("tbody > tr",$downloadGrid)->each(sub {
        shift;
        my $thisRow = pQuery($_)->toHtml();
        if($thisRow =~ m/<a\s/gi) # Making sure there is a download link. There are some "FYI" rows in these tables
        {
            my @key = @{createKeyString($self, $thisRow)};
            if($#key == 1) #needs to have two array elements
            {
                $downloads{@key[0]} = $key[1];
            }
        }
    });
    return \%downloads;
}

sub createKeyString
{
    my $self = shift;
    my $tableRow = shift;
    my $expectedCellCount = 6;
    my $cellCount = 0;
    my @ret = ('',''); # key, URL
    $self->{log}->addLine("Parsing: $tableRow") if $self->{debug};
    # Expected cell order headers:
    # Date 	Adds 	Deletes 	Last Download 	Downloaded By 	Download
    my %wantCells = (0 => 1, 1 => 1, 2=>1);
    pQuery("td",$tableRow)->each(sub {
        shift;
        my $thisCell = pQuery($_)->text();
        my $thisCellHTML = pQuery($_)->toHtml();
        $self->addTrace("createKeyString","$thisCell");
        if($thisCellHTML =~ m/<a/gi) # This cell contains the link (or at least something that looks like an anchor tag
        {
            @ret[1] = $self->getHrefFromAnchorHTML($thisCellHTML);
        }
        @ret[0] .= $thisCell . "_" if($wantCells{$cellCount});
        $cellCount++;
        undef $thisCell;
    });

    @ret[0] = substr(@ret[0],0,-1) if( (length(@ret[0]) > 0) && (@ret[0] =~ m/_$/ ) ); # remove the trailing underscore
    if($cellCount != $expectedCellCount)
    {
        print "Cell count didn't match what we wanted, Check log for details\n";
        $self->setError("Proquest download grid had an unexpected number of columns: $cellCount, expected: $expectedCellCount");
        return undef;
    }
    $self->{log}->addLine("Final KeyString: " . Dumper(\@ret)) if $self->{debug};
    return \@ret;
}

sub decideDownload
{
    my $self = shift;
    my $keyString = shift;
    $keyString = $self->escapeData($keyString);

    my $query = "select id from $self->{prefix}"."_file_track file
    where key = '$keyString' 
    and source = " .$self->{sourceID}. " 
    and client = " .$self->{clientID};
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