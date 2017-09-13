#!/usr/bin/perl


use lib qw(../); 
use Loghandler;
use Mobiusutil;
use Data::Dumper;
use MARC::Record;
use MARC::File;
use File::Path qw(make_path remove_tree);
use File::Copy;
 
my $dirRoot = @ARGV[0];
if(!$dirRoot)
{
    print "Please specify a directory root \n";
    exit;
}

our $pidfile = "/tmp/marc_processing.pl.pid";

if (-e $pidfile)
{
    #Check the processes and see if there is a copy running:
    my $thisScriptName = $0;
    my $numberOfNonMeProcesses = scalar grep /$thisScriptName/, (split /\n/, `ps -aef`);
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

my $writePid = new Loghandler($pidfile);
$writePid->addLine("running");
undef $writePid;

while(1)
{

    my @files;
    @files = @{dirtrav(\@files, $dirRoot)};
    my %functionMaps = (
    'EWL YBP DDA' => 'EWL_YBP_DDA',
    );

    foreach(@files)
    {
        my $file = $_;
        my $path;
        my $finalpath;
        my $baseFileName;
        my $fExtension;
        my $originalFileName;
        my $processedFileName;
        my @sp = split('/',$file);
       
       
        $path=substr($file,0,( (length(@sp[$#sp]))*-1) );
    #print "lastE = ".@sp[$#sp]."\n";
        my @fsp = split('\.',@sp[$#sp]);
        $fExtension = pop @fsp;
        $baseFileName = join('.', @fsp);
        $finalpath = $path."/marc_done_processing";
        
        if( !($path =~ m/marc_done_processing/) && ($fExtension =~ 'mrc'))
        {
            # Make sure we have a function for this directory
            my $functionCall;
            while (my ($key, $value) = each %functionMaps)
            {
                $functionCall = $value if($path =~ m/$key/);
            }
            if($functionCall)
            {
                $functionCall = "\$finalmarc = $functionCall(\$marc);";
                # ensure that our final directory exists
                ensureFinalFolderExists($finalpath);
                $originalFileName = $baseFileName."_org.".$fExtension;
                $processingFileName = $baseFileName.".processing";
                $processedFileName = $baseFileName."_processed.".$fExtension;
print "path = $path  Base = $baseFileName  Orgname = $originalFileName  ProcessingFN = $processingFileName  Processed = $processedFileName\n";
                checkFileReady($file);
                # move($file,$path.$processingFileName);
                moveFile($file,$path.$processingFileName);
                my $marcfile = MARC::File::USMARC->in($path.$processingFileName);
                my $writeOut = '';
                while ( my $marc = $marcfile->next() )
                {
                    my $finalmarc;
                    eval ($functionCall);
                    $writeOut.=$finalmarc->as_usmarc();
                }
                
                my $doneFH = new Loghandler($finalpath.'/'.$processedFileName);
                $doneFH->appendLineRaw($writeOut);
                undef $doneFH;
                moveFile($path.$processingFileName,$finalpath.'/'.$originalFileName);
            }
        }
    }    
    sleep 5;
}

sub moveFile
{
    my $file = @_[0];
    my $destination = @_[1];
#print "Moving file from $file to $destination\n";
    
    my $fhandle = new Loghandler($file);
    
    if( $fhandle->copyFile($destination) )
    {
        if(! (unlink($file)) )
        {
            print "Unable to delete $file";
            exit;
        }
    }
    undef $fhandle;
}

sub EWL_YBP_DDA
{
    my $marc = @_[0];
#print "Received marc:\n";
#print $marc->as_formatted();
    my $z001 = $marc->field('001');
    $z001->update("ewlebc".$z001->data());
#print "After z001->update\n";
    my $two45 = $marc->field('245');
    $two45->update( 'h' => "[electronic resource]" );
#print "After two45->update\n";
    my $field655 = MARC::Field->new( '655',' ','0', a => 'Electronic books' );
    $marc->insert_grouped_field( $field655 );
#print "After marc->insert_grouped_field\n";
    my $field949 = MARC::Field->new( '949',' ','1', c => '1', h => '090',i=>'wwcii', o => '-', r => '-', s => '-', t => '019', u => '-' );
    $marc->insert_grouped_field( $field949 );
#print "After marc->insert_grouped_field field949\n";
    $marc = prefix856u($marc,"http://library3.webster.edu/login?url=");
#print "After marc->insert_grouped_field field949\n";
    $marc = change856z($marc,"Webster-Eden: Click here to access this online book");
#print $marc->as_formatted();
    return $marc;
}

sub manipulate_another_project
{
    my $marc = @_[0];
    
    return $marc;
}   
    
sub prefix856u
{
    my $marc = @_[0];
    my $prefix = @_[1];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;
        $thisfield->update('u' => $prefix.$thisfield->subfield('u') );
    }
    return $marc;
}

sub change856z
{
    my $marc = @_[0];
    my $subz = @_[1];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;
        $thisfield->update('z' => $subz );
    }
    return $marc;
}

sub checkFileReady
{
    my $file = @_[0];
    my $worked = open (inputfile, '< '. $file);
    my $trys=0;
    if(!$worked)
    {
        print "******************$file not ready *************\n";
    }
    while (!(open (inputfile, '< '. $file)) && $trys<100)
    {
        print "Trying again attempt $trys\n";
        $trys++;
        sleep(1);
    }
    close(inputfile);
}

sub ensureFinalFolderExists
{

    my $path = shift;
    if ( !(-d $path) )
    {
# print "Creating directory: $path\n";
        make_path($path, {
        verbose => 1,
        mode => 0711,
        });
    }
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

sub DESTROY
{
    print "I'm dying, deleting PID file $pidFile\n";
    unlink $pidFile;
}

exit;
