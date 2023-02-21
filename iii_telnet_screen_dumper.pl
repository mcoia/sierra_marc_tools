#!/usr/bin/perl

# You need to install a few perl modules for this script to work:
# DateTime::Format::Duration
# Expect
# Text::CSV
# Email::MIME
# Data::Dumper
# Email::Sender::Simple
# Email::Stuffer

# TODO:
# You need to customize the login/host/pass variables below
# You also need to update all of the email addresses at the bottom of the script
# Look for these lines:

# my @tolist = ("email0\@none.org");
# my %conf = (
# "successemaillist" => "email1\@none.org, email2\@none.com, email3\@none.com",
# "erroremaillist" => "email5\@none.org",
# );
# my $email = new email("Friendly MOBIUS Server <noreply\@none.org>",\@tolist,0,1,\%conf);


use lib qw(./);
use Loghandler;
use DateTime;
use DateTime::Format::Duration;
use Data::Dumper;
use Expect;
use email;
use Text::CSV (csv);


our @finalOutput = ();
our %finalNums = ();
my $login = 'SSHLOGIN';
my $host = 'HOSTNAME';
my $pass = 'SSHPASSWORD';
my $timeout = 5;

my $log = new Loghandler("log.log");

$log->truncFile("");

my $connectVar = "ssh $login\@$host";

my $exp = new Expect;
$exp->debug(0);
$exp->raw_pty(0);
$exp->spawn($connectVar);

# handle public key accept
if ($exp->expect($timeout, "yes/no"))
{
    print $exp "yes\r";
}

unless($exp->expect($timeout, "password") )
{
    die print "No Password Prompt";
}

print $exp "$pass\r";

unless($exp->expect($timeout, "MANAGEMENT") )
{
    die print "No MANAGEMENT Prompt";
}

print $exp "m";

unless($exp->expect($timeout, "MONITOR MOBIUS") )
{
    die print "No MONITOR MOBIUS Prompt";
}

print $exp "m";

unless($exp->expect($timeout, "Choose one") )
{
    die print "No Choose one Prompt";
}

$exp->before();

print $exp "l";

unless($exp->expect($timeout, "ess <SPACE> to contin") )
{
    die print "No ess <SPACE> to contin Prompt";
}

processLast24HoursScreen($exp->before());

# this code is to collect the big dataset, but I think we're going with
# "Last 24 hours"
# my $thisScreen = $exp->before();
# my $moreData = processQueueScreen($thisScreen);

# while($moreData && $thisScreen =~ /> FORWARD/)
# {
    # print $exp "f";
    # unless($exp->expect($timeout, "Choose one") )
    # {
        # die print "No Choose one Prompt";
    # }
    # $moreData = processQueueScreen($exp->before());
# }


# move through the menu and disconnect
print $exp " ";

unless($exp->expect($timeout, "Choose one") )
{
    die print "No  Choose one Prompt";
}

print $exp "q";

unless($exp->expect($timeout, "Choose one (I,A,L") )
{
    die print "No  Choose one (I,A,L Prompt";
}

print $exp "q";

unless($exp->expect($timeout, "Choose one (S,M") )
{
    die print "No  Choose one (S,M Prompt";
}

print $exp "x";

# if no longer needed, do a soft_close to nicely shut down the command
$exp->soft_close();
 
# or be less patient with
$exp->hard_close();
$log->addLine(Dumper(\@finalOutput));

my $dt      = DateTime->now( time_zone => "local" );
my $fdate   = $dt->ymd;

my $csvfile = createCSVOutput(chooseNewFileName("./", "innreach_queue_$fdate", "csv"));

my @tolist = ("email0\@none.org");
my %conf = (
"successemaillist" => "email1\@none.org, email2\@none.com, email3\@none.com",
"erroremaillist" => "email5\@none.org",
);

my $email = new email("Friendly MOBIUS Server <noreply\@none.org>",\@tolist,0,1,\%conf);
my @attachments = ($csvfile);
$email->sendWithAttachments("III INNReach Utility - Daily Queue Report","All,\r\n\r\nPlease find the attached queue report\r\n\r\n-MOBIUS Perl Squad-",\@attachments);
unlink $csvfile;


sub createCSVOutput
{
    my $outFile = shift;
    
    # and write as CSV
    print "\nExporting final ./$outFile file\n";
    open $fh, ">:encoding(utf8)", $outFile or die "$outFile: $!";
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
    $csv->say($fh, $_) for @finalOutput;
    close $fh or die "$outFile: $!";
    return $outFile;
}

sub processLast24HoursScreen
{
    $log->addLine("***********************************");
    my $raw = shift;
    $log->addLine($raw);
    my $out = '';
    my @lines = split(/[\n\r]/,$raw);
    my $foundData = 0;
    my @data = ();
    my $loopNum = 0;
    foreach(@lines)
    {
        $log->addLine($_);
        # attempting to get the header row to make our CSV nicer to read
        if($loopNum == 0)
        {
            my @s = split(/\sTime/, $_);
            if(@s[1] && @s[1] =~ /Group/)
            {
                my @headerTemp = split(/\s+/, trim(@s[1]));
                my @secRow = split(/\s+/, trim(@s[2]));
                push (@headerTemp, "Time");
                push (@headerTemp, @secRow);

                my @header = ("ExtractDate", "Time");
                for my $i (0..10) # hardcoded number of header columns
                {
                    push (@header, @headerTemp[$i]);
                }
                push (@data, \@header);
            }
        }
        else
        {
            $foundData = 1 if($_ =~ /---------------/);
            $foundData = 0 if($_ =~ /Press <SPACE> to/);
            if($foundData)
            {
                push(@data, $_);
            }
        }
        $loopNum++;
    }
    $log->addLine(Dumper(\@data));
    my $i = 0;
    foreach(@data)
    {
        if(ref $_ eq 'ARRAY')
        {
            # this is the header row, as is
            push(@finalOutput, $_);
        }
        else
        {
            my $st = @data[$i];
            $st =~ s/^[^;]*?;[^H]*H\*?\s?(.*)$/\1/;
            $st =~ s/[^\d]*$//;
            $st =~ s/[^\s]*\s/\s/g;
            @data[$i] = $st;
            my @caps = split(/\s+/, $st);
            if($#caps > 5)
            {
                my @withDate = ();
                my $dt      = DateTime->now( time_zone => "local" );
                my $fdate   = $dt->ymd;
                push (@withDate, "'" .$fdate . "'"  );
                push(@withDate, "'" . $_ . "'" ) foreach(@caps);
                push(@finalOutput, \@withDate);
            }
        }
        $i++;
    }

}

sub processQueueScreen
{
    $log->addLine("***********************************");
    my $raw = shift;
    $log->addLine($raw);
    my $out = '';
    my @lines = split(/\[/,$raw);
    my $foundData = 0;
    my @data = ();
    foreach(@lines)
    {
        $foundData = 1 if($_ =~ />/);
        $foundData = 0 if($_ =~ /qqqqq/);
        if($foundData)
        {
            if($_ =~ />/)
            {
                push(@data, $_);
            }
            else
            {
                @data[$#data] .= $_;
            }
        }
    }
    my $i = 0;
    my @thisSet = ();
    foreach(@data)
    {
        my $st = @data[$i];
        $st =~ s/^[^;]*?;[^H]*H\*?\s?(.*)$/\1/;
        $st =~ s/[^\d]*$//;
        $st =~ s/[^\s]*\s/\s/g;
        @data[$i] = $st;
        if($st =~/^\d/)
        {
            push (@thisSet, $st);
            # my @caps = $st =~ /^(\d+)\s*>\s*([^\s]+)\s*([^\s]+)\s+([^\s]+)\s*([^\-]+)\-([^\s]+)\s+([^:]*):([^\s]+)\s+([^\-]+)\-([^\s]+)\s*([^:]*):([^\s]*)\s*.*/x;
            my @caps = split(/\s+/, $st);
            push(@thisSet, \@caps);
        }
        $i++;
    }
    return mergeNewDataIntoFinal(\@thisSet);
}

# returns boolean, whether or not there was new data to merge
sub mergeNewDataIntoFinal
{
    my $ret = 0;
    my $incoming = shift;
    my @inc = @{$incoming};
    my @adds = ();
    foreach(@inc)
    {
        my @fRow = @{$_};
        my $findingNum = @fRow[0];
        if(!$finalNums{$findingNum})
        {
            $finalNums{$findingNum} = 1;
            push @finalOutput, \@fRow;
            $ret = 1;
        }
    }
    return $ret;
}

sub chooseNewFileName  
{

    my $path = shift;
    my $seed = shift;
    my $ext = shift;
# Add trailing slash if there isn't one
    if(substr($path,length($path)-1,1) ne '/')
    {
        $path = $path.'/';
    }
    my $ret="";
    if( -d $path)
    {
        my $num="";
        $ret = $path . $seed . $num . '.' . $ext;
        while(-e $ret)
        {
            if($num eq "")
            {
                $num=-1;
            }
            $num = $num+1;
            $ret = $path . $seed . $num . '.' . $ext;
        }
    }
    else
    {
        $ret = 0;
    }

    return $ret;
}

sub trim {
    my $string = shift;
    $string =~ s/^[\s\n\r]+//;
    $string =~ s/[\s\n\r]+$//;
    return $string;
}

exit;
 
 