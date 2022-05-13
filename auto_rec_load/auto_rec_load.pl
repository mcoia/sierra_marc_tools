#!/usr/bin/perl


use lib qw(./); 
use Loghandler;
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use File::Copy;
use DBhandler;
use Encode;
use Text::CSV;
use DateTime;
use DateTime::Format::Duration;
use DateTime::Span;
use JSON;
use Selenium::Remote::Driver;
use Selenium::Firefox;
use Selenium::Remote::WebElement;
use pQuery;
use Getopt::Long;
use Cwd;
use email;
use Digest::SHA2;


use dataHandler;
use dataHandlerProquest;
use dataHandlerOverdrive;
use commonTongue;
use marcEditor;
use job;
use notice;

# use sigtrap qw(handler cleanup normal-signals);

our $stagingTablePrefix = "auto";
our $lockfile;


our $driver;
our $dbHandler;
our $databaseName = '';
our $log;
our $debug = 0;
our $recreateDB = 0;
our $dbSeed;
our $action;
our $specific_source;
our $specific_client;
our $runJobID;
our $configFile;
our $jobid = -1;
our $vendor = '';
our $screenShotDIR;
our $testMARC = '';
our $checkILSLoaded;

# This doesn't work but whatever I guess, we'll just have to leave the lockfile on disk
$SIG{INT} = 'DEFAULT';
local $SIG{INT} = \&cleanup;

# sub {print "dead\n";};

GetOptions (
"config=s" => \$configFile,
"debug" => \$debug,
"recreateDB" => \$recreateDB,
"dbSeed=s" => \$dbSeed,
"specific_source=s" => \$specific_source,
"specific_client=s" => \$specific_client,
"action=s" => \$action,
"job" => \$runJobID,
"testMARC=s" => \$testMARC,
"lockfile=s" => \$lockfile,
"checkILSLoaded" => \$checkILSLoaded,
)
or die("Error in command line arguments\nYou can specify
--config                                      [Path to the config file]
--action                                      [specify what you want this thing to do: run_scrapers, run_jobs, run_ils_check, run_marc_test, www_actions, fire_emails]
--debug                                       [Cause more log output]
--recreateDB                                  [Deletes the tables and recreates them]
--dbSeed                                      [DB Seed file - populating the base data]
--lockfile                                    [Specific lockfile for this operation, allows for the script to run simultaneously with itself in different modes]
--testMARC                                    [Used in conjunction action=run_marc_test, expects to find test.mrc in working folder, pass the name of the MARC editor you want to test EG 'ebook_central_MWSU']
--job                                         [specify a job ID in some action contexts]
--specific_source                             [specify a specific source (by name) in some action contexts]
--specific_client                             [specify a specific client (by name) in some action contexts]
\n");

if(!$configFile || !(-e $configFile) )
{
    print "Please specify a valid path to a config file\n";
    exit;
}

$lockfile = figureLockFile() if !$lockfile;


our $mobUtil = new Mobiusutil();
our $conf = $mobUtil->readConfFile($configFile);


if($conf)
{
    %conf = %{$conf};
    if ($conf{"logfile"})
    {
        $action = lc $action;

        # defang
        undef $specific_source if( ($specific_source) && ($specific_source  =~ m/[&'%\\\/]/) );
        $specific_source = lc $specific_source if $specific_source;

        undef $specific_client if( ($specific_client) && ($specific_client =~ m/[&'%\\\/]/) );
        $specific_client = lc $specific_client if $specific_client;

        figurePIDFileStuff();
        checkConfig();
        $log = new Loghandler($conf->{"logfile"});
        $log->truncFile("");
        $log->addLogLine("****************** Starting ******************");

        # defang
        undef $runJobID if($runJobID =~ m/[&'%\\\/]/);
        $runJobID =~ s/\D//g if $runJobID; #remove non-numeric values. We expect and ID number here

        if($action eq 'run_marc_test')
        {
            runTest() if($testMARC);
            exit;
        }

        setupDB();

        createDatabase();

        my $writePid = new Loghandler($lockfile);
        $writePid->truncFile("running");

        my $cwd = getcwd();
        # This is for debugging, an additional screenshot folder
        # for the devs to view the output easier than using the web UI
        if($debug)
        {
            $screenShotDIR = "$cwd/screenshots";
            mkdir $screenShotDIR unless -d $screenShotDIR;
        }

        if($action eq 'run_scrapers')
        {
            runScrapers();
        }
        elsif($action eq 'run_jobs')
        {
            runProcessMarcJobs();
        }
        elsif($action eq 'run_ils_check')
        {
            runCheckILSLoaded();
        }
        elsif($action eq 'www_actions')
        {
            runWWWActions();
        }
        elsif($action eq 'fire_emails')
        {
            runEmails();
        }

        undef $writePid;
        unlink $lockfile;

        $log->addLogLine("****************** Ending ******************");

    }
    else
    {
        print "Your config file needs to specify a logfile\n";
    }
}
else
{
    print "Something went wrong with the config\n";
    exit;
}

sub runScrapers
{
    my %all = %{getScraperJobs()};
    while ( (my $key, my $value) = each(%all) )
    {
        # my $folder = "/mnt/evergreen/tmp/auto_rec_load/tmp/1"; # setupDownloadFolder($key);
        my $folder = setupDownloadFolder($key);
        initializeBrowser($folder);
        my %details = %{$value};
        if( checkFolders(\%details) ) # make sure that the output folders are pre-created. We expect that these are special and have external mechanism for them.
        {
            # turn off local screenshots, and only write to the web screenshot folder
            $screenShotDIR = undef if !$debug;
            $vendor = $details{"sourcename"} . '_' . $details{"clientname"};
            print "Scraping on: '$vendor'\n";
            my $json = decode_json( $details{"json"} );
            my $source;
            my $perl = '$source = new ' . $details{"perl_mod"} .'($log, $dbHandler, $stagingTablePrefix, $debug, '.
                       '$key, "' . $vendor . '", $driver, $screenShotDIR, $folder, $json, ' . $details{"clientid"} .', ' . $details{"jobid"} .');';
            print $perl . "\n" if $debug;
            # Instantiate the perl Module
            {
                local $@;
                eval
                {
                    eval $perl;
                    die if $source->getError();
                    1;  # ok
                } or do
                {
                    writeTrace( $@ || "instantiation error: " . $details{"perl_mod"}, $details{"jobid"} );
                    queueNotice($details{"jobid"}, 'scraper', 'fail', $@ || "instantiation error");
                    next;
                };
            }
            # Run the scrape function
            {
                local $@;
                eval
                {
                    print "Scraping\n" if $debug;
                    $source->scrape();
                    # $source->processDownloadedFile('test','/mnt/evergreen/tmp/auto_rec_load/tmp/2/extract/20210928_331263_spst-ebooks_Express-MARC8_Add.mrc');
                    die if $source->getError();
                    writeTrace( concatTrace('', $source->getTrace(), ''), $details{"jobid"} );
                    queueNotice($details{"jobid"}, 'scraper', 'success');
                    1;  # ok
                } or do
                {
                    print "had error\n";
                    print $@ . "\n";
                    print $source->getError(). "\n";
                    writeTrace( concatTrace('', $source->getTrace(), $source->getError()), $details{"jobid"});
                    my $evalError = concatTrace( $@ || "error", $source->getTrace(), $source->getError());
                    queueNotice($details{"jobid"}, 'scraper', 'fail', $evalError); # appending the error to the message in case the template doesn't utilize it
                    next;
                };
            }
            concatTrace('', $source->getTrace(), '');
            undef $source;
        }
        else
        {
            printError("Scheduler Output folder doesn't exist");
        }
    }
    closeBrowser();
}

sub runProcessMarcJobs
{
    my @jobs = @{getProcessMarcReadyJobs()};
    foreach(@jobs)
    {
        my $thisJobID = $_;
        print "Working on: '$thisJobID'\n";
        my $tJob;
        # $tJob = new job($log, $dbHandler, $stagingTablePrefix, $debug, $thisJobID);
        my $perl = '$tJob = new job($log, $dbHandler, $stagingTablePrefix, $debug, $thisJobID);';
        print $perl . "\n" if $debug;
        # Instantiate the Job
        {
            local $@;
            eval
            {
                eval $perl;
                die if $tJob->getError();
                1;  # ok
            } or do
            {
                writeTrace( $@ || "instantiation error", $thisJobID );
                queueNotice($thisJobID, 'processmarc', 'fail', $@ || "instantiation error");
                next;
            };
        }
        # Run the runJob function
        {
            local $@;
            eval
            {
                print "Executing job: '$thisJobID'\n";
                $tJob->runJob();
                die if $tJob->getError();
                writeTrace( concatTrace('', $tJob->getTrace(), ''), $thisJobID );
                queueNotice($thisJobID, 'processmarc', 'success');
                1;  # ok
            } or do
            {
                writeTrace( concatTrace('', $tJob->getTrace(), $tJob->getError()), $thisJobID);
                my $evalError = concatTrace( $@ || "error", $tJob->getTrace(), $tJob->getError());
                queueNotice($thisJobID, 'processmarc', 'fail', $evalError); # appending the error to the message in case the template doesn't utilize it
                next;
            };
        }
        undef $tJob;
    }
}

sub runCheckILSLoaded
{
    my @jobs = @{getILSConfirmationJobs()};
    foreach(@jobs)
    {
        my $thisJobID = $_;
        print "Checking ILS Load for job: '$thisJobID'\n";
        my $tJob;
        # $tJob = new job($log, $dbHandler, $stagingTablePrefix, $debug, $thisJobID);
        my $perl = '$tJob = new job($log, $dbHandler, $stagingTablePrefix, $debug, $thisJobID);';
        print $perl . "\n" if $debug;
        # Instantiate the Job
        {
            local $@;
            eval
            {
                eval $perl;
                die if $tJob->getError();
                1;  # ok
            } or do
            {
                writeTrace( $@ || "instantiation error", $thisJobID );
                queueNotice($thisJobID, 'ilsload', 'fail', $@ || "instantiation error");
                next;
            };
        }
        # Run the runCheckILSLoaded function
        {
            local $@;
            eval
            {
                print "Executing job: '$thisJobID'\n";
                $tJob->runCheckILSLoaded();
                die if $tJob->getError();
                writeTrace( concatTrace('', $tJob->getTrace(), ''), $thisJobID );
                queueNotice($thisJobID, 'ilsload', 'success');
                1;  # ok
            } or do
            {
                writeTrace( concatTrace('', $tJob->getTrace(), $tJob->getError()), $thisJobID);
                my $evalError = concatTrace( $@ || "error", $tJob->getTrace(), $tJob->getError());
                queueNotice($thisJobID, 'ilsload', 'fail', $evalError); # appending the error to the message in case the template doesn't utilize it
                next;
            };
        }
        concatTrace('', $tJob->getTrace(), '');
        undef $tJob;
    }
}

sub runTest
{
    print "Testing MARC manipulations: $testMARC\n";
    my $cwd = getcwd();
    my $marcin = "$cwd/test.mrc";
    if(!(-e $marcin))
    {
        print "Can't test without some MARC, please provide 'test.mrc' in current working directory\n";
    }
    my $before = new Loghandler("$cwd/before.txt");
    my $after = new Loghandler("$cwd/after.txt");
    $before->truncFile("");
    $after->truncFile("");
    my $file = MARC::File::USMARC->in($marcin);
    my @types = ("adds", "updates");
    my $count = 0;
    while ( my $marc = $file->next() )
    {
        my $pristine = $marc->clone;
        foreach(@types)
        {
            $count++;
            my $marc2 = $pristine->clone;
            my $editor = new marcEditor($log, $debug, $_);
            $before->addLine("***********Test $count - Type: $_**************");
            $after->addLine("***********Test $count - Type: $_**************");
            $before->addLine($marc2->as_formatted());
            print "Running manipulator\n'$testMARC'\n";
            $marc2 = $editor->manipulateMARC($testMARC, $marc2, "Test Dummy");
            $after->addLine($marc2->as_formatted());
            $before->addLine("***********End Test $count**************");
            $after->addLine("***********End Test $count**************");
            foreach my $i (0..10)
            {
                my $rand = $mobUtil->generateRandomString(30);
                $before->addLine($rand);
                $after->addLine($rand);
            }
            undef $editor;
            undef $marc2;
        }
        undef $pristine;
    }
    print "The before and after files are here:\n" . $before->getFileName() . "\n" . $after->getFileName() . "\n";
    exit;
}

sub getProcessMarcReadyJobs
{
    my @ret = ();
    my $query = "";
    if($runJobID && trim($runJobID) != '')
    {
        # When the user wants us to run a specific job, we need to reset it
        $query = "
        UPDATE auto_import_status
        SET
        status='new',
        record_tweaked = NULL,
        itype = NULL,
        loaded = 0,
        no856s_remain = 0,
        out_file = NULL
        WHERE job = ?";
        my @vals = ($runJobID);
        $log->addLogLine($query);
        $log->addLogLine(Dumper(\@vals));
        $dbHandler->updateWithParameters($query, \@vals);

        $query = "
        UPDATE $stagingTablePrefix"."_job
        SET
        start_time = null,
        status = 'ready',
        current_action_num = 0,
        current_action = ''
        WHERE
        id = ?
        ";
        $log->addLogLine($query);
        $log->addLogLine(Dumper(\@vals));
        $dbHandler->updateWithParameters($query, \@vals);
        undef @vals;
    }
    $query = "
    SELECT
    job.id
    FROM
    $stagingTablePrefix"."_job job
    where
    job.status = 'ready'
    AND type = 'processmarc'
    AND job.start_time is null
    AND job.run_time < NOW()
    ___specificJob___
    order by 1
    ";

    $query =~ s/___specificJob___/AND job.id = $runJobID/g if ($runJobID && trim($runJobID) != '');
    $query =~ s/___specificJob___//g if !($runJobID && trim($runJobID) != '');


    $log->addLogLine($query);
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        push (@ret, $row[0]);
    }
    print Dumper(@ret) if $debug;
    return \@ret;
}

sub getILSConfirmationJobs
{
    # my @ret = (3);
    # return \@ret;
    my $query = "
    SELECT
    distinct job.id
    FROM
    $stagingTablePrefix"."_job job
    JOIN $stagingTablePrefix"."_import_status ais ON (ais.job=job.id)
    WHERE
    ais.loaded = 0
    order by 1
    ";
    $log->addLogLine($query);
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        push (@ret, $row[0]);
    }
    print Dumper(@ret) if $debug;
    return \@ret;
}

sub createScraperJobs
{
    # gather up all of the enabled sources, ignoring those that already have a scraper job pending
    my $query = "
    SELECT
    source.id,source.scrape_interval,max(job.run_time)
    FROM
    $stagingTablePrefix"."_source source
    LEFT JOIN $stagingTablePrefix"."_job job on (job.source = source.id and job.type='scraper')
    WHERE
    source.enabled IS TRUE
    AND source.id NOT IN
    (
    SELECT
    source.id
    FROM
    $stagingTablePrefix"."_source source2
    JOIN $stagingTablePrefix"."_job job2 on (job2.source = source2.id and job2.type='scraper' and job2.status='new')
    WHERE
    source.enabled IS TRUE
    )
    GROUP BY 1,2
    ";
    $log->addLogLine($query) if $debug;
    my @results = @{$dbHandler->query($query)};
    my %creates = ();
    foreach(@results)
    {
        my @row = @{$_};
        my $sourceID = $row[0];
        my $scrape_interval = $row[1];
        my $last_run = $row[2];
        $scrape_interval = '1 MONTH' if($scrape_interval eq '');
        my $run_time = "'$last_run' + INTERVAL $scrape_interval";
        $run_time = 'NOW()' if($last_run eq ''); # set the job to run now if it's never been run before
        $creates{$row[0]} = $run_time;
    }
    $log->addLogLine("Creating new scraper jobs:\n" . Dumper(\%creates));
    while ( (my $key, my $run_time) = each(%creates) )
    {
        insertOneScraperJob($key, $run_time);
    }
    if($specific_client && $specific_source) # if the user wants a special run, we might need to make a special scraper job
    {
        print "User wants special job\n";
        $query = "SELECT
        source.id,client.name,source.name,job.id,job.run_time < (NOW() + INTERVAL 1 MINUTE), (NOW() - INTERVAL 1 minute)
        FROM
        $stagingTablePrefix"."_client client
        JOIN $stagingTablePrefix"."_source source ON (source.client=client.id)
        JOIN $stagingTablePrefix"."_job job ON (job.source=source.id)
        WHERE
        job.type='scraper'
        AND job.status='new'
        AND LOWER(source.name) = '$specific_source'
        AND LOWER(client.name) = '$specific_client'";
        $log->addLogLine($query) if $debug;
        @results = @{$dbHandler->query($query)};
        if($#results > -1)
        {
            my @row = @{$results[0]};
            my $jobid = $row[3];
            my $is_future = $row[4];
            my $run_time = $row[5];
            if($is_future eq '0')
            {
                $query = "UPDATE $stagingTablePrefix"."_job set run_time = ? WHERE id = ?";
                my @vals = ($run_time, $jobid);
                $log->addLogLine($query) if $debug;
                $log->addLogLine(Dumper(\@vals)) if $debug;
                $dbHandler->updateWithParameters($query, \@vals);
            }
        }
        else
        {
            $query = "SELECT
            source.id
            FROM
            $stagingTablePrefix"."_client client
            JOIN $stagingTablePrefix"."_source source ON (source.client=client.id)
            WHERE
            LOWER(source.name) = '$specific_source'
            AND LOWER(client.name) = '$specific_client'";
            $log->addLogLine($query) if $debug;
            @results = @{$dbHandler->query($query)};
            if($#results > -1)
            {
                my @row = @{$results[0]};
                insertOneScraperJob($row[0], 'NOW()');
            }
        }
    }
}

sub insertOneScraperJob
{
    my $source = shift;
    my $run_time = shift;
    my $query = "INSERT INTO $stagingTablePrefix"."_job (source, type) VALUES(?,?)";
    my @vals = ($source, 'scraper');
    $log->addLogLine($query) if $debug;
    $log->addLogLine(Dumper(\@vals)) if $debug;
    $dbHandler->updateWithParameters($query, \@vals);
    my $id = getNewestJob($source, 'scraper');
    if($id)
    {
        $query = "UPDATE $stagingTablePrefix"."_job
        SET
        run_time = $run_time
        WHERE
        id = ?";
        @vals = ($id);
        $log->addLogLine($query) if $debug;
        $log->addLogLine(Dumper(\@vals)) if $debug;
        $dbHandler->updateWithParameters($query, \@vals);
    }
    return $id;
}

sub getNewestJob
{
    my $source = shift;
    my $type = shift;
    my $ret = 0;
    my $query = "SELECT MAX(id) FROM $stagingTablePrefix"."_job
    WHERE
    source = ? AND
    type = ? AND
    status = 'new'";
    my @vals = ($source, $type);
    my @results = @{$dbHandler->query($query, \@vals)};
    foreach(@results)
    {
        my @row = @{$_};
        $ret = $row[0];
    }
    return $ret;
}

sub getScraperJobs
{
    createScraperJobs();
    my @ret = ();
    my %sources = ();
    my @order = ();
    my $query = "
    SELECT
    source.id,client.name,source.name,source.type,source.perl_mod,source.json_connection_detail,client.id,scrape_img_folder,job.id
    FROM
    $stagingTablePrefix"."_client client
    JOIN $stagingTablePrefix"."_source source ON (source.client=client.id)
    JOIN $stagingTablePrefix"."_job job ON (job.source=source.id)
    WHERE
    client.id=client.id
    AND job.type='scraper'
    AND job.status='new'
    AND source.enabled IS TRUE
    ___specific_source___
    ___specific_client___
    ___specificJob___
    ORDER BY 2 desc,1
    ";

    if (!$specific_source && !$specific_client)
    {
        my $fill = "AND source.id IN (select source from $stagingTablePrefix"."_job WHERE AND type='scraper' AND run_time < (NOW() + INTERVAL 1 MINUTE) )";
        $query =~ s/___specific_client___/$fill/g;
    }
    else
    {
        # remove enabled requirement when humans want to run it by hand
        $query =~ s/AND source.enabled IS TRUE//g;
    }
    $query =~ s/___specific_source___/AND LOWER(source.name) = '$specific_source'/g if $specific_source;
    $query =~ s/___specific_source___//g if !$specific_source;

    $query =~ s/___specific_client___/AND LOWER(client.name) = '$specific_client'/g if $specific_client;
    $query =~ s/___specific_client___//g if !$specific_client;

    $query =~ s/___specificJob___/AND job.id = $runJobID/g if $runJobID;
    $query =~ s/AND job.status='new'//g if $runJobID; # remove "new" requirement if specified JOBID argument

    $query =~ s/___specificJob___//g if !$runJobID;

    $log->addLogLine($query);
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        my %hash = ();
        my $sid = shift @row;
        $hash{"clientname"} = shift @row;
        $hash{"sourcename"} = shift @row;
        $hash{"type"} = shift @row;
        $hash{"perl_mod"} = shift @row;
        $hash{"json"} = shift @row;
        $hash{"clientid"} = shift @row;
        $hash{"scrape_img_folder"} = shift @row;
        $hash{"jobid"} = shift @row;
        $hash{"json"} =~ s/\\([^\\])/\\\\$1/g; #escape backslashes
        $sources{$sid} = \%hash;
    }
    print Dumper(%sources) if $debug;
    return \%sources;
}

sub runEmails
{
    print "Firing Emails\n";
    my $query = "
    SELECT
    id
    FROM
    $stagingTablePrefix"."_notice_history
    WHERE
    status = 'pending' AND
    send_time IS NULL
    ORDER BY 1";
    $log->addLogLine($query);
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        print "Firing: " . $row[0] . "\n";
        my $notice = new notice($log, $dbHandler, $stagingTablePrefix, $debug, $row[0]);
        $notice->fire();
        undef $notice;
    }

}

sub runWWWActions
{
    my @types = ('emailme', 'emit');

    my $query = "SELECT referenced_id, misc_data, id
    FROM
    $stagingTablePrefix"."_wwwaction
    WHERE
    status = 'new' AND
    type = ?";
    foreach(@types)
    {
        my $type = $_;
        my @vars = ($type);
        my @results = @{$dbHandler->query($query, \@vars)};
        $log->addLogLine($query);
        $log->addLogLine(Dumper(\@vars));
        foreach(@results)
        {
            my @row = @{$_};
            if($type eq 'emailme')
            {
                my $n = new notice($log, $dbHandler, $stagingTablePrefix, $debug, $row[0]);
                my $data = $n->getData();
                undef $n;
                my $notice = new notice($log, $dbHandler, $stagingTablePrefix, $debug);
                $notice->setData($data);
                print "Sending override to: " . $row[1] . "\n";
                $notice->fire($row[1]);
                undef $notice;
                undef $data;
            }
            my $uquery = "UPDATE 
            $stagingTablePrefix"."_wwwaction
            SET status = 'processed'
            WHERE id = ?";
            @vars = ($row[2]);
            $log->addLogLine($uquery);
            $log->addLogLine(Dumper(\@vars));
            $dbHandler->updateWithParameters($uquery, \@vars);
        }
    }
}

sub escapeData
{
    my $d = shift;
    $d =~ s/'/\\'/g;   # ' => \'
    $d =~ s/\\/\\\\/g; # \ => \\
    return $d;
}

sub initializeBrowser
{
    my $downloadFolder = shift;

    closeBrowser();
    undef $driver;

    $Selenium::Remote::Driver::FORCE_WD3=1;
    my $profile = Selenium::Firefox::Profile->new;
    $profile->set_preference('browser.download.folderList' => '2');
    $profile->set_preference('browser.download.dir' => $downloadFolder);
    # $profile->set_preference('browser.helperApps.neverAsk.saveToDisk' => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/pdf;text/plain;application/text;text/xml;application/xml;application/xls;text/csv;application/xlsx");
    $profile->set_preference('browser.helperApps.neverAsk.saveToDisk' => "application/vnd.ms-excel; charset=UTF-16LE; application/zip; text/csv");
    # $profile->set_preference('browser.helperApps.neverAsk.saveToDisk' => "");
    $profile->set_preference("browser.helperApps.neverAsk.openFile" =>"application/vnd.ms-excel; charset=UTF-16LE; application/zip; text/csv");
    $profile->set_boolean_preference('browser.download.manager.showWhenStarting' => 0);
    $profile->set_boolean_preference('pdfjs.disabled' => 1);
    $profile->set_boolean_preference('browser.helperApps.alwaysAsk.force' => 0);
    $profile->set_boolean_preference('browser.download.manager.useWindow' => 0);
    $profile->set_boolean_preference("browser.download.manager.focusWhenStarting" => 0);
    $profile->set_boolean_preference("browser.download.manager.showAlertOnComplete" => 0);
    $profile->set_boolean_preference("browser.download.manager.closeWhenDone" => 1);
    $profile->set_boolean_preference("browser.download.manager.alertOnEXEOpen" => 0);

    $driver = Selenium::Remote::Driver->new
    (
        binary => '/usr/bin/geckodriver',
        browser_name  => 'firefox',
        firefox_profile => $profile
    );
    $driver->set_window_size(1200,1500);
}

sub closeBrowser
{
    $driver->quit if $driver;
}

sub writeTrace
{
    my $trace = shift;
    my $job = shift;
    print "Writing trace: $job\n";
    return unless $job;
    my @traceRow = @{getTraceRow($job)};
    my @vars = ($trace, $job);
    my $query =
    "UPDATE
    $stagingTablePrefix"."_job_trace
    set
    trace = ?
    where
    id = ?";
    if(!$traceRow[0])
    {
        $query = "INSERT INTO $stagingTablePrefix"."_job_trace (trace, job)
        values(?,?)";
    }
    $dbHandler->updateWithParameters($query, \@vars);
}

sub getTraceRow
{
    my $job = shift;
    my @ret = ();
    print "Getting trace Row\n";
    my $query = "
    SELECT
    id, trace
    FROM
    $stagingTablePrefix"."_job_trace 
    WHERE
    job = ?";
    my @vars = ($job);
    my @results = $dbHandler->query($query, \@vars);
    foreach(@results)
    {
        my @row = @{$_};
        push @ret, $row[0];
        push @ret, $row[1];
    }
    print "Got trace Row\n";
    return \@ret;
}

sub queueNotice
{
    my $job = shift;
    my $type = shift;
    my $upon_status = shift;
    my $notice = new notice($log, $dbHandler, $stagingTablePrefix, $debug);
    $notice->queueNotice($job, $type, $upon_status);
}

sub failJob
{
    my $job = shift;
    my $query = "UPDATE $stagingTablePrefix"."_job
    SET
    status = 'failed'
    WHERE
    id = ?";
    my @vars = ($job);
    $log->addLogLine($query);
    $log->addLogLine(Dumper(\@vals));
    $dbHandler->updateWithParameters($query, \@vals);
}

sub setupDownloadFolder
{
    my $subFolder = shift;
    my $folder = $conf{"tmpspace"}."/$subFolder";
    print "Creating Folder: $folder\n";
    remove_tree($folder) if(-d $folder); #reset folder
    my $tries = 0;
    my $giveUpAfter = 10;
    while(!(-d $folder) && ($tries < $giveUpAfter))
    {
        make_path($folder, {
            chmod => 0777,
        });
        $tries++;
        sleep 1;
    }
    return $folder;
}

sub setupDB
{
    eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"}||"3306","mysql", 1);};
    if ($@)
    {
        print "Could not establish a connection to the database\n";
        printError("Could not establish a connection to the database");
        exit 1;
    }
    $databaseName = $conf{"db"};
}

sub createDatabase
{
    if($recreateDB)
    {
        print "Re-creting database\n";
        my $query = "DROP TRIGGER IF EXISTS $stagingTablePrefix"."_job_update";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TRIGGER IF EXISTS $stagingTablePrefix"."_import_status_update_deleted";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_wwwaction";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_wwwpages";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_wwwusers";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_job_trace";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_notice_history";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_notice_template";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_import_status";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_output_file_track";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_file_track";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_job";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_source";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_client";
        $log->addLine($query);
        $dbHandler->update($query);
        $query = "DROP TABLE IF EXISTS $stagingTablePrefix"."_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
        
        ##################
        # TABLES
        ##################

        $query = "CREATE TABLE $stagingTablePrefix"."_cluster (
        id int not null auto_increment,
        name varchar(100),
        type varchar(100),
        postgres_host varchar(100),
        postgres_db varchar(100),
        postgres_port varchar(100),
        postgres_username varchar(100),
        postgres_password varchar(100),
        PRIMARY KEY (id),
        INDEX (name)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_client (
        id int not null auto_increment,
        name varchar(100),
        cluster int,
        PRIMARY KEY (id),
        UNIQUE INDEX (name),
        FOREIGN KEY (cluster) REFERENCES $stagingTablePrefix"."_cluster(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_source (
        id int not null auto_increment,
        enabled boolean default true,
        last_scraped datetime,
        name varchar(100),
        type varchar(100),
        client int,
        perl_mod varchar(50),
        marc_editor_function varchar(100),
        scrape_img_folder varchar(1000),
        scrape_interval varchar(100) DEFAULT '1 MONTH',
        json_connection_detail varchar(5000),
        PRIMARY KEY (id),
        FOREIGN KEY (client) REFERENCES $stagingTablePrefix"."_client(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_job (
        id int not null auto_increment,
        type varchar(100) DEFAULT 'processmarc',
        source int,
        create_time datetime DEFAULT CURRENT_TIMESTAMP,
        run_time datetime DEFAULT now(),
        start_time datetime,
        last_update_time datetime DEFAULT CURRENT_TIMESTAMP,
        current_action varchar(1000),
        status varchar(100) default 'new',
        current_action_num int DEFAULT 0,
        PRIMARY KEY (id),
        FOREIGN KEY (source) REFERENCES $stagingTablePrefix"."_source(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_file_track (
        id int not null auto_increment,
        fkey varchar(1000),
        filename varchar(1000),
        client int,
        source int,
        size int,
        grab_time datetime DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        INDEX (fkey),
        FOREIGN KEY (client) REFERENCES $stagingTablePrefix"."_client(id) ON DELETE RESTRICT,
        FOREIGN KEY (source) REFERENCES $stagingTablePrefix"."_source(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_output_file_track (
        id int not null auto_increment,
        filename varchar(1000),
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_import_status (
        id int not null auto_increment,
        file int,
        status varchar(100) DEFAULT 'new',
        record_raw mediumtext,
        record_tweaked mediumtext,
        tag varchar(100),
        z001 varchar(100),
        loaded BOOLEAN DEFAULT FALSE,
        no856s_remain BOOLEAN DEFAULT FALSE,
        ils_id varchar(100),
        itype varchar(10),
        insert_time datetime DEFAULT CURRENT_TIMESTAMP,
        job int,
        out_file int,
        deleted BOOLEAN DEFAULT FALSE,
        PRIMARY KEY (id),
        FOREIGN KEY (file) REFERENCES $stagingTablePrefix"."_file_track(id) ON DELETE RESTRICT,
        FOREIGN KEY (job) REFERENCES $stagingTablePrefix"."_job(id) ON DELETE RESTRICT,
        FOREIGN KEY (out_file) REFERENCES $stagingTablePrefix"."_output_file_track(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_notice_template (
        id int not null auto_increment,
        name varchar(100),
        enabled boolean default true,
        source int,
        type varchar(100) DEFAULT 'scraper',
        upon_status varchar(100) DEFAULT 'success',
        template text(60000),
        CONSTRAINT single_template_per_source UNIQUE (source, type, upon_status),
        PRIMARY KEY (id),
        FOREIGN KEY (source) REFERENCES $stagingTablePrefix"."_source(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_notice_history (
        id int not null auto_increment,
        notice_template int,
        status varchar(100) DEFAULT 'pending',
        job int,
        create_time datetime DEFAULT CURRENT_TIMESTAMP,
        send_time datetime DEFAULT NULL,
        data text(65000),
        send_status varchar(100) DEFAULT 'new',
        PRIMARY KEY (id),
        FOREIGN KEY (notice_template) REFERENCES $stagingTablePrefix"."_notice_template(id) ON DELETE RESTRICT,
        FOREIGN KEY (job) REFERENCES $stagingTablePrefix"."_job(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_job_trace (
        id int not null auto_increment,
        job int,
        trace text(65000) DEFAULT null,
        PRIMARY KEY (id),
        FOREIGN KEY (job) REFERENCES $stagingTablePrefix"."_job(id) ON DELETE RESTRICT
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_wwwpages (
        id int not null auto_increment,
        name varchar(1000),
        class_name varchar(1000),
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "INSERT INTO $stagingTablePrefix"."_wwwpages (name, class_name)
        values
        ('Dashboard','dashboardUI'),
        ('Files','filesUI'),
        ('Vendors','vendorsUI')
        ";
        $log->addLine($query) if $debug;
        # This table has it's seed data in db_seed.db
        # $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_wwwusers (
        id int not null auto_increment,
        username varchar(100) not null,
        password varchar(100) not null,
        first_name varchar(100),
        last_name varchar(100),
        phone1 varchar(50),
        phone2 varchar(50),
        address1 varchar(100),
        address2 varchar(100),
        email_address varchar(300),
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "INSERT INTO $stagingTablePrefix"."_wwwusers (username, password, first_name, last_name)
        values('admin', md5(\'password\'), 'MOBIUS', 'ADMIN')";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_wwwaction (
        id int not null auto_increment,
        type varchar(100) not null,
        status varchar(100) not null DEFAULT 'new',
        referenced_id int,
        misc_data text(10000),
        create_time datetime DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        ##################
        # FUNCTIONS
        ##################

        $query = "CREATE TRIGGER $stagingTablePrefix"."_job_update BEFORE UPDATE ON $stagingTablePrefix"."_job
        FOR EACH ROW
        BEGIN
            IF NEW.current_action != OLD.current_action THEN
                SET NEW.last_update_time = NOW();
                SET NEW.current_action_num = OLD.current_action_num + 1;
            END IF;
            IF NEW.status != OLD.status THEN
                SET NEW.last_update_time = NOW();
                SET NEW.current_action_num = OLD.current_action_num + 1;
            END IF;
        END;
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TRIGGER $stagingTablePrefix"."_import_status_update_deleted BEFORE UPDATE ON $stagingTablePrefix"."_import_status
        FOR EACH ROW
        BEGIN
            IF NEW.deleted THEN
                SET NEW.record_raw = NULL;
                SET NEW.record_tweaked = NULL;
            END IF;
        END;
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        seedDB($dbSeed) if $dbSeed;

    }
    
}

sub seedDB
{
    my $seedFile = shift;
    my $readFile = new Loghandler($seedFile);
    $log->addLine("Reading seeDB File $seedFile");
    my @lines = @{$readFile->readFile()};

    my $currTable = '';
    my @cols = ();
    my $insertQuery = "";
    my @datavals = ();
    foreach(@lines)
    {
        my $line = $_;
        $line = trim($line);
        if($line =~ m/^\[/)
        {
            if( ($#cols > -1) && ($#datavals > -1) )
            {
                # execute the insert
                @flatVals = ();
                my $insertLog = $insertQuery;
                foreach(@datavals)
                {
                    my @row = @{$_};
                    $insertQuery .= "(";
                    $insertLog .= "(";
                    $insertQuery .= ' ? ,' foreach(@row);
                    $insertLog .= " '$_' ," foreach(@row);
                    $insertQuery = substr($insertQuery,0,-1);
                    $insertLog = substr($insertLog,0,-1);
                    $insertQuery .= "),\n";
                    $insertLog .= "),\n";
                    push @flatVals, @row;
                }
                $insertQuery = substr($insertQuery,0,-2);
                $insertLog = substr($insertLog,0,-2);
                $log->addLine($insertLog);
                $dbHandler->updateWithParameters($insertQuery,\@flatVals);
                undef @flatVals;
                @datavals = ();
            }
            $log->addLine("seedDB: Detected client delcaration") if $debug;
            $currTable = $line;
            $currTable =~ s/^\[([^\]]*)\]/$1/g;
            $log->addLine("Heading $currTable") if $debug;
            @cols = @{figureColumnsFromTable($currTable)};
            my @temp = ();
            $insertQuery = "INSERT INTO $stagingTablePrefix"."_$currTable (";
            foreach(@cols)
            {
                $insertQuery .= "$_," if($_ ne 'id');
                push @temp, $_ if($_ ne 'id');
            }
            @cols = @temp;
            undef @temp;
            $insertQuery = substr($insertQuery,0,-1);
            $insertQuery .= ")\nvalues\n";
            $log->addLine(Dumper(\@cols)) if $debug;
            $log->addLine(Dumper($#cols)) if $debug;
        }
        elsif($currTable)
        {
            $log->addLine($line);
            
            my @vals = split(/\t/,$line);
            $log->addLine("Split and got\n".Dumper(\@vals)) if $debug;
            $log->addLine("Expecting $#cols and got $#vals") if $debug;
            if($#vals == $#cols) ## Expected number of columns
            {
                my @v = ();
                my $colPos = 0;
                foreach (@vals)
                {
                    my $val = getForignKey($currTable, $colPos, $_);
                    push @v, $val;
                    $colPos++;
                }
                push @datavals, [@v];
            }
        }
    }
    if( ($#cols > -1) && ($#datavals > -1) )
    {
        # execute the insert
        @flatVals = ();
        my $insertLog = $insertQuery;
        foreach(@datavals)
        {
            my @row = @{$_};
            $insertQuery .= "(";
            $insertLog .= "(";
            $insertQuery .= ' ? ,' foreach(@row);
            $insertLog .= " '$_' ," foreach(@row);
            $insertQuery = substr($insertQuery,0,-1);
            $insertLog = substr($insertLog,0,-1);
            $insertQuery .= "),\n";
            $insertLog .= "),\n";
            push @flatVals, @row;
        }
        $insertQuery = substr($insertQuery,0,-2);
        $insertLog = substr($insertLog,0,-2);
        $log->addLine($insertLog);
        $dbHandler->updateWithParameters($insertQuery,\@flatVals);
        undef @flatVals;
    }
}

sub getForignKey
{
    my $table = shift;
    my $colPos = shift;
    my $value = shift;
    my %convert_map = (
    "import_status_0" => {"table" => "file_track", "colname" => "name"},
    "file_track_1" => {"table" => "client", "colname" => "name"},
    "file_track_2" => {"table" => "source", "colname" => "name"},
    "source_4" => {"table" => "client", "colname" => "name"},
    "client_1" => {"table" => "cluster", "colname" => "name"},
    );
    my $key = $table."_".$colPos;
    if($convert_map{$key})
    {
        print "value \"$value\"";
        $value = escapeData($value); #excape ticks
        my $query = "SELECT id FROM $stagingTablePrefix"."_".$convert_map{$key}{"table"}." WHERE ".$convert_map{$key}{"colname"}." = '$value'";
        $log->addLine($query) if $debug;
        my @results = @{$dbHandler->query($query)};
        if(!$results[0])
        {
            print "Error in seed data mapping on table: '$table' and column '$colPos' with value: '$value'\n";
            exit;
        }
        my @row = @{$results[0]};
        return $row[0];
    }
    return $value;
}

sub figureColumnsFromTable
{
    my $table = shift;
    my @ret = ();
    my $query = "
        SELECT COLUMN_NAME 
        FROM 
        INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA='$databaseName'
        AND TABLE_NAME='$stagingTablePrefix".'_'."$table'";
    $log->addLine($query) if $debug;
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        push @ret, $row[0];
    }
    return \@ret;
}

sub checkConfig
{
    my @reqs = ("logfile","db","dbhost","dbuser","dbpass","port","tmpspace");
    my $valid = 1;
    print Dumper(\%conf);
    for my $i (0..$#reqs)
    {
        if(!$conf{$reqs[$i]})
        {
            print "Required configuration missing from conf file: ".$reqs[$i]."\n";
            exit;
        }
    }
}

sub trim
{
    my $st = shift;
    $st =~ s/^[\s\t]*(.*)/$1/;
    $st =~ s/(.*)[\s\t]*$/$1/;
    return $st;
}

sub dirtrav
{
    my $f = shift;
	my $pwd = shift;
    my @files = @{$f};
	opendir(DIR,"$pwd") or die "Cannot open $pwd\n";
	my @thisdir = readdir(DIR);
	closedir(DIR);
	foreach my $file (@thisdir) 
	{
		if(($file ne ".") and ($file ne ".."))
		{
			if (-d "$pwd/$file")
			{
				push(@files, "$pwd/$file");
				@files = @{dirtrav(\@files,"$pwd/$file")};
			}
			elsif (-f "$pwd/$file")
			{			
				push(@files, "$pwd/$file");			
			}
		}
	}
	return \@files;
}

sub checkFolders
{
    my $d = shift;
    my %details = %{$d};
    my $ret = 1;
    my $json = decode_json( $details{"json"} );
    if(ref $json->{"folders"} eq 'HASH')
    {
        while ( (my $key, my $folder) = each(%{$json->{"folders"}}) )
        {
            print "error '$key' : '$folder' doesn't exist\n" if( !(-d $folder));
            $ret = 0 if( !(-d $folder));
        }
    }
    return $ret;
}


sub concatTrace
{
    my $startingString = shift;
    my $traceArray = shift;
    my $endingString = shift;
    my $ret = $startingString;
    my @trace = @{$traceArray};

    foreach(@trace)
    {
        $ret .= "\r\n$_";
    }
    $ret .= "\r\n" . $endingString;
    $log->addLine($ret) if $debug;
    print $ret if $debug;
    return $ret;
}

sub figureLockFile
{
    my $ret = "/tmp/auto_rec_load-";
    $ret .= "scraper" if $action eq 'run_scrapers';
    $ret .= "scraper-client$specific_client" if $specific_client;
    $ret .= "-source$specific_source" if $specific_source;

    $ret .= "processmarc" if $action eq 'run_jobs';
    $ret .= "processmarc-job$runJobID" if $runJobID;

    $ret .= "testmarc"  if ($action eq 'run_marc_test' && $testMARC);

    $ret .= "ilsload" if ($action eq 'run_ils_check');
    $ret .= ".LOCK";
    return $ret;
}

sub figurePIDFileStuff
{
    print "Looking for: $lockfile\n";
    if (-e $lockfile)
    {
        print "Sorry, it looks like I am already running.\nIf you know that I am not, please delete $lockfile\n";
        # exit;
    }
}

sub printError
{
    my $error = shift;
    print "
    Automatic Record Load Utility - $vendor Import Report Job # $jobid - ERROR
    $error
    
    -Friendly MOBIUS Server-
    ";
}

sub cleanup
{
    # my $lockfile = shift;
    if(-e $lockfile)
    {
        print "I'm dying, deleting PID file $lockfile\n";
        unlink $lockfile;
        print "Deleted '$lockfile'\n";
    }
    closeBrowser();
}

exit;
