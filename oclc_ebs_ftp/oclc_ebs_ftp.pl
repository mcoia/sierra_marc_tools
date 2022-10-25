#!/usr/bin/perl

use lib qw(.);
use Data::Dumper;
use Getopt::Long;
use Text::CSV;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use edsService;

my $csvfile;
my $summaryemailaddress;
our $debug = 0;
my $noftp = 0;
my $nomovefiles = 0;
our $fromemailaddress;
my $emailsubject = "MOBIUS Weekly OCLC EBS Summary";
our @csvReadErrors = ();

our @csvSanityCheck =
(
    '^\d+\.[^\.]{3,7}.*$',  # filename (needs numeric followed by period, folloewd by 3-7 non-period characters
    '^.*?\/.*?\/.*$',  # local folder (require two slashes)
    '^.*?\.+.*$',  # ftp server (at least one period)
    '^.{2}.*$',  # ftp username (at least 2 characters)
    '^.{2}.*$',  # ftp password (at least 2 characters)
    '.*',  # ftp folder (anything)
    '^[^@]*?@[^\.]*?\..*$',  #emailsucces (emali address format please)
    '^.{2}.*$',  #Filename replacer
    '^.{2}.*$',  #Library Name (at least 2 characters)
    '^.*?\/.*?\/.*$',  #final destination (require two slashes)
);

GetOptions
(
    "csv=s" => \$csvfile,
    "summaryemailaddress=s" => \$summaryemailaddress,
    "emailsubject=s" => \$emailsubject,
    "fromemailaddress=s" => \$fromemailaddress,
    "debug" => \$debug,
    "noftp" => \$noftp,
    "nomovefiles" => \$nomovefiles
)
or printHelp();

if(!$csvfile || !$summaryemailaddress || !$emailsubject || !$fromemailaddress)
{
    printHelp();
}

my @edsObjects = @{readCSV($csvfile)};


# I think it's a good idea to figure out how many of these have
# the same email address, that way we're not sending multiple emails to the same email address
my %uniqueEmailSuccess = ();
my @errorPOS = ();

my $arpos = -1;
foreach(@edsObjects)
{
    $arpos++;
    undef $thisEDS; # in case there is bleed from loop to loop
    my $thisEDS = $_;
    print "$arpos : " . $thisEDS->getLibraryName() ."\n" if $debug;
    if($thisEDS->getRelatedFilesNum() > 0) # make sure there are files to process for any given object
    {
        print "Got files: " .$thisEDS->getLibraryName() ." ." . $thisEDS->getFilenameReplacer() . "\n" if $debug;
        print "Number: $arpos\n" if $debug;
        print Dumper($thisEDS) if $debug;
        $thisEDS->readFilesContents();
        push @errorPOS, $arpos if($thisEDS->getTotalErrors() != 0);
        next if($thisEDS->getTotalErrors() != 0); # next object if we had an error here
        $thisEDS->sendFTP() if !$noftp;
        push @errorPOS, $arpos if($thisEDS->getTotalErrors() != 0);
        next if($thisEDS->getTotalErrors() != 0); # next object if we had an error here

        my $thisEmail = $thisEDS->getEmailSuccess();
        my @ar = ();
        @ar = @{$uniqueEmailSuccess{$thisEmail}} if $uniqueEmailSuccess{$thisEmail};
        push @ar, $arpos;
        $uniqueEmailSuccess{$thisEmail} = \@ar;
        $thisEDS->moveFilesToArchive() if !$nomovefiles;
        push @errorPOS, $arpos if($thisEDS->getTotalErrors() != 0); # this is a non-fatal error, but we need to report it anyway
    }
}

# And now the summary email to the summaryemailaddress
my $summaryBody = boxText("Full Summary") . "\n";
# Loop through all of our successful processes per email address
while ((my $internal, my $mvalue ) = each(%uniqueEmailSuccess))
{
    my @thisGroup = ();
    my $bodyHeader = "The following EBS records were sent to OCLC this week:\n\n";
    my $bodyFooter = "\n\nThe ICODE1 code for the Adds has been updated to 0 and the Cancels to 200.";
    push @thisGroup, @edsObjects[$_] foreach(@{$mvalue});
    my $thisSubject = composeSubject(\@thisGroup);
    my $thisBody = composeBody(\@thisGroup);
    $summaryBody .= boxText($thisSubject) . "\n\n";
    $summaryBody .= "To: $internal\n";
    $summaryBody .= "\nBody:\n$bodyHeader $thisBody $bodyFooter\n";
    my @allEmailAddresses = split(/\s+/, $internal); # The CSV could specify more than one email address space delimited
    emailsend($thisSubject, $bodyHeader.$thisBody.$bodyFooter, @allEmailAddresses) if !$debug;
    emailsend($thisSubject, $bodyHeader.$thisBody.$bodyFooter, $summaryemailaddress) if $debug;
}

my $subjectErrorMessage = "Success";
if($#errorPOS > -1 || $#csvReadErrors > -1) # don't bother putting an error section if there were none
{
    $subjectErrorMessage = "SOME ERRORS";
    $summaryBody .= boxText("ERRORS",'!','!',7);
    if($#csvReadErrors > -1)
    {
        $summaryBody .= boxText("CSV File Issues");
        foreach(@csvReadErrors)
        {
            $summaryBody .= $_."\n";
        }
    }
    if($#errorPOS > -1)
    {
        $summaryBody .= boxText("Data File Issues");
        foreach(@errorPOS)
        {
            my $thisEDS = @edsObjects[$_];
            my @thisErrors = @{$thisEDS->getErrors()};
            $summaryBody .= boxText($thisEDS->getLibraryName());
            foreach(@thisErrors)
            {
                $summaryBody .= $_ ."\n";
            }
            undef $thisEDS;
        }
    }
}


emailsend($emailsubject . " - [$subjectErrorMessage] Admin Complete Summary", $summaryBody, $summaryemailaddress);

sub composeSubject
{
    my $groupRef = shift;
    my @group = @{$groupRef};
    my $libNames = "";
    my $libTotal = 0;
    my $fileTotal = 0;
    my $recordTotal = 0;
    foreach(@group)
    {
        if($_->getTotalRecords() > 0)
        {
            $libNames .= $_->getLibraryName() .", ";
            $libTotal++;
            $fileTotal += $_->getRelatedFilesNum();
            $recordTotal += $_->getTotalRecords();
        }
    }
    $libNames = substr($libNames, 0, -2); #chop off the last comma

    return $emailsubject . " - libraries: $libNames $fileTotal file(s) and $recordTotal record(s)";
}

sub composeBody
{
    my $groupRef = shift;
    my @group = @{$groupRef};
    my $ret = "";
    foreach(@group)
    {
        if($_->getTotalRecords() > 0)
        {
            $ret .= $_->getEmailBlurb();
        }
    }
    return $ret;
}

sub emailsend  	#subject, body
{
    my ($subject, $body, @to) = @_;

    @to = @{_deDupeEmailArray(\@to)};

    my $message = Email::MIME->create(
        header_str => [
            From    => $fromemailaddress,
            To      => [ @to ],
            Subject => $subject
        ],
        attributes => {
            encoding => 'quoted-printable',
            charset  => 'ISO-8859-1',
        },
        body_str => "$body\n"
    );

    sendmail($message);
}

sub _deDupeEmailArray
{
    my $emailArrayRef = shift;
    my @emailArray    = @{$emailArrayRef};
    my %posTracker    = ();
    my %bareEmails    = ();
    my $pos           = 0;
    my @ret           = ();

    foreach (@emailArray)
    {
        my $thisEmail = $_;

        print "processing: '$thisEmail'\n" if $debug;

        # if the email address is expressed with a display name,
        # strip it to just the email address
        $thisEmail =~ s/^[^<]*<([^>]*)>$/$1/g if ( $thisEmail =~ m/</ );

        # lowercase it
        $thisEmail = lc $thisEmail;

        # Trim the spaces
        $thisEmail = _trim($thisEmail);

        print "normalized: '$thisEmail'\n" if $debug;

        $bareEmails{$thisEmail} = 1;
        if ( !$posTracker{$thisEmail} )
        {
            my @a = ();
            $posTracker{$thisEmail} = \@a;
            print "adding: '$thisEmail'\n" if $debug;
        }
        else
        {
            print "deduped: '$thisEmail'\n" if $debug;
        }
        push( @{ $posTracker{$thisEmail} }, $pos );
        $pos++;
    }
    while ( ( my $email, my $value ) = each(%bareEmails) )
    {
        my @a = @{ $posTracker{$email} };

        # just take the first occurance of the duplicate email
        push( @ret, @emailArray[ @a[0] ] );
    }

    return \@ret;
}

sub readCSV
{
    my $csvfile = shift;
    my @edsObjects = ();
    # Read/parse CSV
    print "reading CSV: $csvfile\n" if $debug;
    my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1 });
    open my $fh, "<:encoding(utf8)", $csvfile or die "Error opening $csvfile $!";

    # Skip header line
    $csv->getline ($fh);

    my $linenum = 2; # 1-based Starting on second line because we skipped the header

    while (my $row = $csv->getline ($fh))
    {
        my @ar = @{$row};
        my $error = checkCSVLine(\@ar);
        if($error == 1)
        {
            push @edsObjects, new edsService(@ar);
        }
        else
        {
            push @csvReadErrors, "Line $linenum : $error";
        }
        $linenum++;
    }
    close $fh;
    return \@edsObjects;
}

sub checkCSVLine
{
    my $row = shift;
    my @ar = @{$row};
    return "Incorrect number of columns" if($#ar != $#csvSanityCheck);
    for my $pos(0..$#ar)
    {
        my $check = @csvSanityCheck[$pos];
        if( !(@ar[$pos] =~ m/$check/))
        {
            return "CSV column number $pos did not pass the sanity check";
        }
        $pos++;
    }
    return 1;
}

sub boxText
{
    my $text = shift;
    my $hChar = shift || '#';
    my $vChar = shift || '|';
    my $padding = shift || 2;
    my $ret = "";
    my $longest = 0;
    my @lines = split(/\n/,$text);
    length($_) > $longest ? $longest = length($_) : '' foreach(@lines);
    my $totalLength = $longest + (length($vChar)*2) + ($padding *2) + 2;
    my $heightPadding = ($padding / 2 < 1) ? 1 : $padding / 2;

    # Draw the first line
    my $i = 0;
    while($i < $totalLength)
    {
        $ret.=$hChar;
        $i++;
    }
    $ret.="\n";
    # Pad down to the data line
    $i = 0;
    while( $i < $heightPadding )
    {
        $ret.="$vChar";
        my $j = length($vChar);
        while( $j < ($totalLength - (length($vChar))) )
        {
            $ret.=" ";
            $j++;
        }
        $ret.="$vChar\n";
        $i++;
    }

    foreach(@lines)
    {
        # data line
        $ret.="$vChar";
        $i = -1;
        while($i < $padding )
        {
            $ret.=" ";
            $i++;
        }
        $ret.=$_;
        $i = length($_);
        while($i < $longest)
        {
            $ret.=" ";
            $i++;
        }
        $i = -1;
        while($i < $padding )
        {
            $ret.=" ";
            $i++;
        }
        $ret.="$vChar\n";
    }
    # Pad down to the last
    $i = 0;
    while( $i < $heightPadding )
    {
        $ret.="$vChar";
        my $j = length($vChar);
        while( $j < ($totalLength - (length($vChar))) )
        {
            $ret.=" ";
            $j++;
        }
        $ret.="$vChar\n";
        $i++;
    }
     # Draw the last line
    $i = 0;
    while($i < $totalLength)
    {
        $ret.=$hChar;
        $i++;
    }
    $ret.="\n";
    return $ret;
}

sub printHelp
{
    print "
Please give me the path to the CSV file and a global email address

    --csv [required, path to the csv]
    --summaryemailaddress [required, where to send the summary message email address]
    --emailsubject [required, provide a quoted string for the prepended subject line]
    --fromemailaddress [required, provide the 'from' email address to forge the message from]
    --debug [not required, flag, causes the emails to only go to the 'summaryemailaddress']
    --noftp [not required, flag, causes the software to skip the FTP portion]
    --nomovefiles [not required, flag, causes the software to leave the files where they are]
";
    exit;
}