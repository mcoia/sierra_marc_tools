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

use dataHandler;
use dataHandlerProquest;

our $stagingTablePrefix = "auto";
our $pidfile = "/tmp/auto_rec_load.pl.pid";


our $driver;
our $dbHandler;
our $databaseName = '';
our $log;
our $debug = 0;
our $recreateDB = 0;
our $dbSeed;
our $specificSource;
our $specificClient;
our $configFile;
our $jobid = -1;
our $vendor = "";

GetOptions (
"config=s" => \$configFile,
"debug" => \$debug,
"recreateDB" => \$recreateDB,
"dbSeed=s" => \$dbSeed,
"specificSource=s" => \$specificSource,
"specificClient=s" => \$specificClient,
)
or die("Error in command line arguments\nYou can specify
--config                                      [Path to the config file]
--debug                                       [Cause more log output]
--recreateDB                                  [Deletes the tables and recreates them]
--dbSeed                                      [DB Seed file - populating the base data]

\n");

if(!$configFile || !(-e $configFile) )
{
    print "Please specify a valid path to a config file\n";
    exit;
}

our $mobUtil = new Mobiusutil();
our $conf = $mobUtil->readConfFile($configFile);


if($conf)
{
    %conf = %{$conf};
    if ($conf{"logfile"})
    {
        figurePIDFileStuff();
        checkConfig();
        $log = new Loghandler($conf->{"logfile"});
        $log->truncFile("****************** Starting ******************");

        setupDB();

        createDatabase();

        my $writePid = new Loghandler($pidfile);
        $writePid->truncFile("running");

        my $cwd = getcwd();
        $cwd .= "/screenshots";
        mkdir $cwd unless -d $cwd;

        my %all = %{getSources()};
        while ( (my $key, my $value) = each(%all) )
        {   
            my $folder = "/mnt/evergreen/tmp/auto_rec_load/tmp/1"; # setupDownloadFolder($key);
            initializeBrowser($folder);
            my %details = %{$value};
            if(!(-d $details{"outputfolder"}))
            {
                print "Scheduler Output folder: '".$details{"outputfolder"}."' doesn't exist\n";
                alertErrorEmail("Scheduler Output folder: '".$details{"outputfolder"}."' doesn't exist");
            }
            else
            {
                $vendor = $details{"sourcename"} . '_' . $details{"clientname"};
                print "Working on: '$vendor'\n";
                my $json = decode_json( $details{"json"} );
                my $source;
                my $perl = '$source = new ' . $details{"perl_mod"} .'($key, "' . $vendor . '"' .
                           ', $dbHandler, $stagingTablePrefix, $driver, $cwd, $log, $debug, $folder, $json, ' . $details{"clientid"} .');';
                print $perl . "\n";
                # Instanciate the perl Module
                {
                    local $@;
                    eval
                    {
                        eval $perl;
                        die if $source->getError();
                        1;  # ok
                    } or do
                    {
                        my $evalError = concatTrace( $@ || "error", $source->getTrace(), $source->getError());
                        alertErrorEmail("Could not instanciate " .$details{"perl_mod"} . "\r\n\r\n$perl\r\n\r\nerror:\r\n\r\n$evalError") if!$debug;
                        next;
                    };
                }
                # Run the scrape function
                {
                    local $@;
                    eval
                    {
                        print "Executing special file parsing\n$folder\n";
# processDownloadedFile / 2021-09-28_0_1 -> /20210928_332503_missouriwestern_export.zip
# processDownloadedFile / 2020-12-28_26_4 -> /20201228_261094_missouriwestern_export.zip
# processDownloadedFile / 2021-02-28_1_0 -> /20210228_277428_missouriwestern_export.zip
# processDownloadedFile / 2021-06-28_22_9 -> /20210628_307429_missouriwestern_export.zip

                        $source->processDownloadedFile("2021-09-28_0_1","/20210628_307429_missouriwestern_export.zip");
                        # print "Scraping\n" if $debug;
                        # $source->scrape();
                        # die if $source->getError();
                        1;  # ok
                    } or do
                    {
                        my $evalError = concatTrace( $@ || "error", $source->getTrace(), $source->getError());
                        alertErrorEmail($evalError) if!$debug;
                        next;
                    };
                }
                concatTrace('', $source->getTrace(), '');
                # Run deal with any data files that were produced
                # {
                    # local $@;
                    # eval
                    # {
                        # print "Scraping\n" if $debug;
                        # $source->scrape();
                        # die if $source->getError();
                        # 1;  # ok
                    # } or do
                    # {
                        # my $evalError = $@ || "error";
                        # my @trace = @{$source->getTrace()};
                        # foreach(@trace)
                        # {
                            # $evalError .= "\r\n$_";
                        # }
                        # $evalError .= "\r\n" . $source->getError();
                        # print $evalError if $debug;
                        # alertErrorEmail($evalError) if!$debug;
                        # next;
                    # };
                # }
            }
        }

        undef $writePid;
        closeBrowser();
        $log->addLogLine("****************** Ending ******************");
    }
    else
    {
        
    }
}
else
{
    print "Something went wrong with the config\n";
    exit;
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

sub getSources
{
    my @ret = ();
    my %sources = ();
    my @order = ();
    my $query = "
    SELECT
    source.id,client.name,source.name,source.type,source.scheduler_folder,source.perl_mod,source.json_connection_detail,client.id
    FROM
    $stagingTablePrefix"."_client client
    join $stagingTablePrefix"."_source source on (source.client=client.id)
    where
    client.id=client.id
    ___specificSource___
    ___specificClient___
    order by 2 desc,1
    ";

    # defang
    undef $specificSource if($specificSource =~ m/[&'%\\\/]/);
    $specificSource = lc $specificSource if $specificSource;

    undef $specificClient if($specificClient =~ m/[&'%\\\/]/);
    $specificClient = lc $specificClient if $specificClient;

    $query =~ s/___specificSource___/AND LOWER(source.name) = '$specificSource'/g if $specificSource;
    $query =~ s/___specificSource___//g if !$specificSource;

    $query =~ s/___specificClient___/AND LOWER(client.name) = '$specificClient'/g if $specificClient;
    $query =~ s/___specificClient___//g if !$specificClient;

    $log->addLogLine($query);
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        my %hash = ();
        $hash{"clientname"} = @row[1];
        $hash{"sourcename"} = @row[2];
        $hash{"type"} = @row[3];
        $hash{"outputfolder"} = @row[4];
        $hash{"perl_mod"} = @row[5];
        $hash{"json"} = @row[6];
        $hash{"clientid"} = @row[7];
        $sources{@row[0]} = \%hash;
    }
    print Dumper(%sources);
    return \%sources;
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
    $profile->set_preference('browser.helperApps.neverAsk.saveToDisk' => "application/vnd.ms-excel; charset=UTF-16LE; application/zip");
    # $profile->set_preference('browser.helperApps.neverAsk.saveToDisk' => "");
    $profile->set_preference("browser.helperApps.neverAsk.openFile" =>"application/vnd.ms-excel; charset=UTF-16LE; application/zip");
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

sub setupDownloadFolder
{
    my $subFolder = shift;
    my $folder = $conf{"tmpspace"}."/$subFolder";
    print "Folder: $folder\n";
    remove_tree($folder) if(-d $folder); #reset folder
    make_path($folder, {
        chmod => 0777,
    });
    return $folder;
}

sub setupDB
{
    eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"}||"3306","mysql");};
    if ($@)
    {
        print "Could not establish a connection to the database\n";
        alertErrorEmail("Could not establish a connection to the database");
        exit 1;
    }
    $databaseName = $conf{"db"};
}

sub createDatabase
{

    if($recreateDB)
    {
        my $query = "DROP TABLE $stagingTablePrefix"."_output_file_track ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_import_status ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_file_track ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_source ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_client ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_job ";
        $log->addLine($query);
        $dbHandler->update($query);
    }

    my @exists = @{$dbHandler->query("SELECT table_name FROM information_schema.tables WHERE table_schema RLIKE '$databaseName' AND table_name RLIKE '$stagingTablePrefix'")};
    if(!$exists[0])
    {
    
        ##################
        # TABLES
        ##################
        my $query = "CREATE TABLE $stagingTablePrefix"."_job (
        id int not null auto_increment,
        start_time datetime DEFAULT CURRENT_TIMESTAMP,
        last_update_time datetime DEFAULT CURRENT_TIMESTAMP,
        current_action varchar(1000),
        status varchar(100) default 'new',
        current_action_num int DEFAULT 0,
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

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
        FOREIGN KEY (cluster) REFERENCES $stagingTablePrefix"."_cluster(id) ON DELETE CASCADE
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_source (
        id int not null auto_increment,
        name varchar(100),
        type varchar(100),
        client int,
        scheduler_folder varchar(500),
        perl_mod varchar(50),
        json_connection_detail varchar(5000),
        PRIMARY KEY (id),
        FOREIGN KEY (client) REFERENCES $stagingTablePrefix"."_client(id) ON DELETE CASCADE
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
        FOREIGN KEY (client) REFERENCES $stagingTablePrefix"."_client(id) ON DELETE CASCADE,
        FOREIGN KEY (source) REFERENCES $stagingTablePrefix"."_source(id) ON DELETE CASCADE
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
        ils_id varchar(100),
        insert_time datetime DEFAULT CURRENT_TIMESTAMP,
        job int,
        PRIMARY KEY (id),
        FOREIGN KEY (file) REFERENCES $stagingTablePrefix"."_file_track(id) ON DELETE CASCADE,
        FOREIGN KEY (job) REFERENCES $stagingTablePrefix"."_job(id) ON DELETE CASCADE
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_output_file_track (
        id int not null auto_increment,
        filename varchar(1000),
        import_id int
        PRIMARY KEY (id),
        FOREIGN KEY (import_id) REFERENCES $stagingTablePrefix"."_import_status(id) ON DELETE CASCADE
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        

        seedDB($dbSeed) if $dbSeed;

    }
    else
    {
        print "Staging table already exists\n";
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
    "source_2" => {"table" => "client", "colname" => "name"},
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
        if(!@results[0])
        {
            print "Error in seed data mapping on table: '$table' and column '$colPos' with value: '$value'\n";
            exit;
        }
        my @row = @{$results[0]};
        return @row[0];
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
        push @ret, @row[0];
    }
    return \@ret;
}

sub checkConfig
{
    my @reqs = ("logfile","db","dbhost","dbuser","dbpass","port","tmpspace");
    my $valid = 1;
    for my $i (0..$#reqs)
    {
        if(!$conf{@reqs[$i]})
        {
            print "Required configuration missing from conf file: ".@reqs[$i]."\n";
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
	my @files = @{@_[0]};
	my $pwd = @_[1];
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

sub figurePIDFileStuff
{
    if (-e $pidfile)
    {
        #Check the processes and see if there is a copy running:
        my $thisScriptName = $0;
        my $numberOfNonMeProcesses = scalar grep /$thisScriptName/, (split /\n/, `ps -aef`);
        print "$thisScriptName has $numberOfNonMeProcesses running\n" if $debug;
        # The number of processes running in the grep statement will include this process,
        # if there is another one the count will be greater than 1
        if($numberOfNonMeProcesses > 1)
        {
            print "Sorry, it looks like I am already running.\nIf you know that I am not, please delete $pidfile\n";
            exit;
        }
        else
        {
            #I'm really not running
            unlink $pidFile;
        }
    }
}

sub alertErrorEmail
{
    my $error = shift;
    my @tolist = ($conf{"alwaysemail"});
    my $email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
    print "Sending an Error email:
    Automatic Record Load Utility - $vendor Import Report Job # $jobid - ERROR
    $error
    
    -Friendly MOBIUS Server-
    ";

    # $email->send("Automatic Record Load Utility - $vendor Import Report Job # $jobid - ERROR","$error\r\n\r\n-Friendly MOBIUS Server-");
}

sub DESTROY
{
    print "I'm dying, deleting PID file $pidFile\n";
    closeBrowser();
    unlink $pidFile;
}

exit;
