#!/usr/bin/perl
#
# Usage:
# ./zipbigfiles.pl <absolute path> <path to log html file> <Age to compress (in days)> <Age to Delete (in days)> <email notification address>
#
use lib qw(../);
use email;
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use File::stat;
use Time::localtime;
use DateTime;
use Loghandler;
use IO::Compress::Gzip qw(gzip $GzipError);
use Getopt::Long;

my $printHelp;
my $path;
my $outputFile;
my $ageToCompress;
my $ageToDelete;
my $toemail;

my $help = "Usage: zipbigfiles.pl [OPTION]...
gZip files in the specified directory of a certain age while removing files of a certain age.

Mandatory arguments
--path              Path to files that will be gzipped.
--outputFile        Name of the html report file.
--ageToCompress     Number of days old the file has to be before it is skipped & not gzipped.
--ageToDelete       Number of days old the file has to be before it is deleted.
--email             Email address to send the final report to.
";

GetOptions(
    "help"             => \$printHelp,
    "path=s"           => \$path,
    "outputFile=s"     => \$outputFile,
    "daysToCompress=i" => \$ageToCompress,
    "daysToDelete=i"   => \$ageToDelete,
    "email=s"          => \$toemail
);

if ($printHelp)
{
    print $help;
    exit 1;
}

#setup test directory tree /tmp/run/test
#setup($outputFile);

my @files;

#Get all files in the directory path
@files = @{dirtrav(\@files, $path)};

#print Dumper(\@files);

my @rmfiles;
my @rmdirs;
my @failed;
my $somethingChanged = 0;
if (1)
{
    for my $i (0 .. $#files)
    {
        my $thisFile = @files[$i];
        my $thisFileName = substr($thisFile, rindex($thisFile, '/') + 1);
        my $diff = -M @files[$i];
        my $size = -s @files[$i];
        my $fileExtension = substr($thisFile, rindex($thisFile, '.') + 1);
        my $compressed = 0;
        if ($diff > $ageToCompress && !(-d $thisFile))
        {
            if (($fileExtension ne "zip") && ($fileExtension ne "gz"))
            {

                #print "Flagged for compression: $thisFile age $diff\n";
                my $mobutil = new Mobiusutil();
                my $folder = substr($thisFile, 0, rindex(@files[$i], '/'));
                my $dest =
                    $mobutil->chooseNewFileName($folder, $thisFileName, "gz");
                open($n, "<", $thisFile);
                my $zipped = gzip $n => $dest;
                close($n);
                if ($zipped)
                {
                    unlink(@files[$i]);
                    $compressed = 1;
                    my $then = $diff * 24 * 60 * 60; #converting days to seconds
                    my $now = time;
                    $then = $now - $then;
                    utime($now, $then, $dest); #maintaining file modified date
                }
            }
        }

        if (!$compressed)
        {
            if ($diff > $ageToDelete)
            {
                if (-d @files[$i])
                {

                    #print "Removing Directory: @files[$i]\n";
                    #check to see if the dir is empty
                    opendir(DIR, @files[$i])
                        or die "Cannot open @files[$i]\n";
                    my @thisdir = readdir(DIR);
                    closedir(DIR);

                    #print "Directory about to be deleted has this inside\n";
                    #print Dumper(@thisdir);
                    if ($#thisdir < 2)
                    {
                        $somethingChanged = 1;
                        push(@rmdirs, @files[$i]);
                        my $worked = rmdir(@files[$i]);
                        if (!$worked)
                        {

                            #print "Failed to delete @files[$i]\n";
                            push(@failed, @files[$i]);
                        }
                    }
                }
                else
                {
                    push(@rmfiles, $thisFile);
                    $somethingChanged = 1;

                    #print "Deleting file $thisFile\n";
                    my $worked = unlink($thisFile);
                    if (!$worked)
                    {
                        push(@failed, @files[$i]);
                    }
                }
            }
        }
    }
    if ($somethingChanged)
    {
        my $date = DateTime->now(time_zone => "local");
        my @s = split('T', $date);
        my $emailOut = "$date\r\n\r\nThese Files were deleted:\r\n";
        my $htmlOut =
            '<div class="job"><div class="jobheader">'
                . @s[0]
                . '   -  '
                . @s[1]
                . '</div><div class="section">Files Deleted</div>';
        foreach my $i (0 .. $#rmfiles)
        {
            $emailOut .= @rmfiles[$i] . "\r\n";
            $htmlOut .= '<div class="sectionline">' . @rmfiles[$i] . '</div>';
        }

        $emailOut .= "\r\n\r\nThese Folders were removed:\r\n";
        $htmlOut .= '<div class="section">Folders Deleted</div>';
        foreach my $i (0 .. $#rmdirs)
        {
            $emailOut .= @rmdirs[$i] . "\r\n";
            $htmlOut .= '<div class="sectionline">' . @rmdirs[$i] . '</div>';
        }
        $emailOut .= "\r\n\r\nThese Failed to get removed:\r\n";
        $htmlOut .= '<div class="section">Failed</div>';
        foreach my $i (0 .. $#failed)
        {
            $emailOut .= @failed[$i] . "\r\n";
            $htmlOut .= '<div class="sectionline">' . @failed[$i] . '</div>';
        }
        $htmlOut .= "</div>";
        $emailOut .=
            "\r\n\r\nFull Log here: \r\n$outputFile\r\n\r\n-MOBIUS Perl Squad-";
        my @tolist = ($toemail);
        my %conf = ();
        my $email =
            new email("dropbox\@mobiusconsortium.org", \@tolist, 0, 0, \%conf);
        $email->send("Old File Deletion Report", $emailOut);

        my $htmlLog = new Loghandler($outputFile);
        my @lines = @{$htmlLog->readFile()};
        my $orgHTML = "";
        foreach (@lines)
        {
            $orgHTML .= $_;
        }
        my $body = substr($orgHTML, index($orgHTML, '</div>') + 6);

        $htmlOut .= $body;
        $htmlOut = getHTMLHead() . $htmlOut;
        $htmlLog->truncFile($htmlOut);

    }
}

exit;

sub setup
{
    my $outputfile = shift;
    my @files = (
        "/tmp/run/test/one/test.one",
        "/tmp/run/test/two/test.two",
        "/tmp/run/test/two/lair2/test.three",
        "/tmp/run/test/two/lair2/test.three",
        "/tmp/run/test/two/lair2/lair3/test.four",
        "/tmp/run/test/two/lair2/lair3/lair4/test.5",
        "/tmp/run/test/two/lair2/test.6"
    );
    for my $i (0 .. $#files)
    {
        my $this = @files[$i];

        #print "Reading $this\n";
        my $path = substr($this, 0, rindex($this, '/'));
        make_path(
            $path,
            {
                verbose => 1,
                mode    => 0711,
            }
        );

        #print "Path: $path\n";
        my $old = int(rand(2));
        my $then = time;
        my $now = time;
        if ($old)
        {
            $then -= 31537000; #number of seconds in a year
            print "Making this old: $this\n";
        }
        open(OUTPUT, ">>$this");
        my $dataChunk = getFakeData(1000);
        for my $b (0 .. 100)
        {
            print OUTPUT "$dataChunk\n";
        }
        close(OUTPUT);
        utime($now, $then, $this);

    }

    my @dirs = (
        "/tmp/run/test/done",
        "/tmp/run/test/dtwo",
        "/tmp/run/test/dtwo/dlair2",
        "/tmp/run/test/dtwo/dlair2",
        "/tmp/run/test/dtwo/dlair2/dlair3",
        "/tmp/run/test/dtwo/dlair2/dlair3/dlair4",
        "/tmp/run/test/dtwo/dlair2"
    );
    for my $i (0 .. $#dirs)
    {
        my $this = @dirs[$i];
        make_path(
            $this,
            {
                verbose => 1,
                mode    => 0711,
            }
        );

        #print "Path: $path\n";
        my $old = int(rand(2));
        my $then = time;
        my $now = time;
        if ($old)
        {
            $then -= 31537000; #number of seconds in a year
            print "Making this old: $this\n";
        }
        utime($now, $then, $this);
    }

    #my $htmlStart = getHTMLHead();
    #open(OUTPUT, '> '.$outputfile);
    #binmode(OUTPUT, ":utf8");
    #print OUTPUT "$htmlStart";
    #close(OUTPUT);

}

sub getFakeData
{
    my $howmany = @_[0];
    my $ret = "";
    for my $i (0 .. $howmany)
    {
        my $value = rand(2);
        $ret .= "" . $value;
    }

    return $ret;
}

sub getHTMLHead
{
    my $style = '
    <style>
        .allhead
        {
            font-size: 27pt;
            font-weight: bold;
            margin: 47px;
        }
        .job
        {
            border-bottom: 2px solid black;
            padding: 10px;
        }
        .jobheader
        {
            color: darkviolet;
            font-size: 22pt;
            font-weight: bold;
            letter-spacing: 2px;
            margin-left: 20px;
        }
        .section
        {
            border-bottom: 1px solid black;
            font-size: 15pt;
            margin-bottom: 11px;
            margin-top: 11px;
            text-align: center;
            width: 151px;
        }
        .sectionline
        {
            font-size: 10pt;
            margin-left: 17px;
        }
    </style>';

    my $htmlStart =
        '<html><head><title>Deleted files from MOBIUS share</title>'
            . $style
            . '</head><body><div class="allhead">Old Files Removal Activity Log</div>'
            . "\n";
    return $htmlStart;
}

sub dirtrav
{
    my @files = @{@_[0]};
    my $pwd = @_[1];
    opendir(DIR, "$pwd") or die "Cannot open $pwd\n";
    my @thisdir = readdir(DIR);
    closedir(DIR);
    foreach my $file (@thisdir)
    {
        if (($file ne ".") and ($file ne ".."))
        {
            if (-d "$pwd/$file")
            {
                push(@files, "$pwd/$file");
                @files = @{dirtrav(\@files, "$pwd/$file")};
            }
            elsif (-f "$pwd/$file")
            {
                push(@files, "$pwd/$file");
            }
        }
    }
    return \@files;
}
