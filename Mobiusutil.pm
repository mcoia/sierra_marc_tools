#!/usr/bin/perl
#
# Mobiusutil.pm
# 
# Requires:
#
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# Net::FTP
# 
# This is a simple utility class that provides some common functions
#
# Usage: 
# my $mobUtil = new Mobiusutil(); #No constructor
# my $conf = $mobUtil->readConfFile($configFile);
#
# Other Functions available:
#	makeEvenWidth
#	sendftp
#	getMarcFromQuery (z39.50)
#	chooseNewFileName
#	trim
#	findSummonIDs
#	makeCommaFromArray
#
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24


package Mobiusutil;
 use MARC::Record;
 use ZOOM; 
 use Net::FTP;
 use Loghandler;
 use Data::Dumper;

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}


sub readConfFile
 {
	my %ret = ();
	my $ret = \%ret;
	my $file = @_[1];
	
	my $confFile = new Loghandler($file);
	if(!$confFile->fileExists())
	{
		print "Config File does not exist\n";
		undef $confFile;
		return false;
	}

	my @lines = @{ $confFile->readFile() };
	undef $confFile;
	
	foreach my $line (@lines)
	{
		$line =~ s/\n//;  #remove newline characters
		my $cur = trim('',$line);
		my $len = length($cur);
		if($len>0)
		{
			if(substr($cur,0,1)ne"#")
			{
		
				my $Name, $Value;
				($Name, $Value) = split (/=/, $cur);
				$$ret{trim('',$Name)} = trim('',$Value);
			}
		}
	}
	
	return \%ret;
 }
 
sub makeEvenWidth  #line, width
{
	my $ret;
	
	if($#_+1 !=3)
	{
		return;
	}
	$line = @_[1];	
	$width = @_[2];
	#print "I got \"$line\" and width $width\n";
	$ret=$line;
	if(length($line)>=$width)
	{
		$ret=substr($ret,0,$width);
	} 
	else
	{
		while(length($ret)<$width)
		{
			$ret=$ret." ";
		}
	}
	#print "Returning \"$ret\"\nWidth: ".length($ret)."\n";
	return $ret;
	
}
 
 sub sendftp    #server,login,password,remote directory, array of local files to transfer, Loghandler object
 {
		
	if($#_+1 !=7)
	{
		return;
	}
	
	my $hostname = @_[1];
	my $login = @_[2];
	my $pass = @_[3];
	my $remotedir = @_[4];
    my @files = @{@_[5]};
	my $log = @_[6];
	
	$log->addLogLine("**********FTP starting -> $hostname with $login and $pass -> $remotedir");
    my $ftp = Net::FTP->new($hostname, Debug => 0)
    or die $log->addLogLine("Cannot connect to ".$hostname);
    $ftp->login($login,$pass)
    or die $log->addLogLine("Cannot login ", $ftp->message);
    $ftp->cwd($remotedir)
    or die $log->addLogLine("Cannot change working directory ", $ftp->message);
	foreach my $file (@files)
	{
		$log->addLogLine("Sending file $file");
		$ftp->put($file)
		or die $log->addLogLine("Sending file $file failed");
	}
    $ftp->quit
	or die $log->addLogLine("Unable to close FTP connection");
	$log->addLogLine("**********FTP session closed ***************");
 }
 
 sub getMarcFromQuery  #Pass values (server,query, Loghander Object)  returns array reference to MARC::Record array
 {
	my @ret;
	
	if($#_+1 !=4)
	{
		return;
	}
		
		
	 my $DATABASE = @_[1];
	 my $query = @_[2];
	 my $log = @_[3];
	 
	 
	 if ( ! $query ) 
	 {	 
		 print "Query Required\n";
		 return;
	 }
	 
	 $log->addLogLine("************Starting Z39.50 Connection -> $DATABASE $query");
	 my $connection = new ZOOM::Connection( $DATABASE, 0, count=>1, preferredRecordSyntax => "USMARC" );
	 my $results = $connection->search_pqf( qq[$query] );
	 
	 my $size = $results->size();
	 $log->addLogLine("Received $size records");
	 my $index = 0;
	 for my $i ( 0 .. $results->size()-1 ) 
	 {
		 #print $results->record( $i )->render();
		 my $record = $results->record( $i )->raw;
		 my $marc = MARC::Record->new_from_usmarc( $record );
		 push(@ret,$marc);
	 }
	 
	 $log->addLogLine("************Ending Z39.50 Connection************");
	 undef $conection, $results;
	 return \@ret;
 }
 
 sub chooseNewFileName   #path to output folder,file prefix, file extention    returns full path to new file name
{
	if($#_+1 !=4)
	{
		return 0;
	}
	my $path = @_[1];
# Add trailing slash if there isn't one	
	if(substr($path,length($path)-1,1) ne '/')
	{
		$path = $path.'/';
	}
	
	my $seed = @_[2];
	my $ext = @_[3];
	my $ret="";
	if( -d $path)
	{
		my $num=0;
		$ret = $path . $seed . $num . '.' . $ext;
		while(-e $ret)
		{
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
 
 sub trim
{
	my $self = shift;
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub findSummonIDs		#DBhandler, #loghandler
{
	if($#_+1 !=3)
	{
		return 0;
	}
	my $dbHandler = @_[1];
	my $log = @_[2];
	
	
	my $query = "SELECT RECORD_ID FROM SIERRA_VIEW.BIB_RECORD WHERE RECORD_ID=420907796199";
	
	my @ret;
	my @results = @{$dbHandler->query($query)};
				 
	 my $size = length(@results);
	 #print @results;
	 #print "recieved $size results\n";
	 
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		print "::newrow::";
		foreach my $val(@row)
		{
			push(@ret, $val);
			print"$val\t";
		}
		print "\n";
		
	}
	
	return @ret;
	
}

sub makeCommaFromArray
 {
	my @array = @{@_[1]};
	print Dumper(\@array);
	my $ret = "";
	for my $i (0..$#array)
	{
		$ret.=@array[$i].",";
	}
	$ret= substr($ret,0,length($ret)-1);
	return $ret;
 }

1;

