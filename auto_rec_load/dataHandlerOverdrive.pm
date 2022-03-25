#!/usr/bin/perl

package dataHandlerOverdrive;

use lib qw(./);


use pQuery;
use Try::Tiny;
use Data::Dumper;
use Text::CSV;

use parent dataHandler;

sub scrape
{
    my ($self) = shift;
    $self->startThisJob();
    $self->{log}->addLine("Getting " . $self->{URL});
    $self->{driver}->get($self->{URL});
    $self->cleanScreenShotFolder();
    $self->updateThisJobStatus("Cleaned Screen Shot Folder");
    $self->takeScreenShot('pageload');
    $self->addTrace("scrape","login");
    $self->updateThisJobStatus("Login Page");
    my $continue = $self->handleLoginPage("id","UserName","Password","The information entered is incorrect");
    print "Continue: $continue\n";
    if($continue)
    {
        $self->updateThisJobStatus("Login Page Worked");
        @titleIDs = @{getTitleIDs($self)};
        $continue = $self->handleAnchorClick("Admin/MarcExpressDeliveries","MARC Express deliveries", 1);
        print "Continue: $continue\n";
    }
    if($continue) # we're on the search grid page
    {
        $self->updateThisJobStatus("On Search Grid Page");
       
        # We've made it to the end of execution
        # whether there were files or not, we need to mark this source as having had a successful scrape
        $self->updateSourceScrapeDate();
        $self->finishThisJob("Downloaded $fileCount file(s)");
    }
}

sub getTitleIDs
{
    my $self = shift;
    my $continue = $self->handleAnchorClick("/Insights", "Title status", 1);
    print "Continue: $continue\n";
    if($continue)
    {
        $continue = $self->handleAnchorClick("Reports/TitleStatusAndUsage", "Title status and usage", 1);
    }
    print "Continue: $continue\n";
    if($continue)
    {
        $continue = $self->handleParentAnchorClick("span", "Run new report", "innerHTML", "Title status and usage report options", 'a');
    }
    print "Continue: $continue\n";
    if($continue) # Date range type
    {
        $continue = $self->handleInputBoxData("combobox-1011-inputEl", "Specific");
    }
    print "Continue: $continue\n";
    if($continue) # End date
    {
        $continue = $self->handleInputBoxData("datefield-1017-inputEl", "01/01/2000");
    }
    print "Continue: $continue\n";
    if($continue)
    {
        $continue = $self->handleInputBoxData("Format-inputEl", "Ebook, Audiobook");
    }
    print "Continue: $continue\n";
    if($continue) # Start date empty
    {
        $continue = $self->handleInputBoxData("datefield-1016-inputEl", "");
    }
    print "Continue: $continue\n";
    if($continue) # Start date empty
    {
        $continue = $self->handleParentAnchorClick("span", "Update", "innerHTML", "Displaying 1", 'a');
    }
    if($continue)
    {
        $self->handleParentAnchorClick("span", "Create worksheet", "innerHTML", "Displaying 1", 'a');
        my $newFile = 0;
        my $tries = 0;
        while(!$newFile && $tries < 120) # sometimes Overdrive can take a whole minute to generate the file
        {
            $tries++;
            $newFile = $self->seeIfNewFile();
            print "Waiting for file to download: $tries\n";
            sleep 1;
        }
        if($newFile)
        {
            print "Got this: $newFile\n";
        }
    }
    print "Continue: $continue\n";
    exit;

}

sub decideDownload
{
    my $self = shift;
    my $keyString = shift;
    print "Deciding\n";
    return !$self->getFileID($keyString);
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
        $self->{job} = $job;

        foreach(@files)
        {
            my $thisFile = $_;
            my $bareFileName = $self->getFileNameWithoutPath($thisFile);
            if($self->decideToProcessFile($bareFileName))
            {
                my $fileID = $self->createFileEntry($bareFileName, $key);
                if($fileID)
                {
                    my @records = @{$self->readMARCFile($thisFile)};
                    $self->{log}->addLine("Read: " . $#records . " MARC records");
                    $self->createImportStatusFromRecordArray($fileID, $job, \@records);
                }
                else
                {
                    $self->setError("Couldn't create a DB entry for $file");
                }
            }
        }
        $self->readyJob($job);
    }
}

1;