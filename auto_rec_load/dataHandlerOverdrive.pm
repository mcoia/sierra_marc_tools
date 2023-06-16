#!/usr/bin/perl

package dataHandlerOverdrive;

use lib qw(./);


use pQuery;
use Try::Tiny;
use Data::Dumper;
use Text::CSV;
use Digest::SHA2;

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
    my @titleIDs = ();
    my $key = '';
    if($continue)
    {
        $self->updateThisJobStatus("Login Page Worked");
        print "Login Page Worked\n" if($self->{debug});
        $self->addTrace("scrape","getting title ID's");
        my $titleids = getTitleIDs($self);
        if(ref $titleids eq 'ARRAY')
        {
            $continue = 1;
            @titleIDs = @{$titleids};
            $self->addTrace("scrape","Got:" . $#titleIDs . " Title IDs");
            $key = createKeyString($self, \@titleIDs);
            $continue = decideDownload($self, $key);
        }
        else
        {
            $continue = 0;
            $self->setError("Didn't get CSV of Title IDs");
        }
    }
    if($continue)
    {
        # The ultimate anchor tag that we want to click is setup to create a new tab.
        # So I am skipping the page scrape click throughs, and hard-coding the relative URL

        my $js = "window.location.href = '/Admin/CreateCustomFile';";
        $self->updateThisJobStatus("Navigating to /Admin/CreateCustomFile");
        $self->{driver}->execute_script($js);
        $self->waitForPageLoad();
        $self->takeScreenShot($self, "CreateCustomFile");
    }
    my $idtracker;
    if($continue)
    {
        $self->updateThisJobStatus("On Custom MARC Express file Page");
        print "On Search Grid Page\n" if($self->{debug});    

        my $idValues = '';
        $idValues .= $_.',' foreach(@titleIDs);
        $idValues = substr($idValues,0,-1);
        # Shrinking it to a much smaller data set so we don't have to wait so long
        # This should be removed for production
        $idValues = substr($idValues,0,100); # an arbitrary amount of ID numbers. It's ok if it gets cutoff in the middle of an ID. The interface will ignore
        $self->{log}->addLine($idValues);
        $self->{log}->addLine("Setting Description: '$key'");

        $self->handleDOMTriggerOrSetValue('action', 'CreateFileBtn', 'click()');
        $self->handleDOMTriggerOrSetValue('action', 'btnTitleIds', 'click()');
        $self->handleDOMTriggerOrSetValue('setval', 'CrossRefIds', $idValues);
        $self->handleDOMTriggerOrSetValue('action', 'CrossRefIds', 'dispatchEvent(new Event("keyup"))');
        $idtracker = substr($key, 0, 49); # The website doesn't allow more than 50 characters
        $self->handleDOMTriggerOrSetValue('setval', 'Description', $idtracker);
        $self->handleDOMTriggerOrSetValue('action', 'submitCreateFile', 'click()');
        # the UI has a load time here, 2 seconds is plenty
        sleep 2;
        $self->handleDOMTriggerOrSetValue('action', 'submitConfirmCreation', 'click()');
        sleep 3;
        $continue = waitAndDownloadExpressMARC($self, $idtracker);

    }
    if ($continue) # continue is the fine name if we have one. 
    {
        print "downloaded filename: $continue\n";
        processDownloadedFile($self, $idtracker, $continue);
    }
    # We've made it to the end of execution
    # whether there were files or not, we need to mark this source as having had a successful scrape
    $self->updateSourceScrapeDate();
    $self->finishThisJob("Downloaded $fileCount file(s)");
}

sub waitAndDownloadExpressMARC
{
    my $self = shift;
    my $hashID = shift;
    my $searchCount = 0;
    my $maxSearchCount = 100;
    my $secondsUntilNextCheckCycle = 5;
    $self->takeScreenShot('waitAndDownloadExpressMARC');
    $self->updateThisJobStatus("waitAndDownloadExpressMARC");
    my $tableRows = $self->{driver}->execute_script("return document.getElementsByTagName('tr').length - 1;");
    $self->{log}->addLine("tableRows: $tableRows");
    while ($searchCount < $maxSearchCount)
    {
        $self->{log}->addLine("Checking for hash: [$hashID]");
        foreach $row (reverse 0 .. $tableRows)
        {
            my $rowText = $self->{driver}->execute_script("return document.getElementsByTagName('tr')[$row].textContent;");
            if ($rowText =~ $hashID)
            {
                $self->{log}->addLine("row:[$row] Checking HashID:[$hashID] rowText:[$rowText]");
                if ($rowText =~ 'In progress')
                {
                    $self->{log}->addLine("Reloading Page! HashID:[$hashID] is pending. Check count[$searchCount]");
                    $self->reloadPage();
                    $self->waitForPageLoad();
                }
                if ($rowText =~ 'Ready')
                {
                    $self->{log}->addLine("Clicking checkbox");
                    $self->addTrace("scrape", "clicking file checkbox");
                    $self->updateThisJobStatus("executing javascript checkbox code");
    
                    my $js = $self->hammerTime($hashID);
                    $self->{log}->addLine($js);
                    $self->{log}->addLine("executing javascript event trigger code.");
                    $self->{driver}->execute_script($js);
                    $self->addTrace("scrape", "checkbox javascript has been executed");
                    $self->{log}->addLine("waiting for page to load...");
                    $self->waitForPageLoad();
                    $self->{log}->addLine("done waiting...");
                    $self->takeScreenShot("click_checkbox");
                    $self->{log}->addLine("screenshot taken");
                    $self->{log}->addLine("Downloading File");
                    $self->addTrace("scrape", "Downloading File");
                    $self->updateThisJobStatus("Downloading File");
                    # $self->{driver}->execute_script("document.getElementsByClassName('x-toolbar')[0].getElementsByClassName('downloadfilesbutton')[0].click();");
                    $self->readSaveFolder(1); # read the contents of the download folder to get a baseline
                    # $self->handleDOMTriggerOrSetValue('action', 'submitCreateFile', 'click()');
                    $self->{driver}->execute_script("document.getElementsByClassName('downloadfilesbutton')[0].click();");
                    $self->takeScreenShot("file_download");

                    # wait for file to download 
                    my $newFile = 0;
                    my $maxSleepCount = 300; # wait 5 minutes before breaking out of the loop 
                    my $sleepCount = 0;
                    while (!$newFile && $sleepCount < $maxSleepCount)
                    {
                        $newFile = $self->seeIfNewFile();
                        print "Waiting for file to download\n";
                        sleep 1;
                        $sleepCount++;
                    }

                    return $newFile;

                }

            }

        }

        $searchCount++;
        sleep $secondsUntilNextCheckCycle;

    }

    return 0;
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
        $self->waitForPageLoad();
        $self->waitForPageLoad();
    }
    my $newFile = 0;
    if($continue)
    {
        $self->handleParentAnchorClick("span", "Create worksheet", "innerHTML", "Displaying 1", 'a');
        $self->waitForPageLoad();
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
            if( lc $self->getFileExt($newFile) eq 'csv' )
            {
                $continue = 1;
            }
            else
            {
                $continue = 0;
            }
        }
        else
        {
            $continue = 0;
        }
    }
    if($continue)
    {
        my @titleIDs = @{$self->getColumnFromCSV($newFile, 'TitleID')};
        $self->{log}->addLine(Dumper(\@titleIDs));
        sort @titleIDs;
        return \@titleIDs;
    }
    return 0;
}


sub createKeyString
{
    my $self = shift;
    my $sortedTitleIDs = shift;
    my @ids = @{$sortedTitleIDs};
    my $digest = new Digest::SHA2;
    $digest->add($_) foreach(@ids);
    $digest = $digest->hexdigest();
    $self->{log}->addLine("Final KeyString: " . $digest) if $self->{debug};
    return $digest;
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
    my @fileTypes = ("mrc");
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
        $self->readyJob($job);
    }
}

1;