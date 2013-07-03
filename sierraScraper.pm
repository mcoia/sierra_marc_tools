#!/usr/bin/perl
#
# sierraScraper.pm
# 
# Requires:
# 
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# 
# This code will scrape the sierra database for all of the values that create MARC records
#
# 
# Usage: 
# my $log = new Loghandler("path/to/log/file");
# my $dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});
# 
# my $sierraScraper = new sierraScraper($dbHandler,$log,"SELECT RECORD_ID FROM SIERRA_VIEW.BIB_RECORD LIMIT 10");
#
# You can get the resulting MARC Records in an array of MARC::Records like this:
#
# my @marc = @{$sierraScraper->getAllMARC()};
#
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24

package sierraScraper;
 use MARC::Record;
 use MARC::File;
 use MARC::File::USMARC;
 use Loghandler;
 use recordItem;
 use strict; 
 use Data::Dumper;
 use Mobiusutil;
 use Date::Manip;
 use DateTime::Format::Duration;
 use String::Multibyte;
 use utf8;
 use Encode;
 use Time::HiRes;
 
 sub new   #DBhandler object,Loghandler object, Array of Bib Record ID's matching sierra_view.bib_record
 {
	my $class = shift;
	my %k=();
	my %d=();
	my %e=();
	my %f=();
	my %g=();
	my %h=();
	my $mobutil = new Mobiusutil();
	my $pidfile = new Loghandler($mobutil->chooseNewFileName('/tmp','scraper_pid','pid'));
	
    my $self = 
	{
		'dbhandler' => shift,
		'log' => shift,
		'bibids' => shift,
		'mobiusutil' => $mobutil,
		'nine45' =>  \%k,
		'nine07' =>  \%d,
		'specials' => \%e,
		'leader' => \%f,
		'standard' => \%g,
		'nine98' => \%h,
		'selects' => "",
		'querytime' => 0,
		'query' => "",
		'type' => "",
		'diskdump' => "",
		'toobig' => "",
		'toobigtocut' => "",
		'pidfile' => $pidfile,
		'title' => ""
	};
	
	my $t = shift;
	my $title = shift;
	if($title)
	{
		$pidfile = new Loghandler($mobutil->chooseNewFileName('/tmp',"scraper_pid_$title",'pid'));
		$self->{'pidfile'} = $pidfile;
		$self->{'title'} = $title;
	}
	$pidfile->addLine("starting up....");
	#print "4: $t\n";
	if($t)
	{
		$self->{'type'}=$t;
	}
	bless $self, $class;
	if(($t) && ($t ne 'thread'))
	{
		#print "It's not a thread\n";
		gatherDataFromDB($self);
	}
	elsif(!$t)
	{
		gatherDataFromDB($self);
	}
    return $self;
 }
 
 sub gatherDataFromDB
 {
	my $self = @_[0];
	my $mobUtil = $self->{'mobiusutil'};
	my $dbHandler = $self->{'dbhandler'};
	my $pidfile = $self->{'pidfile'};
	my $offset = 0;
	my $increment = 5;
	my $limit = 1000;
	my $previousRecordCount = 0;
	my $currentRecordCount = 1;
	my $oldRPS = 5;
	my $title=$self->{'title'};
	figureSelectStatement($self);
	my $selects = $self->{'selects'};
	my @cha = split("",$selects);
	my $tselects = "";
	my @best = (0,25);
	my $noAdjustmentCount=0;
	my $chunks=0;
	my $i=0;
	foreach(@cha)  #Doing this to create a new memory variable instead of an internal pointer to the same memory value
	{
		$tselects.=$_;
	}
	
	if($self->{'type'} eq 'full')
	{	#BREAK UP THE QUERY INTO MANAGABLE CHUNKS
		if(index((uc($tselects)),"SELECT")>-1){$chunks=1;}
	}
	
	if($chunks)
	{
		my $masterfile = new Loghandler($mobUtil->chooseNewFileName('/tmp',"master_$title",'pid'));
		my $query = "SELECT MIN(ID) FROM SIERRA_VIEW.BIB_RECORD";
		my @results = @{$dbHandler->query($query)};		
		my $min = 0;
		my $max = 1;
		foreach(@results)
		{
			my $row = $_;
			my @row = @{$row};
			$min = @row[0];
		}
		$min--;
		$query = $tselects;
		$query =~ s/\$recordSearch/COUNT(\*)/gi;
		
		@results = @{$dbHandler->query($query)};		
		foreach(@results)
		{
			my $row = $_;
			my @row = @{$row};
			$max = @row[0];
		}
		
		$tselects=~s/\$recordSearch/RECORD_ID/gi;
		
		$offset=$min;
		$increment=$min;
		my @dumpedFiles = (0);
		my $totalExtractedRecords=0;
		my $zeroAdded=0;
		my $rps=0;
		my $overallRPS=0;
		my $lastOverallRPS=0;
		my $addedRecords=0;
		my $chunkGoal=100;
		while($totalExtractedRecords < $max )
		{			
			my $lastElement = scalar(@dumpedFiles);
			$lastElement--;
			my $recordsOnDisk=@dumpedFiles[$lastElement];
			my $countQ = $query;
			my $yeild=0;
			my $trys=0;
			$limit = $chunkGoal;
			$increment+=$limit;
			if($chunkGoal<0)
			{
				$chunkGoal=1;
			}
			while($yeild<$chunkGoal)  ## Figure out how many rows to read into the database to get the goal number of records
			{	
				$selects = $countQ." AND ID > $offset AND ID <= $increment";
				
				@results = @{$dbHandler->query($selects)};
				foreach(@results)
				{
					my $row = $_;
					my @row = @{$row};
					$yeild = @row[0];
				}
				#print "Yeild: $yeild\n";
				if($yeild<$chunkGoal)
				{
					$trys++;
					if($trys>100)	#well, 100 * 10 and we didn't get 1000 rows returned, so we are stopping here.
					{
						$yeild=$chunkGoal;
					}
					$limit+=$chunkGoal;
					$increment+=$chunkGoal;
				}
				#print "$limit $offset to $increment\n";
			}
			my $previousTime=DateTime->now;
			$self->{'querytime'} = 0;
			my %standard = %{$self->{'standard'}};
			#print $previousTime->hms."\n";
			#print "Previous: $previousRecordCount Current: $currentRecordCount\n";
			$previousRecordCount = scalar keys %standard;
			$totalExtractedRecords = $previousRecordCount+$recordsOnDisk;
			#print "Records On disk: $recordsOnDisk, In Memory: $previousRecordCount, Total: $totalExtractedRecords\n";			
			#print "Need: $max  Searching: $offset To: $increment\n";
			$masterfile->truncFile($pidfile->getFileName);
			$masterfile->addLine("$rps records/s\n$overallRPS records/s Overall\nIncreased $addedRecords\nChunking: $chunkGoal\nRange: $limit");
			$masterfile->addLine(Dumper(\@dumpedFiles));
			$masterfile->addLine("Records On disk: $recordsOnDisk, In Memory: $previousRecordCount, Total: $totalExtractedRecords\nNeed: $max  Searching: $offset To: $increment");
			$selects = $tselects;
			$selects .= " AND ID > $offset AND ID <= $increment";
			#print $selects."\n";
			$self->{'selects'} = $selects;
			stuffStandardFields($self);			
			stuffSpecials($self);			
			stuff945($self);			
			stuff907($self);			
			stuff998alternate($self);			
			stuffLeader($self);
			my $secondsElapsed = calcTimeDiff($self,$previousTime);
			$offset+=$limit;
			#print "Slowest query\n".$self->{'query'}."\n";
			%standard = %{$self->{'standard'}};
			$currentRecordCount = scalar keys %standard;
			#$currentRecordCount+=$recordsOnDisk;
			$addedRecords = $currentRecordCount - $previousRecordCount;
			if($addedRecords==0)
			{
				$zeroAdded++;
				if($zeroAdded>100) #we have looped 100 times with not a single record added to the collection. Time to quit.
				{
					$totalExtractedRecords = $max;
				}
			}
			else
			{
				$zeroAdded=0;
			}
			my $duration = $self->{'querytime'};
			$rps = $addedRecords / $duration;
			$overallRPS = $addedRecords / $secondsElapsed;
			if($lastOverallRPS>$overallRPS)
			{
				if($chunkGoal>100){	$chunkGoal-=100;}
			}
			elsif($lastOverallRPS<$overallRPS)
			{
				$chunkGoal+=100;
			}
			if($duration>480)  #should only occur when the slowest running query gets above 8 minutes. This is to reset the count to protect against the 10 minute limit
			{
				$chunkGoal=10;
			}
			$lastOverallRPS = $overallRPS;
			@dumpedFiles = @{dumpRamToDisk($self, \@dumpedFiles)};
		}
		#print "Saving disk info:\n";
		#print Dumper(@dumpedFiles);
		$self->{'diskdump'}=\@dumpedFiles;
		$masterfile->deleteFile();
	}
	else
	{
		stuffStandardFields($self);
		stuffSpecials($self);
		stuff945($self);
		stuff907($self);
		stuff998alternate($self);
		stuffLeader($self);
	}
	$self->{'selects'} = $tselects;
	$pidfile->deleteFile();
 }
 
 sub gatherDataFromDB_MultiThread
 {
	my $self = @_[0];
	my $mobUtil = $self->{'mobiusutil'};
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	figureSelectStatement($self);							
	my $selects = $self->{'selects'};
	my @cha = split("",$selects);
	my $tselects = "";	
	my $chunks=0;
	my $i=0;
	foreach(@cha)
	{
		$tselects.=$_;
	}
	
	if($self->{'type'} eq 'full')
	{	#BREAK UP THE QUERY INTO MANAGABLE CHUNKS
		if(index((uc($tselects)),"SELECT")>-1){$chunks=1;}
	}
	
	if($chunks)
	{
		use Config; 
		$Config{useithreads} or die('Recompile Perl with threads to run this program.');
		use threads;
		
		my $query = "SELECT MIN(ID) FROM SIERRA_VIEW.BIB_RECORD";
		my @results = @{$dbHandler->query($query)};		
		my $min = 0;
		my $max = 1;
		foreach(@results)
		{
			my $row = $_;
			my @row = @{$row};
			$min = @row[0];
		}
		$min--;
		$query = $tselects;
		$query =~ s/\$recordSearch/COUNT(\*)/gi;#"SELECT MAX(ID) FROM SIERRA_VIEW.BIB_RECORD";
		print "$query\n";
		@results = @{$dbHandler->query($query)};		
		foreach(@results)
		{
			my $row = $_;
			my @row = @{$row};
			$max = @row[0];
		}
		print "Max: $max\n";
		$tselects=~s/\$recordSearch/RECORD_ID/gi;
		print "$tselects\n";
		my @dumpedFiles = (0);
		my $finishedRecordCount=0;
		my @threadTracker = ();
		my $threadsAllowed = 3;
		my $threadsAlive=1;
		my $offset = $min;
		my $limit = 100;
		my $increment = $min+$limit;
		
		while($threadsAlive)#$previousRecordCount!=$currentRecordCount)
		{
			my $workingThreads=0;
			my @newThreads=();
			print "Thread Tracker:\n";
			my $threadJustFinished=0;
			#print Dumper(\@threadTracker);
			foreach(@threadTracker)
			{			
				my $done = threadDone($_);
				if($done)
				{
					print "$_ Thread Finished.... Cleaning up\n";
					$threadJustFinished=1;
					my $pidReader = new Loghandler($_);
					my @lines = @{ $pidReader->readFile() };
					$pidReader->deleteFile();
					undef $pidReader;
					if(scalar @lines >1)
					{
						@lines[0] =~ s/\n//;  
						@lines[1] =~ s/\n//;
						push(@dumpedFiles,@lines[0]);
						$finishedRecordCount+= @lines[1];
					}
					$workingThreads--;
				}
				else
				{
					$workingThreads++;
					push(@newThreads,$_);
				}
			}
			@threadTracker=@newThreads;
			print "Working Threads: $workingThreads  Allowed Threads: $threadsAllowed\n";
			if($workingThreads<$threadsAllowed)
			{
				if(!$threadJustFinished)
				{
					if($finishedRecordCount<$max)
					{
						print "Starting new thread\n";
						print "Max: $max   From: $offset To: $increment\n";
						my $thisPid = $mobUtil->chooseNewFileName("/tmp","0","sierrapid");
						print "Pid: $thisPid\n";
						$selects = $tselects;
						$selects .= " AND ID > $offset AND ID <= $increment";
						my $newS = new sierraScraper($dbHandler,$log,$selects,'thread');
						#print "Started the thread... now pushing to array\n";
						push(@threadTracker,$thisPid);
						#print "Pushed.... creating...\n";
						my $thr = threads->create(\&startThread, $newS, $thisPid);
						#print "Created!\n";
						$thr->detach();
						print "Detached!\n";
						#print Dumper($newS);
						#print Dumper($self);
						$offset+=$limit;
						$increment+=$limit;
						$workingThreads++;
					}
					else
					{
						print "We have reached our target record count... script is winding down\n";
					}
				}
			}
			
			if($workingThreads==0)
			{
				$threadsAlive=0;
			}
			
			
			print "Records On disk: $finishedRecordCount\n";
			sleep(15);
		}
	}
	else
	{
		stuffStandardFields($self);
		stuffSpecials($self);
		stuff945($self);
		stuff907($self);
		stuff998alternate($self);
		stuffLeader($self);
	}
	$self->{'selects'} = $tselects;
 }
 
 sub startThread
 {
	my $sierraScraperObject = @_[0];
	my $pidFile = @_[1];
	my $pidWriter = new Loghandler($pidFile);
	$pidWriter->truncFile("0");
	my @dumpedFiles = @{$sierraScraperObject->go()};
	
	if(scalar @dumpedFiles > 0)
	{
		my $Count = @dumpedFiles[1];
		my $filename = @dumpedFiles[0];
		$pidWriter->truncFile("$filename\n$Count");
	}
	else
	{
		$pidWriter->truncFile("1");
	}
	return 0;
 }
 
 sub go
 {
	my ($self) = @_[0];
	
	my $dbHandler = $self->{"dbhandler"};
	my %conf = %{$dbHandler->getConnectionInfo()};
	my $db = new DBhandler($conf{"dbname"},$conf{"host"},$conf{"login"},$conf{"password"},$conf{"port"});
	$self->{"dbhandler"}=$db;
	bless $self;
	print "Ok - staring GO Method\n";
	figureSelectStatement($self);
	print "Ok - figureSelectStatement\n";
	stuffStandardFields($self);
	print "Ok - stuffStandardFields\n";
	stuffSpecials($self);
	print "Ok - stuffSpecials\n";
	stuff945($self);
	print "Ok - stuff945\n";
	stuff907($self);
	print "Ok - stuff907\n";
	stuff998alternate($self);
	print "Ok - stuff998alternate\n";
	stuffLeader($self);
	print "Ok - stuffLeader\n";
	my @t = ();
	my @dumpedFiles = @{dumpRamToDisk($self, \@t)};
	return \@dumpedFiles;
 }
 
 sub threadDone
 {
	 my $pidFile = @_[0];
	 my $pidReader = new Loghandler($pidFile);
	my @lines = @{ $pidReader->readFile() };
	undef $pidReader;
	if(scalar @lines >1)
	{
		return 1;
	}
	elsif(scalar @lines ==1)
	{
		my $line =@lines[0];
		$line =~ s/\n//;
		if($line eq "0")
		{
			return 0;
		}
		else
		{
			return 1;
		}
	}
	return 0;
 }
 
 sub getSingleStandardFields
 {	
	my ($self) = @_[0];
	my $idInQuestion = @_[1];
	my $log = $self->{'log'};
	my %standard = %{$self->{'standard'}};
	if(exists $standard{$idInQuestion})
	{
		#print "It exists\n";
	}
	return \@{$standard{$idInQuestion}};
 }
 
 sub stuffStandardFields
 {
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my $mobUtil = $self->{'mobiusutil'};
	my %standard = %{$self->{'standard'}};
	my $selects = $self->{'selects'};
	my $previousTime=DateTime->now;
	my $pidfile = $self->{'pidfile'};
	my $query = "SELECT A.MARC_TAG,A.FIELD_CONTENT,
	(SELECT MARC_IND1 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
	(SELECT MARC_IND2 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
	RECORD_ID FROM SIERRA_VIEW.VARFIELD_VIEW A WHERE A.RECORD_ID IN($selects) ORDER BY A.MARC_TAG, A.OCC_NUM";
	#print "$query\n";	
	$pidfile->truncFile($query);
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	my @records;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		if(@row[0] ne '970' &&@row[0] ne '971' &&@row[0] ne '972')
		{
			my $recordID = @row[4];			
			if(!exists $standard{$recordID})
			{
				my @a = ();
				$standard{$recordID} = \@a;
			}
			my $ind1 = @row[2];
			my $ind2 = @row[3];
			
			if(length($ind1)<1)
			{
				$ind1=' ';
			}
			
			if(length($ind2)<1)
			{
				$ind2=' ';
			}
			#print "Pushing ".@row[1]."\n";
			push(@{$standard{$recordID}},new recordItem(@row[0],$ind1,$ind2,@row[1]));
		}
	}
	$self->{'standard'} = \%standard;
	
 }
 
 sub stuffSpecials
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %specials = %{$self->{'specials'}};
	my $mobiusUtil = $self->{'mobiusutil'};	
	my $selects = $self->{'selects'};
	my $pidfile = $self->{'pidfile'};
	my $concatPhrase = "CONCAT(";
	for my $i(0..39)
	{
		my $string = sprintf( "%02d", $i );  #Padleft 0's for a total of 2 characters
		$concatPhrase.="p$string,";
	}
	$concatPhrase=substr($concatPhrase,0,length($concatPhrase)-1).")";
	my $query = "SELECT CONTROL_NUM,$concatPhrase,RECORD_ID FROM SIERRA_VIEW.CONTROL_FIELD WHERE RECORD_ID IN($selects)";	
	#print "$query\n";
	$pidfile->truncFile($query);
	my $previousTime=DateTime->now;		
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[2];
		my $recordItem;
		if(!exists $specials{$recordID})
		{
			my @a = ();
			$specials{$recordID} = \@a;
		}
		if(@row[0] eq '6')
		{
			push(@{$specials{$recordID}},new recordItem('006','','',$mobiusUtil->makeEvenWidth(@row[1],44)));
		}
		elsif(@row[0] eq '7')
		{
			push(@{$specials{$recordID}},new recordItem('007','','',$mobiusUtil->makeEvenWidth(@row[1],44)));
		}
		elsif(@row[0] eq '8')
		{
			push(@{$specials{$recordID}},new recordItem('008','','',$mobiusUtil->makeEvenWidth(@row[1],40)));
		}
	}
	#print Dumper(\%specials);
	$self->{'specials'} = \%specials;
}

sub stuffLeader
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %leader = %{$self->{'leader'}};
	my $mobiusUtil = $self->{'mobiusutil'};	
	my $selects = $self->{'selects'};
	
	my $query = "SELECT
	RECORD_ID,
	RECORD_STATUS_CODE,
	RECORD_TYPE_CODE,
	BIB_LEVEL_CODE,
	CONTROL_TYPE_CODE,
	CHAR_ENCODING_SCHEME_CODE,
	ENCODING_LEVEL_CODE,
	DESCRIPTIVE_CAT_FORM_CODE,
	MULTIPART_LEVEL_CODE
    FROM SIERRA_VIEW.LEADER_FIELD A WHERE A.RECORD_ID IN($selects)";
	my $pidfile = $self->{'pidfile'};
	$pidfile->truncFile($query);
	#print "$query\n";
	my $previousTime=DateTime->now;	
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		
		for my $i (1..$#row)
		{
			if(length(@row[$i])!=1)
			{
				#print "Leader: Correcting empty field\n";
				@row[$i] = " ";
			}
		}
		
		my $firstPart = @row[1].@row[2].@row[3].@row[4].@row[5];
		my $lastPart = @row[6].@row[7].@row[8];
		#print "First part: $firstPart Last Part: $lastPart\n";
		my @add = ($firstPart,$lastPart);
		if(!exists $leader{$recordID})
		{
			$leader{$recordID} = \@add;
		}
		else
		{
			$log->addLogLine("Leader Scrape: There were more than one leader row returned from query $query");
		}
		
	}
	#print Dumper(\%leader);
	$self->{'leader'} = \%leader;
}

sub stuff945
{

	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nineHundreds = %{$self->{'nine45'}};
	my $mobiusUtil = $self->{'mobiusutil'};
	my $selects = $self->{'selects'};
	
	my $query = "SELECT
		(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID = A.ID AND BIB_RECORD_ID IN($selects) LIMIT 1),
		A.ID,
		(SELECT MARC_IND1 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
		(SELECT MARC_IND2 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
		CONCAT('|g',A.COPY_NUM) AS \"g\",
		(SELECT CONCAT('|i',BARCODE) FROM SIERRA_VIEW.ITEM_VIEW WHERE ID=A.ID) AS \"i\",
		CONCAT('|j',A.AGENCY_CODE_NUM) AS \"j\",
		CONCAT('|l',A.LOCATION_CODE) AS \"l\",
		CONCAT('|o',A.ICODE2) AS \"o\",
		CONCAT('|p\$',TRIM(TO_CHAR(A.PRICE,'9999999999990.00'))) AS \"p\",
		CONCAT('|q',A.ITEM_MESSAGE_CODE) AS \"q\",
		CONCAT('|r',A.OPAC_MESSAGE_CODE) AS \"r\",
		CONCAT('|s',A.ITEM_STATUS_CODE) AS \"s\",
		CONCAT('|t',A.ITYPE_CODE_NUM) AS \"t\",
		CONCAT('|u',A.CHECKOUT_TOTAL) AS \"u\",
		CONCAT('|v',A.RENEWAL_TOTAL) AS \"v\",
		CONCAT('|w',A.YEAR_TO_DATE_CHECKOUT_TOTAL) AS \"w\",
		CONCAT('|x',A.LAST_YEAR_TO_DATE_CHECKOUT_TOTAL) AS \"x\",
		(SELECT CONCAT('|z',TO_CHAR(CREATION_DATE_GMT, 'MM-DD-YY')) FROM SIERRA_VIEW.RECORD_METADATA WHERE ID=A.ID) AS \"z\"
		FROM SIERRA_VIEW.ITEM_RECORD A WHERE A.ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN ($selects))";

																if(0)
																{
																my $query = "SELECT
																	B.BIB_RECORD_ID,
																	A.ID,
																	(SELECT MARC_IND1 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
																	(SELECT MARC_IND2 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
																	CONCAT('|g',A.COPY_NUM) AS \"g\",
																	(SELECT CONCAT('|i',BARCODE) FROM SIERRA_VIEW.ITEM_VIEW WHERE ID=A.ID) AS \"i\",
																	CONCAT('|j',A.AGENCY_CODE_NUM) AS \"j\",
																	CONCAT('|l',A.LOCATION_CODE) AS \"l\",
																	CONCAT('|o',A.ICODE2) AS \"o\",
																	CONCAT('|p\$',TRIM(TO_CHAR(A.PRICE,'9999999999990.00'))) AS \"p\",
																	CONCAT('|q',A.ITEM_MESSAGE_CODE) AS \"q\",
																	CONCAT('|r',A.OPAC_MESSAGE_CODE) AS \"r\",
																	CONCAT('|s',A.ITEM_STATUS_CODE) AS \"s\",
																	CONCAT('|t',A.ITYPE_CODE_NUM) AS \"t\",
																	CONCAT('|u',A.CHECKOUT_TOTAL) AS \"u\",
																	CONCAT('|v',A.RENEWAL_TOTAL) AS \"v\",
																	CONCAT('|w',A.YEAR_TO_DATE_CHECKOUT_TOTAL) AS \"w\",
																	CONCAT('|x',A.LAST_YEAR_TO_DATE_CHECKOUT_TOTAL) AS \"x\",
																	(SELECT CONCAT('|z',TO_CHAR(CREATION_DATE_GMT, 'MM-DD-YY')) FROM SIERRA_VIEW.RECORD_METADATA WHERE ID=A.ID) AS \"z\"
																	FROM SIERRA_VIEW.ITEM_RECORD A,
																	SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK B
																	WHERE
																	A.ID=B.ITEM_RECORD_ID
																	AND
																	A.ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN ($selects))";
																	}
		my $pidfile = $self->{'pidfile'};
	$pidfile->truncFile($query);
	#print "$query\n";
	my $previousTime=DateTime->now;	
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	my %tracking; # links recordItems objects to item Numbers without having to search everytime
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $ind1 = @row[2];
		my $ind2 = @row[3];
		if(length($ind1)<1)
		{
			$ind1=' ';
		}
		
		if(length($ind2)<1)
		{
			$ind2=' ';
		}
		
		my $recordID = @row[0];		
		my $subItemID = @row[1];
		
		
		if(!exists $nineHundreds{$recordID})
		{
			my @a = ();
			my %b;
			$nineHundreds{$recordID} = \@a;
			$tracking{$recordID} = \%b;
		}
		
		my %t = %{$tracking{$recordID}};
		if(!exists $t{$subItemID})
		{
			$t{$subItemID} = $#{$nineHundreds{$recordID}}+1;
			$tracking{$recordID} = \%t;
		}
		else
		{
			$log->addLogLine("945 Scrape: Huston, we have a problem, the query returned more than one of the same item(duplicate 945 record) - $recordID");
		}
		my $all;
		foreach my $b (4..$#row)
		{
			$all = $all.@row[$b];
		}
		push(@{$nineHundreds{$recordID}},new recordItem('945',$ind1,$ind2,$all));
		
	}

	$query = "SELECT
	RECORD_ID,
	VARFIELD_TYPE_CODE,
	MARC_TAG,
	FIELD_CONTENT,
	(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID=A.RECORD_ID AND BIB_RECORD_ID IN ($selects) LIMIT 1) AS \"BIB_ID\",
	RECORD_NUM
	FROM SIERRA_VIEW.VARFIELD_VIEW A WHERE RECORD_ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN($selects))
	AND VARFIELD_TYPE_CODE !='a' ORDER BY RECORD_ID";
	$pidfile->truncFile($query); 
	#print "$query\n";
	my $previousTime=DateTime->now;		
	@results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	my $outterp = 0;
	my $startSection=0;
	while($outterp<=$#results)
	{
		my $row = @results[$outterp];
		my @row = @{$row};
		my $trimmedID = $mobiusUtil->trim(@row[2]);
		if(exists $nineHundreds{@row[4]})
		{
			my @thisArray = @{$nineHundreds{@row[4]}};
			if(exists ${$tracking{@row[4]}}{@row[0]})
			{
				my $thisArrayPosition = ${$tracking{@row[4]}}{@row[0]};				
				if(($trimmedID eq '082') || ($trimmedID eq '090') || ($trimmedID eq '086') || ($trimmedID eq '099') || ($trimmedID eq '866') || ($trimmedID eq '050') || ($trimmedID eq '912') || ($trimmedID eq '900') || ($trimmedID eq '927') || ($trimmedID eq '926') || ($trimmedID eq '929') || ($trimmedID eq '928') || ($trimmedID eq '060'))
				{
				
					my $thisRecord = @thisArray[$thisArrayPosition];
					$thisRecord->addData(@row[3]);
					my $checkDigit = calcCheckDigit($self,@row[5]);
					my $barcodeNum = "i".@row[5].$checkDigit;
					$thisRecord->addData("|y.$barcodeNum");
					my $recordID = @row[4];
					my $subItemID = @row[0];
					my $foundMatch=0;
					my $pointer=$startSection;
					while($pointer<=$#results)# Find Null marc_tag values related to 082,090,086,099,866,050,912,900,927,926,929,928,060
					{
						my $rowsearch = @results[$pointer];
						my @rowsearch = @{$rowsearch};
						if(@rowsearch[3] ne '')
						{
							#print "@rowsearch[0] == @row[0]\n";
							if(@rowsearch[0] == @row[0]) 
							{
								#print "$pointer / $#results\n";
								$foundMatch=1;
								if(@rowsearch[2] eq '')
								{	
									my $firstChar = substr($rowsearch[3],0,1);
									if((@rowsearch[1] eq 'b') && ($firstChar ne '|'))
									{
										$thisRecord->addData('|i'.@rowsearch[3]);
									}
									elsif((@rowsearch[1] eq 'v') && ($firstChar ne '|'))
									{
										$thisRecord->addData('|c'.@rowsearch[3]);
									}
									elsif((@rowsearch[1] eq 'x') && ($firstChar ne '|'))
									{
										$thisRecord->addData('|n'.@rowsearch[3]);
									}
									elsif((@rowsearch[1] eq 'm') && ($firstChar ne '|'))
									{
										$thisRecord->addData('|m'.@rowsearch[3]);
									}
									elsif((@rowsearch[1] eq 'c') && ($firstChar eq '|'))
									{
										$thisRecord->addData(@rowsearch[3]);
									}
									elsif((@rowsearch[1] eq 'v') && ($firstChar eq '|'))
									{
										$thisRecord->addData(@rowsearch[3]);
									}
									elsif((@rowsearch[1] eq 'd') && ($firstChar eq '|'))
									{
										$thisRecord->addData(@rowsearch[3]);
									}
									else
									{
										if((@rowsearch[1] ne 'n') && (@rowsearch[1] ne 'p')&& (@rowsearch[1] ne 'r'))
										{
											$log->addLogLine("Related 082,090,086,099,866,050,912,900,927,926,929,928,060 item(".@row[0].") bib($recordID) barcode($barcodeNum) value omitted: ".@rowsearch[1]." = ".@rowsearch[3]);
										}
									}
								}								
							}
							elsif($foundMatch)#stop looping because it has found all related rows (they are sorted as per the order clause in the query)
							{
								$outterp=$pointer-2;
								$startSection=$pointer;
								$pointer=$#results+1;
								
							}
						}
						$pointer++;
					}
					@{$nineHundreds{@row[4]}}[$thisArrayPosition] = $thisRecord;
				}
				elsif( $trimmedID ne '')
				{
					$log->addLogLine(@row[4]." not added \"$trimmedID\" = ".@row[3]);
					#push(@{$nineHundreds{@row[4]}},new recordItem(@row[2],'','',@row[3]));;
				}
			}
			else
			{
				if(@row[2] eq '086')
				{
					$log->addLogLine("I found a row and it looks like this \"$trimmedID\" = ".@row[3]);
					$log->addLogLine("I'm adding that as a 945");
					push(@{$nineHundreds{@row[4]}},new recordItem('945','','',@row[3]));
				}
				else
				{
					$log->addLogLine("945 scrape: Strange results: ".@row[0]." ".@row[1]." ".@row[2]." ".@row[3]." ".@row[4]);
				}
			}
			
		}
		else
		{
			$log->addLogLine("There were items in varfield_view that didn't appear before now:");
			$log->addLogLine("Bib id  = ".@row[4]." Item id = ".@row[0].",$trimmedID = ".@row[3]);
			$log->addLogLine("This was not added to the marc array");
		}
		$outterp++;
	}
	$self->{'nine45'} = \%nineHundreds;
}

sub stuff907
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nine07 = %{$self->{'nine07'}};
	my $selects = $self->{'selects'};
	my $query = "SELECT A.ID,RECORD_TYPE_CODE,RECORD_NUM,
	CONCAT(
	CONCAT('|b',TO_CHAR(A.RECORD_LAST_UPDATED_GMT, 'MM-DD-YY')),
	CONCAT('|c',TO_CHAR(A.CREATION_DATE_GMT, 'MM-DD-YY'))
	)
	FROM SIERRA_VIEW.RECORD_METADATA A WHERE A.ID IN($selects)";
	my $pidfile = $self->{'pidfile'};
	$pidfile->truncFile($query);
	#print "$query\n";
	my $previousTime=DateTime->now;		
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		my $checkDigit = calcCheckDigit($self,$row[2]);
		my $subA = "|a.".@row[1].@row[2].$checkDigit;
		if(!exists $nine07{$recordID})
		{
			my @a = ();
			$nine07{$recordID} = \@a;
		}
		push(@{$nine07{$recordID}},new recordItem('907','','',$subA.@row[3]));
	}
	
	$self->{'nine07'} = \%nine07;
}

sub stuff998
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nine98 = %{$self->{'nine98'}};
	my $mobiusUtil = $self->{'mobiusutil'};
	my $selects = $self->{'selects'};
	my $query = "SELECT ID,
	CONCAT(
	CONCAT('|b',TO_CHAR(CATALOGING_DATE_GMT, 'MM-DD-YY')),
	CONCAT('|c',BCODE1),
	CONCAT('|d',BCODE2),
	CONCAT('|e',BCODE3),
	CONCAT('|f',LANGUAGE_CODE),
	CONCAT('|g',COUNTRY_CODE),
	CONCAT('|h',SKIP_NUM)
	)
	FROM SIERRA_VIEW.BIB_VIEW WHERE ID IN($selects)";
	print "$query\n";
	my $previousTime=DateTime->now;		
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		if(!exists $nine98{$recordID})
		{
			my @a = ();
			$nine98{$recordID} = \@a;
		}
		else
		{
			#print "$recordID - Error - There is more than one row returned when creating the 998 record\n";
		}
		push(@{$nine98{$recordID}},new recordItem('998','','',@row[1]));
	}
	$query = "SELECT 
	(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID = A.ID),
	SUBSTR(LOCATION_CODE,1,LENGTH(LOCATION_CODE)-2) FROM SIERRA_VIEW.ITEM_RECORD A WHERE A.ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN($selects))";

	print "$query\n";
	@results = @{$dbHandler->query($query)};
	my %counts;
	my %total;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		my $location = @row[1];
		if(!exists $nine98{$recordID})
		{
			$log->addLogLine("Stuffing 998 Field $recordID - Error - There is more than one row returned when creating the 998 record");
		}
		else
		{
			if(!exists $counts{$recordID})
			{
				#$counts{$recordID} = {};
				${$counts{$recordID}}{$location}=0;
				${$total{$recordID}}=0;
			}
			${$counts{$recordID}}{$location}++;
			${$total{$recordID}}++;
		}
	}
	while ((my $internal, my $value ) = each(%counts))
	{
		my %tt = %{$value};
		my $total = ${$total{$internal}};
		my $addValue = "";
		while((my $internal2, my $value2) = each(%tt))
		{
			if($value2 == 1)
			{
				$addValue.="|a".$internal2;
			}
			else
			{
				$addValue.="|a(".$value2.")".$internal2;
			}
		}
		#print "Adding $addValue\n";
		@{$nine98{$internal}}[0]->addData($addValue."|i$total");
	}
	
	
	$self->{'nine98'} = \%nine98;
}

# This was created to try another method of counting the copies at each of the locations
# based upon the information located in sierra_view.bib_record_location instead of sierra_view.item_record.
# There is some sort of unusual behavior in the sierra desktop client when there is only 1 945 record.
# It looks like it subtracts 1 from the copy number when there is only 1 row returned. Pretty odd.
# "Multi" is directly inputted into the "i" field.

sub stuff998alternate
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nine98 = %{$self->{'nine98'}};
	my $mobiusUtil = $self->{'mobiusutil'};
	my $selects = $self->{'selects'};
	my $query = "SELECT ID,
	CONCAT(
	CONCAT('|b',TO_CHAR(CATALOGING_DATE_GMT, 'MM-DD-YY')),
	CONCAT('|c',BCODE1),
	CONCAT('|d',BCODE2),
	CONCAT('|e',BCODE3),
	CONCAT('|f',LANGUAGE_CODE),
	CONCAT('|g',COUNTRY_CODE),
	CONCAT('|h',SKIP_NUM)
	)
	FROM SIERRA_VIEW.BIB_VIEW WHERE ID IN($selects)";
	my $pidfile = $self->{'pidfile'};
	$pidfile->truncFile($query);
	#print "$query\n";
	my $previousTime=DateTime->now;	
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		if(!exists $nine98{$recordID})
		{
			my @a = ();
			$nine98{$recordID} = \@a;
		}
		else
		{
			#print "$recordID - Error - There is more than one row returned when creating the 998 record\n";
		}
		push(@{$nine98{$recordID}},new recordItem('998','','',@row[1]));
	}
	$query = "SELECT 
	BIB_RECORD_ID,LOCATION_CODE,COPIES
	FROM SIERRA_VIEW.BIB_RECORD_LOCATION A WHERE A.BIB_RECORD_ID IN($selects) ";
	#AND LOCATION_CODE!='multi'";
	
	my $query2="SELECT BIB_RECORD_ID,COUNT(*) FROM SIERRA_VIEW.BIB_RECORD_LOCATION WHERE BIB_RECORD_ID IN ($selects) GROUP BY BIB_RECORD_ID";
	$pidfile->truncFile($query2);
	#print "$query\n$query2\n";
	my $previousTime=DateTime->now;	
	@results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	my $previousTime = DateTime->now;
	my @results2 = @{$dbHandler->query($query2)};
	updateQueryDuration($self,$previousTime,$query2);
	my %counts;
	my %total;
	my %multicheck;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		my $location = @row[1];
		my $copies = @row[2];
		if(!exists $nine98{$recordID})
		{
			$log->addLogLine("Stuffing 998 Field $recordID - Error - There is more than one row returned when creating the 998 record");
		}
		else
		{
			if($location eq 'multi')
			{
				if(!exists $multicheck{$recordID})
				{
					${$multicheck{$recordID}} = $copies;
				}
			}
			else
			{
				if(!exists $counts{$recordID})
				{
					#$counts{$recordID} = {};
					${$counts{$recordID}}{$location}=0;
					${$total{$recordID}}=0;
				}
				my $subtractBy=0;
				foreach(@results2)
				{
					my $row2 = $_;
					my @row2 = @{$row2};
					if(@row2[0] eq $recordID)
					{
						if(@row2[1] eq '1')
						{
							$subtractBy=$copies-1;
						}
					}
				}
				my $total = $copies-$subtractBy;
				if($total<1)
				{
					$total=1;
				}
				${$counts{$recordID}}{$location}+=$total;
				${$total{$recordID}}+=$copies;
			}
		}
	}
	while ((my $internal, my $value ) = each(%counts))
	{
		my %tt = %{$value};
		my $total = ${$total{$internal}};
		if(exists($multicheck{$internal}))
		{
		
			$total = ${$multicheck{$internal}};
			#print "$internal - Multi existed so total will be trumped with $total\n";
		}
		my $addValue = "";
		while((my $internal2, my $value2) = each(%tt))
		{
			if($value2 == 1)
			{
				$addValue.="|a".$internal2;
			}
			else
			{
				$addValue.="|a(".$value2.")".$internal2;
			}
		}
		#print "Adding $addValue\n";
		@{$nine98{$internal}}[0]->addData($addValue."|i$total");
	}
	
	
	$self->{'nine98'} = \%nine98;
}
 
 sub getSingleMARC
 {
	my ($self) = @_[0];
	my $recID = @_[1];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my $mobiusUtil = $self->{'mobiusutil'};
	my %nine45 = %{$self->{'nine45'}};
	my %nine07 =%{$self->{'nine07'}};
	my %nine98 =%{$self->{'nine98'}};
	my %specials = %{$self->{'specials'}};
	my %standard = %{$self->{'standard'}};
	my %leader = %{$self->{'leader'}};
	my @try = ('nine45','nine07','nine98','specials','standard');
	my @marcFields;
	
	foreach(@try)
	{
		@marcFields = @{pushMARCArray($self,\@marcFields,$_,$recID)};
	}
	
	#turn off sorting because it's a cpu hog when doing huge dumps
	if(1)#$self->{'type'} ne 'full')
	{
		#Sort by MARC Tag

		my $changed = 1;
		while($changed)
		{
			$changed=0;
			for my $i (0..$#marcFields)
			{
				if($i+1<$#marcFields)
				{
					my $thisone = @marcFields[$i]->tag();
					my $nextone;
					eval{$nextone = @marcFields[$i+1]->tag();};
					if ($@) 
					{
						#print "Can't call method tag\ni= $i count = $#marcFields \nRecord ID = $recID";
						#print Dumper(@marcFields);
						$log->addLogLine("Can't call method \"tag\" on an undefined value");
					}
					else
					{
						if($nextone lt $thisone)
						{
							$changed=1;
							my $temp = @marcFields[$i];
							@marcFields[$i] = @marcFields[$i+1];
							@marcFields[$i+1] = $temp;
						}
					}
				}
			}
		}
	}
	#create MARC:Record Object and stuff fields
	my $ret = MARC::Record->new();
	
	#$ret->append_fields( @marcFields );
	$ret->insert_fields_ordered( @marcFields );
	#Alter the Leader to match Sierra
	my $leaderString = $ret->leader();
	#print "Leader was $leaderString\n";
	if(exists $leader{$recID})
	{
		my @thisLeaderAdds = @{$leader{$recID}};
		#print Dumper(\@thisLeaderAdds);
		$leaderString = $mobiusUtil->insertDataIntoColumn($leaderString,@thisLeaderAdds[0],6);
		$leaderString = $mobiusUtil->insertDataIntoColumn($leaderString,@thisLeaderAdds[1],18);
		#print "Leader is now $leaderString\n";
		$ret->leader($leaderString);
	}
	$ret->encoding( 'UTF-8' );
	return $ret;
 }
 
 sub pushMARCArray
 {
	my ($self) = @_[0];
	my @marcFields = @{$_[1]};
	my %group = %{$self->{$_[2]}};
	my $recID = @_[3];
	
	my @fields;
	if(exists $group{$recID})
	{
		#print Dumper(\%group);
		@fields = $group{$recID};
		for my $i (0..$#fields)
		{
			my @recordItems = @{@fields[$i]};
			foreach(@recordItems)
			{
				##Sometimes there isn't enough data in the subfield to create a field object
				# So we check for undef value returned from getMARCField()
				my $mfield = $_->getMARCField();  
				if($mfield!=undef)
				{
					push(@marcFields,$mfield);
				}
			}

		}
	}
	return \@marcFields;
 }
 
 sub getAllMARC
 {
	my $self = @_[0];
	my %standard = %{$self->{'standard'}};
	my $dumpedFiles = $self->{'diskdump'};
	my @marcout;
	
	#format memory into marc
	while ((my $internal, my $value ) = each(%standard))
	{
		push(@marcout,getSingleMARC($self,$internal));
	}
	#look for any dumped files and read those into the array
	if(ref $dumpedFiles eq 'ARRAY')
	{
		my @dumpedFiles = @{$dumpedFiles};
		print Dumper(\@dumpedFiles);
		foreach(@dumpedFiles)
		{	
			my $marcfile = $_;
			my $check = new Loghandler($marcfile);
			if($check->fileExists())
			{
				my $file = MARC::File::USMARC->in( $marcfile );
				my $r =0;
				while ( my $marc = $file->next() ) 
				{						
					$r++;
					push(@marcout,$marc);
				}
				print "Read $r records from $_\n";
				$check->deleteFile();
			}
		}
	}
	return \@marcout;
 }
 
 sub figureSelectStatement
 { 
	my $self = @_[0];
	my $test = $self->{'bibids'};
	my $dbHandler = $self->{'dbhandler'};
	my $results = "";
	my $mobUtil = $self->{'mobiusutil'};
	if(ref $test eq 'ARRAY')
	{
		my @ids = @{$test};
		$results = $mobUtil->makeCommaFromArray(\@ids);
	}
	else
	{
		$results = $test;
		if(0)
		{
#This was just a bad idea. It was supposed to created comma separated ID's from the initial query
#Originally it was thought that this would make the later queries run faster but this breaks sometimes.
			if(index((uc($results)),"SELECT")>-1)
			{
			
				my @results;
				local $@;
				eval{@results = @{$dbHandler->query($test)}};
				if (!$@) 			
				{
					my @ids;
					foreach(@results)
					{
						my $row = $_;
						my @row = @{$row};
						push(@ids,@row[0]);
					}
					#print "ID count = $#ids\n";
					if($#ids<0)
					{
						$results="-1";
					}
					elsif($#ids<1000)
					{
						$results = $mobUtil->makeCommaFromArray(\@ids);
					}
					else
					{
						$results = $test;
					}
				}
				else
				{
					$results = $test;
				}
			}
		}
	}
	$self->{'selects'}  = $results;
	
 }
 
 sub calcCheckDigit
 {
	my $seed =@_[1];
	$seed = reverse($seed);
	my @chars = split("", $seed);
	my $checkDigit = 0;
	for my $i (0.. $#chars)
	{
		$checkDigit += @chars[$i] * ($i+2);
	}
	$checkDigit =$checkDigit%11;
	if($checkDigit>9)
	{
		$checkDigit='x';
	}
	return $checkDigit;
 }
 
 sub getBursarInfo
 {
	my $self = @_[0];
	my $selects = $self->{'selects'};
	my $log = $self->{'log'};
	my $dbHandler = $self->{'dbhandler'};
	my $outputPath = @_[1];
	if(-d $outputPath)
	{
		my $query = "SELECT INVOICE_NUM,
		TO_CHAR(ASSESSED_GMT, 'YYMMDD'),
		CHARGE_LOCATION_CODE,
		(SELECT RECORD_NUM FROM SIERRA_VIEW.PATRON_VIEW WHERE ID=A.PATRON_RECORD_ID),
		CONCAT('b',(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE RECORD_ID=A.PATRON_RECORD_ID AND FIELD_TYPE_CODE='b' LIMIT 1)),
		(SELECT CONCAT(LAST_NAME,', ',FIRST_NAME) FROM SIERRA_VIEW.PATRON_RECORD_FULLNAME WHERE PATRON_RECORD_ID=A.PATRON_RECORD_ID),
		(SELECT CONCAT(
	ADDR1,'\$',
	ADDR2,'\$',ADDR3,'\$',CITY,'\$',REGION,'\$',POSTAL_CODE) FROM SIERRA_VIEW.PATRON_RECORD_ADDRESS WHERE PATRON_RECORD_ID=A.PATRON_RECORD_ID AND PATRON_RECORD_ADDRESS_TYPE_ID=1 LIMIT 1),
		(SELECT 
		CONCAT(
		PCODE1,'|',
		PCODE2,'|',
		PCODE3,'|',
		PTYPE_CODE)
		FROM SIERRA_VIEW.PATRON_RECORD WHERE ID=A.PATRON_RECORD_ID),
		TRIM(CONCAT('b',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE RECORD_ID=A.ITEM_RECORD_METADATA_ID AND FIELD_TYPE_CODE='b')
		)),
		
		TRIM(CONCAT(	
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='a' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID)),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='b' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID)),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='c' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID)),
		' ',	
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='d' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID))
		)),
		
		TRIM(CONCAT(
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=0 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=1 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=2 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=3 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=4 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID)
		)),
		(CASE 
			WHEN CHARGE_CODE='1' THEN 'MANUAL CHARGE'
			WHEN CHARGE_CODE='2' THEN 'OVERDUE'
			WHEN CHARGE_CODE='3' THEN 'REPLACEMENT'
			WHEN CHARGE_CODE='4' THEN 'OVERDUEX'
			WHEN CHARGE_CODE='5' THEN 'LOST BOOK'
			WHEN CHARGE_CODE='6' THEN 'OVERDUE RENEWED'
			WHEN CHARGE_CODE='7' THEN 'RENTAL'
			WHEN CHARGE_CODE='8' THEN 'RENTALX'
			WHEN CHARGE_CODE='9' THEN 'DEBIT'
			WHEN CHARGE_CODE='a' THEN 'NOTICE'
			WHEN CHARGE_CODE='b' THEN 'CREDIT CARD'
			WHEN CHARGE_CODE='p' THEN 'PROGRAM'
			END),
		TRIM(TO_CHAR(ITEM_CHARGE_AMT,'9999999999990.00')),
		TRIM(TO_CHAR(PROCESSING_FEE_AMT,'9999999999990.00')),
		TRIM(TO_CHAR(BILLING_FEE_AMT,'9999999999990.00'))		
		FROM SIERRA_VIEW.FINE A WHERE INVOICE_NUM IN ($selects)";
		print "$query\n";
		my @results = @{$dbHandler->query($query)};		
		my @output;
		my $lowestInvoiceNum=0;
		my $highestInvoiceNum=0;
		my $recordCount = 0;
		my $totalAmt1=0;
		my $totalAmt2=0;
		my $totalAmt3=0;
		
		foreach(@results)
		{
			$recordCount++;
			my $row = $_;
			my @row = @{$row};
			
			my $invoiceNum = @row[0];
			if($lowestInvoiceNum==0)
			{
				$lowestInvoiceNum = $invoiceNum
			}
			elsif($invoiceNum<$lowestInvoiceNum)
			{
				$lowestInvoiceNum = $invoiceNum
			}
			if($highestInvoiceNum==0)
			{
				$highestInvoiceNum = $invoiceNum
			}
			elsif($invoiceNum>$highestInvoiceNum)
			{
				$highestInvoiceNum = $invoiceNum;
			}
			my $addThis;
			
			for my $i (0..$#row)
			{
				my $thisVal = @row[$i];
				if($i==3)  #patronNumber
				{
					$thisVal = "p$thisVal".calcCheckDigit($self,$thisVal);
				}
				if($i==6)
				{
					while(index($thisVal,'$$')>-1)
					{
						$thisVal =~ s/\$\$/\$/; 
					}
					
					if($thisVal eq "\$")
					{
						$thisVal="";
					}
					
				}
				if($i>11)
				{
					$thisVal =~ s/\.//;
					if($i==12)
					{
						$totalAmt1+=$thisVal;
					}
					if($i==13)
					{
						$totalAmt2+=$thisVal;
					}
					if($i==14)
					{
						$totalAmt3+=$thisVal;
					}
				}
				if($thisVal eq '')
				{
					$thisVal ="(no data)";
				}
				$addThis.=$thisVal.'|';
			}
			push(@output,$addThis);
			$addThis=undef;
		}
		
		if($#output > -1)
		{
			my $datestamp = UnixDate("today", "%Y-%m-%d");
			my $mobiusUtil = new Mobiusutil();
			my $header = "HEADER|";
			$header.=$mobiusUtil->padLeft($recordCount,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt1,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt2,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt3,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt1+$totalAmt2+$totalAmt3,10,'0').'|';
			$header.=$mobiusUtil->padLeft($lowestInvoiceNum,10,'0').'|';
			$header.=$mobiusUtil->padLeft($highestInvoiceNum,10,'0').'|';
			my $dt   = DateTime->now;			
			$header.=substr($dt->year,2,2).$mobiusUtil->padLeft($dt->month,2,'0').$mobiusUtil->padLeft($dt->day,2,'0');
			my @outputFiles = ("bursar.$datestamp.send","bursar.$datestamp.out");
			foreach(@outputFiles)
			{
				my $bursarOut = new Loghandler($outputPath.'/'.$_);
				$bursarOut->deleteFile();
				$bursarOut->addLine($header);
				foreach(@output)
				{
					$bursarOut->addLine(substr($_,0,length($_)-1));
				}
				$log->addLogLine("Outputted $recordCount record(s) into $outputPath/$_");
			}
			
			return 1;
		}
	}
	else
	{
		$log->addLogLine("Bursar - output path does not exist ($outputPath)");
	}
	return 0;
	
 }
 
 sub updateQueryDuration
 {
	my $self = @_[0];
	my $previousTime=@_[1];
	my $query = @_[2];
	my $duration = calcTimeDiff($self,$previousTime);	
	if($self->{'querytime'}<$duration)
	{
		$self->{'querytime'}=$duration;
		$self->{'query'}=$query;
		#print "New long running query: $duration\n";
	}
	return $duration;
 }
 
 sub calcTimeDiff
 {
	my $self = @_[0];
	my $previousTime = @_[1];
	my $currentTime=DateTime->now;
	my $difference = $currentTime - $previousTime;#
	my $format = DateTime::Format::Duration->new(pattern => '%M');
	my $minutes = $format->format_duration($difference);
	$format = DateTime::Format::Duration->new(pattern => '%S');
	my $seconds = $format->format_duration($difference);
	my $duration = ($minutes * 60) + $seconds;
	if($duration==0)
	{
		$duration=1;
	}
	return $duration;
 }
 
 sub calcLimitChange
 {
	my $speedDiff = @_[1];
	my $limit = @_[2];
	my $masterpid = @_[3];
	if($speedDiff > 1) #This means that the previous query ran faster
	{
		$limit-=50;
		#print "Adjusting limit DOWN to $limit\n";
		$masterpid->addLine("Adjusting limit DOWN to $limit");
	}
	elsif($speedDiff < 1) #This means that current query ran faster - let's add more and see what happens next time!
	{
		$limit+=100;
		#print "Adjusting limit UP to $limit\n";
		$masterpid->addLine("Adjusting limit UP to $limit");
	} 
	return $limit;
 }
 
 sub dumpRamToDisk
 {
	my $self = @_[0];
	my %standard = %{$self->{'standard'}};
	my $mobUtil = $self->{'mobiusutil'};
	my $extraInformationOutput = $self->{'toobig'};
	my $couldNotBeCut = $self->{'toobigtocut'};
	my $title=$self->{'title'};
	my @dumpedFiles = @{@_[1]};
	my @newDump=@dumpedFiles;
	if(scalar keys %standard >10000)
	{	
		@newDump=();
		my $recordsInFiles=0;
		if(scalar(@dumpedFiles)>0)
		{
			my $lastElement = scalar(@dumpedFiles);
			$lastElement--;
			for my $i(0..$#dumpedFiles-1)
			{
				push(@newDump,@dumpedFiles[$i]);
			}
			$recordsInFiles=@dumpedFiles[$lastElement];  #The last element contains the total count
			undef @dumpedFiles;
			#print Dumper(@newDump);
		}
		my $log = $self->{'log'};
		my @try = ('nine45','nine07','nine98','specials','standard');
		my @marc = @{getAllMARC($self)};
		my $output;
		
		foreach(@marc)
		{
			my $marc = $_;
			my $count = $mobUtil->marcRecordSize($marc);
			my $addThisone=1;
			if($count>99999) #ISO2709 MARC record is limited to 99,999 octets 
			{
				my @re = @{$mobUtil->trucateMarcToFit($marc)};
				$marc = @re[0];
				$addThisone=@re[1];
				if($addThisone)
				{
					$extraInformationOutput.=$marc->subfield('907',"a");
				}
			}
			if($addThisone) #ISO2709 MARC record is limited to 99,999 octets 
			{
				$marc->encoding( 'UTF-8' );
				$output.=$marc->as_usmarc();
			}
			else
			{	
				$couldNotBeCut.=$marc->subfield('907',"a");
			}
		}
		if(length($title)>0)
		{
			$title=$title."_";
		}
		my $fileName = $mobUtil->chooseNewFileName("/tmp/temp",$title."tempmarc","mrc");
		my $marcout = new Loghandler($fileName);
		$marcout->addLine($output);
		push(@newDump, $fileName);
		my $addedToDisk = scalar keys %standard;
		$recordsInFiles+=$addedToDisk;
		push(@newDump, $recordsInFiles);
		foreach(@try)
		{
			my %n = ();
			undef $self->{$_};
			$self->{$_} = \%n;
		}
	}
	#print Dumper(\@newDump);
	$self->{'toobig'} = $extraInformationOutput;
	$self->{'toobigtocut'} = $couldNotBeCut;
	return \@newDump;
 }
 
 sub getTooBigList
 {
	my $self = @_[0];
	my @ret = ($self->{'toobig'},$self->{'toobigtocut'});
	return \@ret;
 }
 
 1;
 
 