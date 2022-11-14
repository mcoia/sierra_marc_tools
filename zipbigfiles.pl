#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright © 2013-2022 MOBIUS
# Blake Graham-Henderson blake@mobiusconsortium.org 2013-2022
# Scott Angel scottangel@mobiusconsoritum.org 2022
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use lib qw(./ ./lib);
use strict;
use warnings FATAL => 'all';

# Modules
use email;
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use File::stat;
use Time::localtime;
use DateTime;
use Loghandler;
use IO::Compress::Gzip qw(gzip $GzipError);
use Getopt::Long;

# Features
use feature 'say';

# we catch the --help parameter and display the documentation
my $printHelp = 0;

# The path of the directory we compress
my $path = '';

# The name of the html report file.
my $outputFile = "./report.html";

# Days old before we compress the file
my $daysToCompress = 0;

# Days old before we delete the file
my $daysToDelete;

# Number of days we keep old records in the report.
my $daysToDrop;

# Email Plain Text || HTML - default to plain text
my $emailType = 0;

# This is the email address we send the final report to
my $emailTo = '';

# This is the email address we send the final report from
my $emailFrom = '';

# The filename
my $HTMLFilePath;

# The Email subject
my $emailSubject = 'Old File Deletion Report';


# Debug - default to OFF
my $debug = 0;

# <<EOSTR;
my $help = "Usage: zipbigfiles.pl [OPTION]...
gZip files in the specified directory of a certain age while removing files of a certain age.

Mandatory arguments
--path              Path to files that will be gzipped.
--outputFile        Name of the html report file.
--daysToCompress    Number of days old the file has to be before it is skipped & not gzipped.
--daysToDelete      Number of days old the file has to be before it is deleted.
--daysToDrop        Number of days we keep records in the report.
--emailType         Email Plain Text or HTML. 0 = Plain, 1 = HTML
--emailTo           Email address to send the final report to.
--emailFrom         Email address of the sender.
--htmlFilePath      HTML file to be use for report templating. If none is specified the default will be used. ex: ./index.html
--emailSubject      Custom Email Subject string, defaults to 'Old File Deletion Report'
--debug             Set debug mode for more verbose output.
";

GetOptions(
    "help"             => \$printHelp,
    "path=s"           => \$path,
    "outputFile=s"     => \$outputFile,
    "daysToCompress=i" => \$daysToCompress,
    "daysToDelete=i"   => \$daysToDelete,
    "daysToDrop=i"     => \$daysToDrop,
    "emailType=i"      => \$emailType,
    "emailTo=s"        => \$emailTo,
    "emailFrom=s"      => \$emailFrom,
    "htmlFilePath=s"   => \$HTMLFilePath,
    "emailSubject=s"   => \$emailSubject,
    "debug"            => \$debug,
);

printHelp();
validateCommandLineArguments();
main();

sub main
{

    my @files;
    my @deletedFiles;
    my @deletedDirectories;
    my @failed;
    my $somethingChanged = 0;
    my @fileReports      = ();

    say "Scanning path: $path" if ($debug);

    #Get all files in the directory path
    @files = @{ traverseDirectory( \@files, $path ) };

    say "Total files found: " . ( $#files + 1 ) if ($debug);

    for my $file (@files)
    {

        my $fileName      = substr( $file, rindex( $file, '/' ) + 1 );
        my $fileDaysOld   = ( -M $file );
        my $fileExtension = substr( $file, rindex( $file, '.' ) + 1 );

        my %fileReport;
        my $compressed = 0;

        say "Age: [$fileDaysOld] Checking file: " . $file if ($debug);

        # Check the age of the file & if it's already zipped or gzipped
        if (   $fileDaysOld > $daysToCompress
            && !( -d $file )
            && ( lc $fileExtension ne "zip" )
            && ( lc $fileExtension ne "gz" ) )
        {

            # zip our file
            %fileReport = %{ zipFile( $fileName, $file ) };
            $compressed = $fileReport{'compressed'};

            # compress the file
            push( @fileReports, \%fileReport );

        }

        # Delete old non-compressed files & directories
        if ( !$compressed && $fileDaysOld > $daysToDelete )
        {

            # directory
            if ( -d $file )
            {

                say "Removing Directory: $file\n" if ($debug);

                opendir( DIR, $file )
                  or die "Cannot open $file\n";
                my @directory = readdir(DIR);
                closedir(DIR);

                if ( $#directory < 2 )
                {
                    $somethingChanged = 1;
                    push( @deletedDirectories, $file );
                    my $worked = rmdir($file);
                    if ( !$worked )
                    {
                        push( @failed, $file );
                    }
                }
            }

            # file
            if ( !( -d $file ) )
            {
                push( @deletedFiles, $file );
                $somethingChanged = 1;

                say "Deleting file $file \n" if ($debug);

                my $worked = unlink($file);
                if ( !$worked )
                {
                    push( @failed, $file );
                }

            }

        }

    }

    # Email Report if something changed
    if ($somethingChanged)
    {

        say "Something changed!" if ($debug);

        # NOTE: fileReports isn't actually in the HTML, Email report. Left for future development.

        my %report = ();
        $report{deletedFiles}       = \@deletedFiles;
        $report{deletedDirectories} = \@deletedDirectories;
        $report{failed}             = \@failed;
        $report{fileReports}        = \@fileReports;

        my $HTML      = buildHTML( \%report );
        my $plainText = buildPlainText( \%report );

        # Email the report
        say "sending email" if ($debug);

        sendEmailReport( $plainText, $HTML );

        # Log the report
        say "logging report" if ($debug);
        logReport($HTML);

    }

}

sub printHelp
{

    # --help
    if ($printHelp)
    {
        print $help;
        exit 0;
    }

}

sub validateCommandLineArguments
{

    printCommandLineArguments() if ($debug);

    say "Checking command line arguments..." if ($debug);

    ## BEGIN Path validation

    # check if the path variable is set
    if ( $path eq '' )
    {
        say "Path variable not set. Please pass in a command line path argument with --path=";
        exit 1;
    }

    # verify the path exists and is actually a directory
    if ( !( -e $path ) )
    {
        say "Path does NOT exist! Please check your --path argument and try again.";
        say $path if ($debug);
        exit 1;
    }

    # verify the path exists and is actually a directory
    if ( !( -d $path ) )
    {
        say "Path is NOT a directory! Please check your --path argument and try again.";
        say $path if ($debug);
        exit 1;
    }

    # Trim any trailing / on path
    $path =~ s/\/$//;

    ## END Path validation

    # check if the emailTo variable is set
    if ( $emailTo eq '' )
    {
        say "EmailTo variable not set. Please pass in a command line 'emailTo' argument with --emailTo=";
        exit 1;
    }

    # check if the emailFrom variable is set
    if ( $emailFrom eq '' )
    {
        say "EmailFrom variable not set. Please pass in a command line 'emailFrom' argument with --emailFrom=";
        exit 1;
    }

}

sub printCommandLineArguments
{

    say "\n--- command line arguments ---";
    say "path=" . $path;
    say "outputFile:" . $outputFile;
    say "daysToCompress:" . $daysToCompress;
    say "daysToDelete:" . $daysToDelete;
    say "daysToDrop:" . $daysToDrop;
    say "emailType:" . $emailType;
    say "emailTo:" . $emailTo;
    say "emailFrom:" . $emailFrom;
    say "htmlFilePath:" . $HTMLFilePath;
    say "--- command line arguments ---\n\n";
}

# Traverses a directory and returns all the file paths
sub traverseDirectory
{

    # The @files array
    my $filesRef = shift;

    # Path of the working directory
    my $path = shift;

    # @files dereference
    my @files = @{$filesRef};

    say "Traversing Directory: " . $path if ($debug);

    # open the directory and grab the contents
    opendir( DIR, "$path" ) or die "Cannot open $path\n";
    my @thisdir = readdir(DIR);
    closedir(DIR);

    # loop over contents adding files to our array.
    foreach my $file (@thisdir)
    {
        if ( ( $file ne "." ) and ( $file ne ".." ) )
        {

            # we are a directory - now traverse it
            if ( -d "$path/$file" )
            {
                push( @files, "$path/$file" );
                @files = @{ traverseDirectory( \@files, "$path/$file" ) };
            }

            # we are a file
            elsif ( -f "$path/$file" )
            {
                push( @files, "$path/$file" );
            }
        }
    }

    return \@files;
}

sub chooseNewFileName
{

    my $path = shift;
    my $seed = shift;
    my $ext  = shift;

    # Add trailing slash if there isn't one
    if ( substr( $path, length($path) - 1, 1 ) ne '/' )
    {
        $path = $path . '/';
    }

    my $ret = 0;

    # Directory
    if ( -d $path )
    {
        my $num = "";
        $ret = $path . $seed . $num . '.' . $ext;
        while ( -e $ret )
        {
            if ( $num eq "" )
            {
                $num = -1;
            }
            $num = $num + 1;
            $ret = $path . $seed . $num . '.' . $ext;
        }
    }

    return $ret;
}

sub zipFile
{

    my $fileName    = shift;
    my $file        = shift;
    my $fileDaysOld = ( -M $file );
    my $fileSizeMB  = ( ( -s $file ) / 1024 / 1024 );
    my $compressed  = 0;

    # the file report that we return
    my %fileReport = ();

    print "Compressing File: $file" if ($debug);

    my $folder = substr( $file, 0, rindex( $file, '/' ) );
    my $dest   = chooseNewFileName( $folder, $fileName, "gz" );
    open( my $n, "<", $file );
    my $zipped = gzip $n => $dest;
    close($n);
    if ($zipped)
    {
        unlink($file);
        $compressed = 1;
        my $then = $fileDaysOld * 24 * 60 * 60;    #converting days to seconds
        my $now  = time;
        $then = $now - $then;
        utime( $now, $then, $dest );               #maintaining file modified date

        # Add times to our report
        $fileReport{'time'}         = $now;
        $fileReport{'modifiedTime'} = $then;
    }

    print " ==> $dest \n" if ($debug);

    # build our file report
    $fileReport{'compressed'} = $compressed;
    $fileReport{'fileSizeMB'} = $fileSizeMB;
    $fileReport{'filename'}   = $fileName;
    $fileReport{'path'}       = $folder;

    return \%fileReport;

}

sub buildHTML
{

    my $reportRef = shift;

    print "Building HTML " if ($debug);

    my $HTML = '';

    # If we don't pass in an email template then we'll use a generic one.
    if ( !$HTMLFilePath )
    {
        print "from generic template \n";
        $HTML = getGenericHTMLTemplate();
    }
    else
    {
        # read the .html file we passed in via --htmlFilePath
        print "from file template \n";
        $HTML = getHTMLFromFileSystem();
    }

    say "Injecting data into html" if ($debug);
    $HTML = injectDataIntoHTML( $HTML, $reportRef );

    return $HTML;
}

sub buildPlainText
{

    # I would like the build this out a little more and add the totals

    my $reportRef = shift;
    my %report    = %{$reportRef};

    # grab our file arrays
    my @deletedFiles       = @{ $report{deletedFiles} };
    my @deletedDirectories = @{ $report{deletedDirectories} };
    my @failed             = @{ $report{failed} };

    # grab the date & time
    my $date = DateTime->now( time_zone => "local" );
    my @time = split( 'T', $date );

    my $emailOut = "$date\r\n\r\nThese Files were deleted:\r\n";

    # Deleted Files
    foreach my $file (@deletedFiles)
    {
        $emailOut .= $file . "\r\n";
    }

    # Deleted Directories
    $emailOut .= "\r\n\r\nThese Folders were removed:\r\n";
    foreach my $dir (@deletedDirectories)
    {
        $emailOut .= $dir . "\r\n";
    }

    # failed
    $emailOut .= "\r\n\r\nThese Failed to get removed:\r\n";
    foreach my $file (@failed)
    {
        $emailOut .= $file . "\r\n";
    }
    $emailOut .= "\r\n\r\nFull Log here: \r\n$outputFile\r\n\r\n-MOBIUS Development Team-";

    return $emailOut;

}

# The default email template - when none is specified
sub getGenericHTMLTemplate
{

    my $HTML = <<EOSTR;
<!DOCTYPE html>
<html>
<head>
    <title>Deleted files from MOBIUS share</title>
    <link rel="icon" href="https://mobiusconsortium.org/sites/default/files/MOBIUS_Mark.jpg" type="image/jpeg"/>
    <style>

        /*MOBIUS Green #0099a8*/

        /*Dark Blue #002856*/

        /*Dark Grey #252525 */

        html, body {
            background-color: lightgrey;
            color: #252525;
        }

        .container {
            background-color: white;
            padding: 25px;
            width: 90%;
            margin: 50px auto;
            border: 1px solid darkgrey;
            border-radius: 5px;
            box-shadow: 5px 5px 5px darkgrey;
        }

        .logo {
            max-height: 50px;
            width: auto;
            text-align: right;
        }

        .title {
            font-size: 18pt;
            font-weight: bold;
            text-align: center;
            background-color: #0099a8;
            color: white;
            padding: 5px;
        }

        .time {
            text-align: right;
            font-size: 18px;
            font-weight: bold;
            color: #002856;
            margin: 0px 5px 0px 0px;
        }

        .section {
            border-bottom: 1px solid #d0d0d0;
            font-size: 15pt;
            margin-bottom: 11px;
            margin-top: 11px;
            text-align: center;
        }

        .text-center {
            text-align: center;
        }

        .text-bold {
            font-weight: bold;
        }

        .text-dark {
            color: #252525;
        }

        .item {
            font-size: 14px;
            font-family: arial;
            margin: 5px;
        }

        .report-time {
            margin-bottom: -20px;
        }

        .report-totals {
            text-align: center;
            background-color: lightgrey;
            padding: 5px;
        }

        .report-container {
            margin-top: 10px;
        }

        .no-data{
            text-align: center;

        }

    </style>
</head>
<body>
<div class="container">
    <img class="logo" src="https://mobiusconsortium.org/sites/default/files/site/MOBIUS-LINKING-HEADER-LOGO.png"
         alt="MOBIUS Logo"/>

    <p class="time">{{date}} - {{time}}</p>
    <div class="title">Old Files Removal Activity Log</div>

    <!-- report-container-start -->
    <div class="report-container">
        <h4 class="report-time" data-time="{{reportTimeEpoch}}">Run Time: {{reportTime}}</h4>
        <h2 class="report-totals">Files Deleted: {{totalFilesDeleted}} | Folders Deleted: {{totalFoldersDeleted}} |
            Failed: {{totalFailed}}</h2>
        <div class="files section text-bold text-dark">Files Deleted</div>
        <!-- files-start  -->
        {{deletedFiles}}
        <!-- files-end -->
        <div class="folders section text-bold text-dark">Folders Deleted</div>
        <!-- folders-start -->
        {{deletedFolders}}
        <!-- folders-end -->
        <div class="failed section text-bold text-dark">Failed</div>
        <!-- failed-start -->
        {{failed}}
        <!-- failed-end -->
    </div>
    <!-- report-container-end -->

    <!-- old-data-here -->

    <p class="text-center">Full Log here: {{outputFile}}</p>
    <p class="text-center text-bold text-dark">-MOBIUS Development Team-</p>
</div>
</body>
</html>
EOSTR

    return $HTML;

}

sub injectDataIntoHTML
{

    my $HTML      = shift;
    my $reportRef = shift;
    my %report    = %{$reportRef};

    # grab our file arrays
    my @deletedFiles       = @{ $report{deletedFiles} };
    my @deletedDirectories = @{ $report{deletedDirectories} };
    my @failed             = @{ $report{failed} };

    # grab the date & time
    my $date = DateTime->now( time_zone => "local" );
    my @time = split( 'T', $date );

    # start our regex replacements

    # date & time
    $HTML =~ s/\{\{date\}\}/$time[0]/g;
    $HTML =~ s/\{\{time\}\}/$time[1]/g;

    # report-container report time
    $HTML =~ s/\{\{reportTime\}\}/$time[0]  $time[1]/g;

    # set the data-attribute to an epoch time
    my $epoch = time();
    $HTML =~ s/\{\{reportTimeEpoch\}\}/$epoch/g;

    # Files Deleted
    my $deletedFilesHTML = '';
    $deletedFilesHTML = '<p class="no-data">NO DATA</p>' if ( @deletedFiles == 0 );
    foreach my $file (@deletedFiles)
    {
        $deletedFilesHTML .= "<div class=\"item\">$file</div>";
    }
    $HTML =~ s/\{\{deletedFiles\}\}/$deletedFilesHTML/g;
    my $totalDeletedFiles = $#deletedFiles + 1;
    $HTML =~ s/\{\{totalFilesDeleted\}\}/$totalDeletedFiles/g;

    # Folders/Directories Deleted
    my $deletedFoldersHTML = '';
    $deletedFoldersHTML = '<p class="no-data">NO DATA</p>' if ( @deletedDirectories == 0 );
    foreach my $dir (@deletedDirectories)
    {
        $deletedFoldersHTML .= "<div class=\"item\">$dir</div>";
    }

    $HTML =~ s/\{\{deletedFolders\}\}/$deletedFoldersHTML/g;
    my $totalDeletedDirectories = $#deletedDirectories + 1;
    $HTML =~ s/\{\{totalFoldersDeleted\}\}/$totalDeletedDirectories/g;

    # Failed to Delete
    my $failed = '';
    $failed = '<p class="no-data">NO DATA</p>' if ( @failed == 0 );
    foreach my $file (@failed)
    {
        $failed .= "<div class=\"item\">$file</div>";
    }

    $HTML =~ s/\{\{failed\}\}/$failed/g;
    my $totalFailed = $#failed + 1;
    $HTML =~ s/\{\{totalFailed\}\}/$totalFailed/g;

    # File report here
    $HTML =~ s/\{\{outputFile\}\}/$outputFile/g;

    if ($debug)
    {

        # say "----- injecting data divider -----";
        say "date: " . $time[0];
        say "time: " . $time[1];
        say "reportTimeEpoch: " . $epoch;
        say "deleted files: " . @deletedFiles;
        say "deleted directories: " . @deletedDirectories;
        say "failed to delete : " . @failed;
        say "report file: " . $outputFile;

    }

    return $HTML;
}

sub sendEmailReport
{

    my $emailPlainText = shift;
    my $emailHTML      = shift;

    my @toList = ($emailTo);
    my %conf   = ();

    my $email = new email( $emailFrom, \@toList, 0, 0, \%conf );

    # emailType -- 0 = Plain Text | 1 = HTML

    # Plain Text
    if ( $emailType == 0 )
    {
        $email->send( $emailSubject, $emailPlainText );
    }

    # HTML
    if ( $emailType == 1 )
    {
        $email->sendHTML( $emailSubject, $emailPlainText, $emailHTML );
    }

}

sub logReport
{

    my $HTML = shift;

    # Arrays for existing data
    my @existingDeletedFiles       = ();
    my @existingDeletedDirectories = ();
    my @existingFailed             = ();

    # report file exists
    if ( ( -e $outputFile ) )
    {

        my $HTMLFileData = '';

        my $reportContainerTrigger      = 0;
        my @reportContainerArray        = ();
        my @reportContainerArrayCLEANED = ();
        my $tmpReportContainer          = "";

        # extract all report-containers from our existing report file
        open( RF, "<", $outputFile );

        # load report file, loop over the report-containers and add the contents to our array
        while (<RF>)
        {

            my $line = $_;

            $reportContainerTrigger = 1 if ( index( $line, "<!-- report-container-start -->" ) != -1 );

            $tmpReportContainer .= $line if ($reportContainerTrigger);

            if ( index( $line, "<!-- report-container-end -->" ) != -1 )
            {
                $reportContainerTrigger = 0;
                push( @reportContainerArray, $tmpReportContainer );
                $tmpReportContainer = '';
            }

        }

        close(RF);

        # Iterate over the array and remove entries older than the specified date
        foreach my $reportContainerItem (@reportContainerArray)
        {

            if ( index( $reportContainerItem, "data-time" ) != -1 )
            {

                # check our times
                my $itemEpoch = $reportContainerItem;

                # extract the epoch time from the data-time html attribute
                $itemEpoch =~ s/^.*?data-time="(\d+)".*$/$1/sg;

                my $secondsInDay = ( 60 * 60 * 24 );
                my $maxEpochAge  = time() - ( $daysToDrop * $secondsInDay );

                if ( $itemEpoch > $maxEpochAge )
                {
                    push( @reportContainerArrayCLEANED, $reportContainerItem );
                }
                else
                {
                    if ($debug)
                    {

                        say "Removing: " . $reportContainerItem if ($debug);
                        say "daysToDrop: " . $daysToDrop;
                        say "itemEpoch: " . $itemEpoch;
                        say "time - (daysToDrop * secondsInDay): " . ( time() - ( $daysToDrop * $secondsInDay ) );
                        say "daysToDrop * secondsInDay: " .          ( $daysToDrop * $secondsInDay );
                        say "---------- next ----------";

                    }

                }

            }

        }

        #If there is more than 1 entry we get multiple report-container-end marks
        $HTML =~ s/<!-- old-data-here -->/@reportContainerArrayCLEANED \n <!-- old-data-here -->/sg;

    }

    # now save the file
    open( FH, ">", $outputFile );
    print FH $HTML;
    close(FH);

}

sub getHTMLFromFileSystem
{

    # open file
    open( FILE, '<', $HTMLFilePath ) or return getGenericHTMLTemplate();

    my $html = '';
    while (<FILE>)
    {
        print $_;
        $html .= $_;
    }

    close(FH);

    return $html;
}
