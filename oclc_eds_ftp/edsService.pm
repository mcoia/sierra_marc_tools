package edsService;

use Data::Dumper;
use MARC::Record;
use MARC::File;
use MARC::File::USMARC;
use File::Copy;

sub new
{
    my ($class, @args) = @_;
    my ($self, $args) = _init($class, \@args);
    bless $self, $class;
    return $self;
}

sub _init
{
    my $self = shift;
    my $args = shift;
    my @args = @{$args};
    my @errors = ();
    $self =
    {
        filename => shift @args,
        localfolder => shift @args,
        ftpserver => shift @args,
        ftpuser => shift @args,
        ftppass => shift @args,
        ftpfolder => shift @args,
        emailsuccess => shift @args,
        filenamereplacer => shift @args,
        libraryname => shift @args,
        subjectfail => shift @args,
        finaldest => shift @args,
        errors => \@errors,
        totalerrors => 0,
        totalrecords => 0
    };
    retrieveRelatedFiles($self);
    return ($self, \@args);
}

sub getFileName
{
    my $self = shift;
    return $self->{filename};
}

sub getRelatedFilesNum
{
    my $self = shift;
    return $self->{relatedfilesnum};
}

sub getLibraryName
{
    my $self = shift;
    return $self->{libraryname};
}

sub getFinalDest
{
    my $self = shift;
    return $self->{finaldest};
}

sub getEmailSuccess
{
    my $self = shift;
    return $self->{emailsuccess};
}

sub getFilenameReplacer
{
    my $self = shift;
    return $self->{filenamereplacer};
}

sub getTotalRecords
{
    my $self = shift;
    return $self->{totalrecords};
}

sub getEmailBlurb
{
    my $ret = "";
    while ((my $internal, my $mvalue ) = each(%{$self->{filestats}}))
    {
        $ret .= $self->{filenamereplacer} . " $mvalue records\r\n";
    }
    return $ret;
}

sub readFilesContents
{
    my $self = shift;
    my %fileStats = ();
    my $totalRecords = 0;
    foreach(@{$self->{relatedfiles}})
    {
        my $marcfile = $_;
        my $bareFilename = getFileNameWithoutPath($self, $marcfile);
        my $file;
        $file = MARC::File::USMARC->in($marcfile);
        local $@;
        eval
        {
            my $recordCount = 0;
            $recordCount++ while ( $file->next() );
            # finally, the juicy stats
            $fileStats{$bareFilename} = $recordCount;
            $totalRecords += $recordCount;
            1;  # ok
        } or do
        {
            $file->close();
            addError($self, "Couldn't read MARC file: $marcfile");
        };
        $file->close();
        undef $file;
    }
    $self->{filestats} = \%fileStats;
    $self->{totalrecords} = \%totalRecords;
}

sub getTotalErrors
{
    my $self = shift;
    return $self->{totalerrors};
}

sub getErrors
{
    my $self = shift;
    return $self->{errors};
}

sub retrieveRelatedFiles
{
    my $self = shift;
    my @files = ();
    @files = @{dirtrav($self, \@files, $self->{localfolder})};
    my @finalList = ();
    foreach(@files)
    {
        my $filename = $_;
        $filename = getFileNameWithoutPath($self, $filename);
        push @finalList, $_ if($filename =~ /$self->{filename}/);
    }
    $self->{relatedfiles} = \@finalList;
    $self->{relatedfilesnum} = ($#finalList + 1);
}

sub getFileNameWithoutPath
{
    my $self = shift;
    my $filename = shift;
    my @fsp = split(/\//, $filename);
    my $ret = pop @fsp;
    return $ret;
}

sub dirtrav
{
    my $self = shift;
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
				@files = @{dirtrav($self,\@files,"$pwd/$file")};
			}
			elsif (-f "$pwd/$file")
			{			
				push(@files, "$pwd/$file");			
			}
		}
	}
	return \@files;
}

sub sendFTP
{
    my $self = shift;
    # my @files = @{$self->{relatedfiles}};
    my @files = ('/mnt/evergreen/tmp/oclc_eds_ftp/dummy.txt');
    local $@;
    eval
    {
        _sendFTP($self, $self->{ftpserver}, $self->{ftpuser}, $self->{ftppass}, $self->{ftpfolder}, \@files);
        1;  # ok
    } or do
    {
        addError($self, $@);
    };
}

sub _sendFTP   # server,login,password,remote directory, array of local files to transfer
{
    my $self = shift;
    my ($hostname, $login, $pass, $remotedir, @files) = @_;

    die "Testing and error ".$hostname;

    my $ftp = Net::FTP->new($hostname, Debug => 0, Passive=> 1)
    or die "Cannot connect to ".$hostname;
    $ftp->login($login,$pass)
    or die "Cannot login " . $ftp->message;
    $ftp->cwd($remotedir)
    or die "Cannot change working directory " . $ftp->message;
    foreach my $file (@files)
    {
        $ftp->put($file)
        or die "Sending file $file failed";
    }
    $ftp->quit;
    undef $ftp;
}

sub moveFilesToArchive
{
    my $self = shift;
    print "Moving files to archive\n";
    my $destination = $self->{finaldest};
    if( !(-d $destination) ) # make sure the folder exists
    {
        addError($self, $self->{finaldest} . " directory does not exist");
    }
    else
    {
        foreach(@{$self->{relatedfiles}})
        {
            my $file = $_;
            if(!(copy($file, $destination)))
            {
                addError($self, "Could not move file: $file -> $destination");
            }
            print "Moved $file to $destination\n";
        }
    }
}

sub addError
{
    my $self = shift;
    my $newError = shift;
    my @errors = @{$self->{errors}};
    push @errors, $newError;
    $self->{errors} = \@errors;
    $self->{totalerrors}++;
}

1;