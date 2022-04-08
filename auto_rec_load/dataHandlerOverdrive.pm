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
    print "Logging in\n" if($self->{debug});
    my $continue = $self->handleLoginPage("id","UserName","Password","The information entered is incorrect");
    print "Continue: $continue\n" if($self->{debug});
    if($continue)
    {
        $self->updateThisJobStatus("Login Page Worked");
        print "Login Page Worked\n" if($self->{debug});
        @titleIDs = @{getTitleIDs($self)};
        $continue = $self->handleAnchorClick("Admin/MarcExpressDeliveries","MARC Express deliveries", 1);
        print "Continue: $continue\n" if($self->{debug});
    }
    if($continue) # we're on the search grid page
    {
        $self->updateThisJobStatus("On Search Grid Page");
        print "On Search Grid Page\n" if($self->{debug});

        # We've made it to the end of execution
        # whether there were files or not, we need to mark this source as having had a successful scrape
        $self->updateSourceScrapeDate();
        $self->finishThisJob("Downloaded $fileCount file(s)");
    }
}

sub getTitleIDs
{
    my $self = shift;
    ##############
    #
    # Click "Insights"
    #
    ##############
    my $continue = $self->doWebActionAfewTimes( 'handleAnchorClick($self, "/Insights", "Title status", 1)', 4 );
    print "Clicked on Insights\n" if($self->{debug});
    print "Continue: $continue\n";

    ##############
    #
    # Click "Reports/TitleStatusAndUsage"
    #
    ##############
    if($continue)
    {
        $continue = $self->doWebActionAfewTimes( 'handleAnchorClick($self, "Reports/TitleStatusAndUsage", "Title status and usage", 1)', 4 );
        print "Clicked on Title status and usage\n" if($self->{debug});
    }
    print "Continue: $continue\n";

    ##############
    #
    # Click Run new report
    #
    ##############
    if($continue)
    {
        $continue = $self->doWebActionAfewTimes('handleParentAnchorClick($self, "span", "Run new report", "innerHTML", "Title status and usage report options", "a")', 4 );
        print "Clicked on Title status and usage report options\n" if($self->{debug});
    }
    print "Continue: $continue\n";

    ##############
    #
    # Click Date Dropdown, and Choose "Specific"
    #
    ##############
    if($continue)
    {
        my %attribs =
        (
            "data-ref" => 'inputEl',
            "role" => "combobox",
            "type" => "text",
            "name" => "DateRangePeriodType"
        );
        my $dropdownID = $self->findElementByAttributes("input", "id", \%attribs);
        print "Clicking on $dropdownID\n";
        $continue = $self->handleDOMTriggerOrSetValue('action', $dropdownID, "click()");
        sleep 1;
        if($continue)
        {
            # Get the associated number value for the dropdown element, so we can find the associated combo element
            $dropdownID =~ s/[^\d]//g;
            %attribs =
            (
                "data-boundview" => 'combobox-' . $dropdownID . '-picker',
                "role" => "option"
            );
            $continue = $self->handleDOMTriggerOrSetValue('action', undef, "click()", "li", \%attribs, "Specific");
        }
        print "Filled 'Specific' into DateRangePeriodType\n" if($self->{debug});
    }
    print "Continue: $continue\n";

    ##############
    #
    # Start Date empty
    #
    ##############
    if($continue) # Start date
    {
        my %attribs =
        (
            "data-ref" => 'inputEl',
            "role" => "combobox",
            "type" => "text",
            "name" => "StartDateInputValue"
        );
        $continue = $self->handleDOMTriggerOrSetValue('setval', undef, "", "input", \%attribs);
        print "Filled 'Specific' into DateRangePeriodType\n" if($self->{debug});
    }
    print "Continue: $continue\n";

    ##############
    #
    # End Date 01/01/4000
    #
    ##############
    if($continue) # End date
    {
        my %attribs =
        (
            "data-ref" => 'inputEl',
            "role" => "combobox",
            "type" => "text",
            "name" => "EndDateInputValue"
        );
        $continue = $self->handleDOMTriggerOrSetValue('setval', undef, "01/01/4000", "input", \%attribs);
        print "Filled 'Specific' into DateRangePeriodType\n" if($self->{debug});
    }
    print "Continue: $continue\n";

    ##############
    #
    # Formats: Ebook, Audiobook
    #
    ##############
    if($continue)
    {
        my %attribs =
        (
            "data-ref" => 'inputEl',
            "role" => "combobox",
            "type" => "text",
            "name" => "Format"
        );
        $continue = $self->handleDOMTriggerOrSetValue('setval', undef, "Ebook, Audiobook", "input", \%attribs);
        print "Filled 'Specific' into DateRangePeriodType\n" if($self->{debug});
    }
    print "Continue: $continue\n";

    ##############
    #
    # Click "Update"
    #
    ##############
    if($continue)
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