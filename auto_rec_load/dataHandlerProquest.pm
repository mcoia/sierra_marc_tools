#!/usr/bin/perl

package dataHandlerProquest;

use lib qw(./);


use pQuery;
use Try::Tiny;
use Data::Dumper;
use parent dataHandler;

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
                if(decideDownload($self, $key))
                {
                    print "Decided to download\n";
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
        if($thisCellHTML =~ m/<a/gi) # This cell contains the link (or at least something that looks like an anchor tag
        {
            @ret[1] = $self->getHrefFromAnchorHTML($thisCellHTML);
        }
        @ret[0] .= $thisCell . "_" if($wantCells{$cellCount});
        $cellCount++;
        undef $thisCell;
    });
    @ret[0] = substr(@ret[0],0,-1) if( (length(@ret[0]) > 0) && (@ret[0] =~ m/_$/ ) ); # remove the trailing underscore
    $self->addTrace("createKeyString",@ret[0]);
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
    return $self->getFileID($keyString);
}

sub processDownloadedFile
{
    my $self = shift;
    my $key = shift;
    my $file = shift;
    my @fileTypes = ("mrc", "xml");
    $self->addTrace("processDownloadedFile","$key -> $file");
    my @files = @{$self->extractCompressedFile($file,\@fileTypes)};
    my $job;
    if($#files > -1)
    {
        $job = $self->createJob();
    }
    foreach(@files)
    {
        my $thisFile = $_;
        my $fileID = $self->createFileEntry($self->getFileNameWithoutPath($thisFile), $key);
        if($fileID)
        {
            my @records = @{$self->readMARCFile($thisFile)};
            $self->createImportStatusFromRecordArray($fileID, $job, \@records);
        }
        else
        {
            $self->setError("Couldn't create a DB entry for $file");
        }
    }
}

1;