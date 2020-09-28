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
    my @i=();
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
		'title' => "",
		'rps' => 0,
		'pathtothis' =>"",
		'conffile' =>"",
		'recordcount' => 0,
		'maxdbconnection' => 3,
        'current_query' => '',
        'query_log' => \@i
	};
	
	my $t = shift;
	my $title = shift;
	$self->{'pathtothis'} = shift;
	$self->{'conffile'} = shift;
	my $m = shift;
	my $launch = shift;
	if(!defined $launch)
	{
		$launch = 1;
	}
	if($launch)
	{
		if($m)
		{
			$self->{'maxdbconnection'} = $m;
		}
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
		figureSelectStatement($self);
		my $max = findMaxRecordCount($self,$self->{'selects'});
		#print "Max calc: $max\n";
		if(($t) && ($t ne 'thread') && ($max > 5000))
		{
			gatherDataFromDB_spinThread_Controller($self);
		}
		elsif(($t) && ($t eq 'full'))
		{		
			gatherDataFromDB_spinThread_Controller($self);
		}
		elsif(($t) && ($t eq 'thread'))
		{
			my $cou = spinThread($self);
			$self->{'recordcount'} = $cou;
		}	
		else
		{
			gatherDataFromDB($self);
		}
		$pidfile->deleteFile();
	}
	else
	{
		bless $self, $class;
	}
    return $self;
 }
 
 sub gatherDataFromDB
 {
	my $self = @_[0];
	my $previousTime = DateTime->now();
	$self->{'selects'} =~ s/\$recordSearch/SIERRA_VIEW.BIB_RECORD.RECORD_ID/gi;
	stuffStandardFields($self);
	stuffSpecials($self);
	stuff945($self);
	stuff907($self);
	stuff998alternate($self);
	stuffLeader($self);
	my $secondsElapsed = calcTimeDiff($self,$previousTime);
	if($secondsElapsed < 1)
	{
		$secondsElapsed = 1;
	}
	my %standard = %{$self->{'standard'}};
	my $recordCount = scalar keys %standard;
	$self->{'rps'} = $recordCount / $secondsElapsed;
 }
 
 sub threadDone
 {
	my $pidFile = @_[0];
	#print "Starting to read pid file\n";
	my $pidReader = new Loghandler($pidFile);
	my @lines = @{ $pidReader->readFile() };
	#print "Done reading Pid\n";
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
 
 sub spinThread
 {
	my $self = @_[0];
	my $mobUtil = $self->{'mobiusutil'};
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my $selects = $self->{'selects'};
	my $pidfile = $self->{'pidfile'};	
	my $previousTime=DateTime->now;
	#print "Thread starting\n";
	$self->{'selects'}  = $self->{'bibids'};
	#print "stuffStandardFields\n";
	stuffStandardFields($self);
	#print "stuffSpecials\n";
	stuffSpecials($self);
	#print "stuff945\n";
	stuff945($self);
	#print "stuff907\n";
	stuff907($self);
	#print "stuff998alternate\n";
	stuff998alternate($self);
	#print "stuffLeader\n";
	stuffLeader($self);
	#print "Done stuffing\n";
	my $secondsElapsed = calcTimeDiff($self,$previousTime);
	#print "time = $secondsElapsed\n";
	my %standard = %{$self->{'standard'}};
	my $currentRecordCount = scalar keys %standard;
	#print "currentRecordCount = $currentRecordCount\n";
	my @dumpedFiles = (0);
	@dumpedFiles = @{dumpRamToDisk($self, \@dumpedFiles,1)};
	$self->{'diskdump'}=\@dumpedFiles;
	#print "Dumped files\n";
	return $currentRecordCount;
 }
 
 sub getLastQuery
 {
    my $self = shift;
    return $self->{'current_query'};
 }
 
 sub getQueryLog
 {
    my $self = shift;
    return $self->{'query_log'};
 }
  
 sub gatherDataFromDB_spinThread_Controller
 {
	my $self = @_[0];
	#This file is written to by each of the threads to debug the database ID's selected for each thread
	my $rangeWriter = new Loghandler("/tmp/rangepid.pid");
	$rangeWriter->deleteFile();
	my $dbUserMaxConnection=$self->{'maxdbconnection'};
	my $mobUtil = $self->{'mobiusutil'};
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my $selects = $self->{'selects'};
	my $pidfile = $self->{'pidfile'};
	my $pathtothis = $self->{'pathtothis'};
	my $conffile = $self->{'conffile'};
	my $conf = $mobUtil->readConfFile($conffile);
	my %conf = %{$conf};
	my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
	my %dbUserTrack = ();
	my @recovers;
	my $i=0;
	foreach(@dbUsers)
	{
		$dbUserTrack{$_}=0;
		$i++;
	}
	$dbUserTrack{@dbUsers[0]}=1;
	
	my @cha = split("",$selects);
	my $tselects = "";	
	my $chunks = 0;
	my $zeroAdded = 0;
	my $chunkGoal = 100;
	my $title = $self->{'title'};
	my $masterfile = new Loghandler($mobUtil->chooseNewFileName('/tmp',"master_$title",'pid'));
    print "NOTICE: see progress with 'watch \"cat " . $masterfile->getFileName() . "\"'\n";
	my $previousTime=DateTime->now;
	foreach(@cha)
	{
		$tselects.=$_;
	}
	
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
	my $maxQuery = $tselects;
	$max = findMaxRecordCount($self,$maxQuery);
	
	my @dumpedFiles = (0);
	my $finishedRecordCount=0;
	my @threadTracker = ();
	my $userCount = scalar @dbUsers;
	#print Dumper(\@dbUsers);
	#print Dumper(\%dbUserTrack);
	#print "$userCount users\n";
	my $threadsAllowed = $dbUserMaxConnection * (scalar @dbUsers);
	my $threadsAlive=1;
	my $offset = $min;
	my $increment = $min+$chunkGoal;
	my $slowestQueryTime = 0;
	my $rps = 0;
	my $range=0;
	my $recordsCollectedTotalPerLoop=0;
	my $recordsCollectedStale=0;
	while($threadsAlive)
	{
		#print "Starting main Thread loop\n";
		my $workingThreads=0;
		my @newThreads=();
		my $threadJustFinished=0;
		#print Dumper(\@threadTracker);
		#print "Looping through the threads\n";
		$recordsCollectedTotalPerLoop = $finishedRecordCount;
		foreach(@threadTracker)
		{
			#print "Checking to see if thread $thisPidfile is done\n";
			my @attr = @{$_};
			my $thisPidfile = @attr[0];
			my $thisOff = @attr[1];
			my $thisInc = @attr[2];
			my $checkcount = @attr[3];
			@attr[3]++;
			my $duser = @attr[4];
			my $continueChecking=1;
			# print "$thisPidfile $thisOff $thisInc: $checkcount\n";
			#give thread time to get started and create pidfile (40 seconds)
			if($checkcount > 20)
			{
				my $abandonThread=0;
				my $splitChunk=0;
				unless (-e $thisPidfile)
				{
					$abandonThread=1;					
				}
				if((-e $thisPidfile) && ($checkcount>1200))
				{
					$abandonThread=1;
					$splitChunk=1;
				}
				if($abandonThread)
				{
					# Split the chunk because it too so long for it to finish
					if($splitChunk)
					{
						print "Splitting Chunk $thisOff - $thisInc \n";
						my $dif = $thisInc - $thisOff;
						print "dif: $dif\n";
						my $newd = int($dif/2) + $thisOff;
						print "newd: $newd\n";
						my @add = ($thisOff,$newd);						
						print "add: $thisOff , $newd\n";
						push(@recovers,[@add]);
						$newd++;
						my @add = ($newd,$thisInc);
						print "add: $newd , $thisInc\n";
						push(@recovers,[@add]);
						my @fil = split('/',$thisPidfile);
						my $kill = @fil[$#fil];
						print "kill \$(ps aux | grep '$kill' | grep -v 'grep' | awk '{print \$2}')\n";
						system("kill \$(ps aux | grep '$kill' | grep -v 'grep' | awk '{print \$2}')");						
						unlink $thisPidfile;
                        undef @add;
					}
					else
					{
						my @add = ($thisOff,$thisInc);
						push(@recovers,[@add]);
                        undef @add;
					}
					if($dbUserTrack{$duser})
					{
						$dbUserTrack{$duser}--;
					}
					$threadJustFinished=1;
					$continueChecking=0;
				}
			}
			
			if($continueChecking)
			{
				my $done = threadDone($thisPidfile);
				if($done)
				{
					#print "$thisPidfile Thread Finished.... Cleaning up\n";
					$threadJustFinished=1;				
					my $pidReader = new Loghandler($thisPidfile);				
					my @lines = @{ $pidReader->readFile() };				
					$pidReader->deleteFile();
					
					undef $pidReader;
					if(scalar @lines >6)
					{
						@lines[0] =~ s/\n//; # Output marc file location
						@lines[1] =~ s/\n//; # Total Records Gathered
						@lines[2] =~ s/\n//; # $self->{'toobig'} = $extraInformationOutput;
						@lines[3] =~ s/\n//; # $self->{'toobigtocut'}					
						@lines[4] =~ s/\n//; # Slowest Query Time
						@lines[5] =~ s/\n//; # Chunk Size
						@lines[6] =~ s/\n//; # DB Username
						@lines[7] =~ s/\n//; # Execute Time in Seconds
						my $dbuser = @lines[6];
						if(@lines[8])
						{
							@lines[8] =~ s/\n//;
						}
						if(scalar @lines >8 && @lines[8]==1)
						{
							#print "************************ RECOVERING ************************\n";
							
							#print "This thread died, going to restart it\n";
							#This thread failed, we are going to try again (this is usually due to a database connection)
							@lines[9] =~ s/\n//;
							@lines[10] =~ s/\n//;
							#print Dumper(\@lines);
							my $off = @lines[9];
							my $inc = @lines[10];
							my @add = ($off,$inc);
							push(@recovers,[@add]);
							if($dbUserTrack{$dbuser})
							{
								$dbUserTrack{$dbuser}--;
							}
							my $check = new Loghandler(@lines[0]);
							if($check->fileExists())
							{
								#print "Deleting @lines[0]\n";
								$check->deleteFile();
							}
							#print "Done recovering\n";
						}
						else
						{
							#print "Completed thread success, now cleaning\n";
							if(@lines[1] == 0)
							{
								$zeroAdded++;
								$max = findMaxRecordCount($self,$maxQuery);
								print "Got 0 records $zeroAdded times\n";
								if($zeroAdded>1200) #we have looped 2400 times (20 minutes) and not a single record added to the collection. Time to quit.
								{
									$finishedRecordCount = $max;
								}
							}
							else
							{
								$zeroAdded=0;
							}
							
							$dbUserTrack{$dbuser}--;
							if(@lines[1] !=0)
							{
								$self->{'toobig'}.=@lines[2];
								$self->{'toobigtocut'}.=@lines[3];
								if(@lines[7]<1)
								{
									@lines[7]=1;
								}
								my $trps = @lines[1] / @lines[7];
								#print "Performed math\n";
								if($rps < $trps-1)
								{
									$chunkGoal+=100;
								}
								elsif($rps > $trps+1)
								{
									$chunkGoal-=100;
								}
								if($chunkGoal<1)
								{
									$chunkGoal=10;
								}
								if(@lines[4] > 280)
								{
									$chunkGoal=10;
								}
								$rps = $trps;
                                $rps =~ s/^([^\.]*\.?\d{3}?).*/$1/g;
                                $rps += 0; # back to numeric
								#print "Adjusted chunk to $chunkGoal\n";
								push(@dumpedFiles,@lines[0]);
								#print "Added dump files to array\n";
								$finishedRecordCount += @lines[1];
								#print "Added dump count to total\n";
								#print Dumper(\@dumpedFiles);
							}
						}
					}
					else
					{
						print "For some reason the thread PID file did not output the expected stuff\n";
					}
					#print "Looping back through the rest of running threads\n";
                    undef @lines;
				}
				else
				{
					#print "Thread not finished, adding it to \"running\"\n";
					$workingThreads++;
					push(@newThreads,[@attr]);
				}
                undef $done;
			}
            undef @attr;
			undef $thisPidfile;
			undef $thisOff;
			undef $thisInc;
			undef $checkcount;
			undef $duser;
			undef $continueChecking;
		}
		@threadTracker=@newThreads;
		#print "$workingThreads / $threadsAllowed Threads\n";
		
		#Figure out if total collected records is the same as last time
		#Count the number of times that the number of collected records are the same
		if($finishedRecordCount==$recordsCollectedTotalPerLoop)
		{
			$recordsCollectedStale++;
		}
		else
		{
			$recordsCollectedStale=0;
		}
		
		if($workingThreads<($threadsAllowed-1))
		{
			if(!$threadJustFinished)
			{
				my $pidFileNameStart=int(rand(10000));
				if($finishedRecordCount<$max)
				{
					my $loops=0;
					while ($workingThreads<($threadsAllowed-1))#&& ($finishedRecordCount+($loops*$chunkGoal)<$max))
					{
						$loops++;
						my $thisOffset = $offset;
						my $thisIncrement = $increment;	
						my $choseRecover=0;						
						my $dbuser = "";
						my $keepsearching=1;
						#print "Searching for an available userid\n";
						#print Dumper(\%dbUserTrack);
						while (((my $internal, my $value ) = each(%dbUserTrack)) && $keepsearching)
						{
							if($value<$dbUserMaxConnection)
							{
								$keepsearching=0;
								$dbuser=$internal;
								$dbUserTrack{$dbuser}++;
								#print "$dbuser: $value\n";
							}
						}
						if($dbuser ne "")
						{	
							if((scalar @recovers) == 0)
							{
								# print "Sending off for range min: $thisOffset\n";
                                $thisOffset = calcDBMinID($self,$thisOffset,$dbHandler,$tselects);
                                # print "got min: $thisOffset\n";
								$thisIncrement = calcDBRange($self,$thisOffset,$chunkGoal,$dbHandler,$tselects);
								#print "Got range: $thisIncrement\n";
							}
							else
							{
								print "There are some threads that died, so we are using those ranges for new threads\n";
								$choseRecover=1;
								$thisOffset = @{@recovers[0]}[0];
								$thisIncrement = @{@recovers[0]}[1];
								my $test = $thisIncrement - $thisOffset;
								if($test<0)
								{
									print "NEGATIVE RANGE:\n$thisOffset\n$thisIncrement\n";
								}
								shift(@recovers);
							}
							$range=$thisIncrement-$thisOffset;
							#print "Starting new thread\n";
							#print "Max: $max   From: $thisOffset To: $thisIncrement\n";
							my $thisPid = $mobUtil->chooseNewFileName("/tmp",$pidFileNameStart,"sierrapid");
							my $ty = $self->{'type'};
							#print "Spawning: $pathtothis $conffile thread $thisOffset $thisIncrement $thisPid $dbuser $ty\n";
							system("$pathtothis $conffile thread $thisOffset $thisIncrement $thisPid $dbuser $ty &");
							my @ran = ($thisPid,$thisOffset,$thisIncrement,0,$dbuser);
							push(@threadTracker,[@ran]);
							#print "Just pushed thread onto stack\n";
							$pidFileNameStart++;
							if(!$choseRecover)
							{
								$offset=$thisIncrement;
								$increment=$thisIncrement;
							}
						}
						else
						{
							#print "Could not find an available db user - going to have to wait\n";
						}
						$workingThreads++;
						#print "End of while loop for $workingThreads< ( $threadsAllowed - 1 )\n";
                        undef $thisOffset;
						undef $thisIncrement;
						undef $choseRecover;
						undef $dbuser;
						undef $keepsearching;
					}
                    undef $loops;
				}
				else
				{
					print "We have reached our target record count... script is winding down\n";
				}
			}
		}
		
		#stop this nonsense - we have looped 1200 times and not increased our records!  1200 loops * 2 seconds per loop = 40 minutes
		if($recordsCollectedStale>1200)
		{
			$threadsAlive=0;
		}
		
		if($workingThreads==0 && !$threadJustFinished)
		{
			$threadsAlive=0;
		}
		my $secondsElapsed = calcTimeDiff($self,$previousTime);
		my $minutesElapsed = $secondsElapsed / 60;
		my $overAllRPS = $finishedRecordCount / $secondsElapsed;
        $overAllRPS =~ s/^([^\.]*\.?\d{3}?).*/$1/g;
        $minutesElapsed =~ s/^([^\.]*\.\d{3}).*/$1/g;
		my $devideTemp = $overAllRPS;
		if($devideTemp<1)
		{
			$devideTemp=1;
		}
        $devideTemp =~ s/^([^\.]*\.?\d{3}?).*/$1/g;
		
		my $remaining = ($max - $finishedRecordCount) / $devideTemp / 60;
        $remaining =~ s/^([^\.]*\.?\d{3}?).*/$1/g;
		$self->{'rps'}=$overAllRPS;
		$masterfile->truncFile($pidfile->getFileName);
		$masterfile->addLine("$rps records/s Per Thread\n$overAllRPS records/s Average\nChunking: $chunkGoal\nRange: $range\n$remaining minutes remaining\n$minutesElapsed minute(s) elapsed\n");
		$masterfile->addLine("Records On disk: $finishedRecordCount,\nNeed: $max  \n");
		$masterfile->addLine("Loops with no records: $recordsCollectedStale");
		$masterfile->addLine("Database User Utalization:");
		$masterfile->addLine(Dumper(\%dbUserTrack));
		if((scalar @recovers)>0)
		{
			$masterfile->addLine("Recovering these ranges:");
			$masterfile->addLine(Dumper(\@recovers));
		}
		
		#print "$rps records/s Current\n$overAllRPS records/s Average\nChunking: $chunkGoal\nRange: $range\nRecords On disk: $finishedRecordCount,\nNeed: $max  Searching: $offset To: $increment\n";
		sleep(2);
	}
	$self->{'diskdump'}=\@dumpedFiles;
	$masterfile->deleteFile();
 }
 
 sub findMaxRecordCount
 {
	my $self = @_[0];
	my $mm = @_[1];
	my @cha = split("",$mm);
	my $maxQuery;
	foreach(@cha)
	{
		$maxQuery.=$_;
	}
	$maxQuery =~ s/\$recordSearch/COUNT(DISTINCT SIERRA_VIEW\.BIB_RECORD\.RECORD_ID)/gi;

	my $dbHandler = $self->{'dbhandler'};
	my $max = 0;
	my @results = @{$dbHandler->query($maxQuery)};
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		$max = @row[0];
	}
    return $max;
 }
 
 sub calcDBRange
 {
	#print "starting rangefinding\n";
	my $self = @_[0];
	my $thisOffset = @_[1];	
	my $chunkGoal = @_[2];
	my $dbHandler = @_[3];
	my $countQ = @_[4];
	my $previousTime=DateTime->now;
	my $thisIncrement = $thisOffset;
	
	$countQ =~s/\$recordSearch/COUNT(DISTINCT SIERRA_VIEW\.BIB_RECORD\.RECORD_ID)/gi;
	my $yeild=0;
	if($chunkGoal<1)
	{
		$chunkGoal=1;
	}
	$thisIncrement+=$chunkGoal;
	my $trys = 0;
	while($yeild<$chunkGoal)  ## Figure out how many rows to read into the database to get the goal number of records
	{	
		my $selects = $countQ." AND SIERRA_VIEW.BIB_RECORD.ID > $thisOffset AND SIERRA_VIEW.BIB_RECORD.ID <= $thisIncrement";
		# print "$selects\n";
		my @results = @{$dbHandler->query($selects)};
		foreach(@results)
		{
			my $row = $_;
			my @row = @{$row};
			$yeild = @row[0];
		}
		# print "Yeild: $yeild\n";
		if($yeild<$chunkGoal)
		{
			$trys++;
			if($trys>5)	#well, 100 * 10 and we didn't get 1000 rows returned, so we are stopping here.
			{
				$yeild=$chunkGoal;
			}
			$thisIncrement+=$chunkGoal+($trys*$chunkGoal);
		}
	}
	my $secondsElapsed = calcTimeDiff($self,$previousTime);
	#print "Range Finding: $secondsElapsed after $trys trys\n";
	
	#print "ending rangefinding\n";
	return $thisIncrement;
 }
 
 sub calcDBMinID
 {
    my $self = @_[0];
	my $thisOffset = @_[1];
	my $dbHandler = @_[2];
	my $countQ = @_[3];
    my $previousTime=DateTime->now;
	my $thisIncrement = $thisOffset;
	$countQ =~s/\$recordSearch/MIN(SIERRA_VIEW\.BIB_RECORD\.RECORD_ID)/gi;
    my $min = 1;
    my $selects = $countQ." AND SIERRA_VIEW.BIB_RECORD.ID >= $thisOffset";
    my @results = @{$dbHandler->query($selects)};
    foreach(@results)
    {
        my $row = $_;
        my @row = @{$row};
        $min = @row[0];
    }
    $min = $thisOffset + 1  if($min !=~ m/^[^\d]/); # Failsafe

	my $secondsElapsed = calcTimeDiff($self,$previousTime);
	return ($min--);
 }
 
 sub getRecordCount
 {
	my $self = @_[0];
	return $self->{'recordcount'};
 }
 
 sub getDiskDump
 {
	my $self = @_[0];
	return $self->{'diskdump'};
 }
 
 sub getSpeed
 {
	my $self = @_[0];
	return $self->{'querytime'};
 }
 
 sub getRPS
 {
	my $self = @_[0];
	return $self->{'rps'};
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
    recordQuery($self, $query);
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
    recordQuery($self, $query);
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
    recordQuery($self, $query);
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
svbr.id,
sviv.id,
concat('|g',sviv.copy_num) as \"g\",
concat('|i',regexp_replace(sviv.barcode,'\\|','','g')) as \"i\",
concat('|j',sviv.agency_code_num) as \"j\",
concat('|l',regexp_replace(sviv.location_code,'\\|','','g')) as \"l\",
concat('|o',regexp_replace(sviv.icode2,'\\|','','g')) as \"o\",
concat('|p\$',trim(to_char(sviv.price,'9999999999990.00'))) as \"p\",
concat('|q',regexp_replace(sviv.item_message_code,'\\|','','g')) as \"q\",
concat('|r',regexp_replace(sviv.opac_message_code,'\\|','','g')) as \"r\",
concat('|s',regexp_replace(sviv.item_status_code,'\\|','','g')) as \"s\",
concat('|t',sviv.itype_code_num) as \"t\",
concat('|u',sviv.checkout_total) as \"u\",
concat('|v',sviv.renewal_total) as \"v\",
concat('|w',sviv.year_to_date_checkout_total) as \"w\",
concat('|x',sviv.last_year_to_date_checkout_total) as \"x\",
concat('|z',to_char(min(mvrm.creation_date_gmt), 'mm-dd-yy')) as \"z\"
from 
sierra_view.item_view sviv
left join SIERRA_VIEW.record_metadata mvrm on (mvrm.record_num=sviv.record_num AND mvrm.record_type_code='i'),
sierra_view.bib_record svbr,
sierra_view.bib_record_item_record_link svbrir,
(
	$selects
) 
as selects
WHERE 
svbr.record_id = selects.record_id AND
svbrir.bib_record_id=svbr.id AND
sviv.id=svbrir.item_record_id
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
";
    my $pidfile = $self->{'pidfile'};
	$pidfile->truncFile($query);
    recordQuery($self, $query);
	#print "$query\n";
	my $previousTime=DateTime->now;	
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	my %tracking; # links recordItems objects to item Numbers without having to search everytime
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		
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
		foreach my $b (2..$#row)
		{
			$all = $all.@row[$b];
		}
		push(@{$nineHundreds{$recordID}},new recordItem('945',' ',' ',$all));
		
	}

	# $query = "
     # SELECT
        # svvv.record_id,
        # svvv.varfield_type_code,
        # svvv.marc_tag,
        # svvv.field_content,
        # svbr.id as \"BIB_ID\",
        # svvv.record_num
        # FROM 
        # sierra_view.varfield_view svvv,
        # sierra_view.bib_record svbr,
        # (
            # $selects
        # ) as selects
         # WHERE
        # selects.record_id = svvv.record_id and
        # svvv.record_id = svbr.record_id and
        # varfield_type_code !='a'
        # ORDER BY 1";
	# $pidfile->truncFile($query); 
	# #print "$query\n";
    # recordQuery($self, $query);
	# my $previousTime=DateTime->now;		
	# @results = @{$dbHandler->query($query)};
	# updateQueryDuration($self,$previousTime,$query);
	# my $outterp = 0;
	# my $startSection=0;
	# while($outterp<=$#results)
	# {
		# my $row = @results[$outterp];
		# my @row = @{$row};
		# my $trimmedID = $mobiusUtil->trim(@row[2]);
		# if(exists $nineHundreds{@row[4]})
		# {
			# my @thisArray = @{$nineHundreds{@row[4]}};
			# if(exists ${$tracking{@row[4]}}{@row[0]})
			# {
				# my $thisArrayPosition = ${$tracking{@row[4]}}{@row[0]};				
				# if(($trimmedID eq '082') || ($trimmedID eq '090') || ($trimmedID eq '086') || ($trimmedID eq '099') || ($trimmedID eq '866') || ($trimmedID eq '050') || ($trimmedID eq '912') || ($trimmedID eq '900') || ($trimmedID eq '927') || ($trimmedID eq '926') || ($trimmedID eq '929') || ($trimmedID eq '928') || ($trimmedID eq '060'))
				# {
				
					# my $thisRecord = @thisArray[$thisArrayPosition];
					# $thisRecord->addData(@row[3]);
					# my $checkDigit = calcCheckDigit($self,@row[5]);
					# my $barcodeNum = "i".@row[5].$checkDigit;
					# $thisRecord->addData("|y.$barcodeNum");
					# my $recordID = @row[4];
					# my $subItemID = @row[0];
					# my $foundMatch=0;
					# my $pointer=$startSection;
					# while($pointer<=$#results)# Find Null marc_tag values related to 082,090,086,099,866,050,912,900,927,926,929,928,060
					# {
						# my $rowsearch = @results[$pointer];
						# my @rowsearch = @{$rowsearch};
						# if(@rowsearch[3] ne '')
						# {
							# #print "@rowsearch[0] == @row[0]\n";
							# if(@rowsearch[0] == @row[0]) 
							# {
								# #print "$pointer / $#results\n";
								# $foundMatch=1;
								# if(@rowsearch[2] eq '')
								# {	
									# my $firstChar = substr($rowsearch[3],0,1);
									# if((@rowsearch[1] eq 'b') && ($firstChar ne '|'))
									# {
										# $thisRecord->addData('|i'.@rowsearch[3]);
									# }
									# elsif((@rowsearch[1] eq 'v') && ($firstChar ne '|'))
									# {
										# $thisRecord->addData('|c'.@rowsearch[3]);
									# }
									# elsif((@rowsearch[1] eq 'x') && ($firstChar ne '|'))
									# {
										# $thisRecord->addData('|n'.@rowsearch[3]);
									# }
									# elsif((@rowsearch[1] eq 'm') && ($firstChar ne '|'))
									# {
										# $thisRecord->addData('|m'.@rowsearch[3]);
									# }
									# elsif((@rowsearch[1] eq 'c') && ($firstChar eq '|'))
									# {
										# $thisRecord->addData(@rowsearch[3]);
									# }
									# elsif((@rowsearch[1] eq 'v') && ($firstChar eq '|'))
									# {
										# $thisRecord->addData(@rowsearch[3]);
									# }
									# elsif((@rowsearch[1] eq 'd') && ($firstChar eq '|'))
									# {
										# $thisRecord->addData(@rowsearch[3]);
									# }
									# else
									# {
										# if((@rowsearch[1] ne 'n') && (@rowsearch[1] ne 'p')&& (@rowsearch[1] ne 'r'))
										# {
											# $log->addLogLine("Related 082,090,086,099,866,050,912,900,927,926,929,928,060 item(".@row[0].") bib($recordID) barcode($barcodeNum) value omitted: ".@rowsearch[1]." = ".@rowsearch[3]);
										# }
									# }
								# }								
							# }
							# elsif($foundMatch)#stop looping because it has found all related rows (they are sorted as per the order clause in the query)
							# {
								# $outterp=$pointer-2;
								# $startSection=$pointer;
								# $pointer=$#results+1;
								
							# }
						# }
						# $pointer++;
					# }
					# @{$nineHundreds{@row[4]}}[$thisArrayPosition] = $thisRecord;
				# }
				# elsif( $trimmedID ne '')
				# {
					# $log->addLogLine(@row[4]." not added \"$trimmedID\" = ".@row[3]);
					# #push(@{$nineHundreds{@row[4]}},new recordItem(@row[2],'','',@row[3]));;
				# }
			# }
			# else
			# {
				# if(@row[2] eq '086')
				# {
					# $log->addLogLine("I found a row and it looks like this \"$trimmedID\" = ".@row[3]);
					# $log->addLogLine("I'm adding that as a 945");
					# push(@{$nineHundreds{@row[4]}},new recordItem('945','','',@row[3]));
				# }
				# else
				# {
					# $log->addLogLine("945 scrape: Strange results: ".@row[0]." ".@row[1]." ".@row[2]." ".@row[3]." ".@row[4]);
				# }
			# }
			
		# }
		# else
		# {
			# $log->addLogLine("There were items in varfield_view that didn't appear before now:");
			# $log->addLogLine("Bib id  = ".@row[4]." Item id = ".@row[0].",$trimmedID = ".@row[3]);
			# $log->addLogLine("This was not added to the marc array");
		# }
		# $outterp++;
	# }
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
    recordQuery($self, $query);
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
	# print "$query\n";
    recordQuery($self, $query);
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
    recordQuery($self, $query);
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
	if(0)#$self->{'type'} ne 'full')
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
		#print "Creating MARC for $recID\n";
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
	my @ret;
	my @marcout;
	
	#format memory into marc
	while ((my $internal, my $value ) = each(%standard))
	{
		push(@marcout,getSingleMARC($self,$internal));
	}
	push(@ret,[@marcout]);
	#look for any dumped files and read those into the array
	#print "Checking to see if it's array";
	#print ref $dumpedFiles;
	#print "\n";
	if(ref $dumpedFiles eq 'ARRAY')
	{
		my @dumpedFiles = @{$dumpedFiles};
		push(@ret,[@dumpedFiles]);
		#print Dumper(\@dumpedFiles);
		# foreach(@dumpedFiles)
		# {	
			# my $marcfile = $_;
			# my $check = new Loghandler($marcfile);
			# if($check->fileExists())
			# {
				# my $file = MARC::File::USMARC->in( $marcfile );
				# my $r =0;
				# while ( my $marc = $file->next() ) 
				# {						
					# $r++;
					# push(@marcout,$marc);
				# }
				# print "Read $r records from $_\n";
				# $check->deleteFile();
			# }
		# }
	}
	return \@ret;
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
 
 sub getBridgesFiscalInfo
 {
	my $self = @_[0];
	my $selects = $self->{'selects'};
	my $log = $self->{'log'};
	my $dbHandler = $self->{'dbhandler'};
	my $outputPath = @_[1];


    my $dt   = DateTime->now;			

    # Useful for testing.
	# my $dt = DateTime->new(
	#     year       => 2018,
	#     month      => 07,
	#     day        => 31,
	#     hour       => 16,
	#     minute     => 12,
	#     second     => 47,
	#     nanosecond => 500000000,
	#     time_zone  => 'US/Central',
	# );

	my $ymd    = $dt->ymd; 

    my $cyear  = $dt->year;
    my $cmonth = $dt->month;
    my $fy = '';
    if ($cmonth >= 6) {
       $fy = $cyear.'-06-01' 
    }
    else {
       $fy = ($cyear-1).'-06-01';
    }



	my $query = '';
	if(-d $outputPath)
	{
		$query = "SELECT 
			i.invoice_number_text        AS \"invoice_number\",
			il.vendor_code            AS \"vendor\",
			i.subtotal_amt            AS \"subtotal\",
			i.grand_total_amt        AS \"grand_total\",
			i.shipping_amt            AS \"shipping\",
			il.paid_amt            AS \"paid\",
			i.record_creation_date_gmt    AS \"invoice_date\",
			i.record_type_code        AS \"record_type\",
			i.record_num            AS \"record_number\",
			i.posted_date_gmt        AS \"posted_date\",
			il.title            AS \"title\"
			FROM sierra_view.invoice_view i
			JOIN sierra_view.invoice_record ir ON ir.record_id = i.id
			JOIN sierra_view.invoice_record_line il ON il.invoice_record_id = ir.record_id
			WHERE ir.accounting_unit_code_num = '9'
			AND ir.posted_data_gmt BETWEEN '".${fy}."' AND '".${ymd}."'
			ORDER BY i.record_num
			";

			$log->addLogLine($query);
		my @results = @{$dbHandler->query($query)};		
		my @output;
		my $recordCount = 0;
		
		foreach(@results)
		{
			$recordCount++;
			my $row = $_;
			my @row = @{$row};
			
			my $addThis;
			
			for my $i (0..$#row)
			{
				my $thisVal = @row[$i];
					
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
			my $header = "invoice_number|vendor|subtotal|grand_total|shipping|paid|invoice_date|record_type|record_num|posted_date|title";
			my $dt   = DateTime->now;			
			my @outputFiles = ("bridgesFiscal.$datestamp.csv");
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
		$log->addLogLine("bridgesFiscal - output path does not exist ($outputPath)");
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
    my $format = DateTime::Format::Duration->new(pattern => '%D');
	my $days = $format->format_duration($difference);
	$format = DateTime::Format::Duration->new(pattern => '%M');
	my $minutes = $format->format_duration($difference);
	$format = DateTime::Format::Duration->new(pattern => '%S');
	my $seconds = $format->format_duration($difference);
	my $duration = ($days * 86400) + ($minutes * 60) + $seconds;
	if($duration<.1)
	{
		$duration=.1;
	}
    $duration += ''; # Making it a string
    if($duration !=~ m/\./) # putting a decimal point if none exists
    {
        $duration .= ".000";
    }
    $duration =~ s/^([^\.]*\.\d{3}).*/$1/g;
	return $duration;
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
	my $threshHold = @_[2];
	my @newDump=@dumpedFiles;
    my $previousTime = DateTime->now();
	if(scalar keys %standard >$threshHold)
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
		#print "Getting all marc\n";
		my @both = @{getAllMARC($self)};
		my @marc = @{@both[0]};
		my $files = @both[1];
		if(ref $files eq 'ARRAY')
		{
			print "There should not be any files here but there are:\n";
			my @files = @{$files};
			foreach(@files)
			{
				print "$_\n";
			}
		}
		#print Dumper(@marc);
		#print "Got em\n";
		my $output;
		
		foreach(@marc)
		{
			#print "Loop through marc record";
			my $marc = $_;
			my $count = $mobUtil->marcRecordSize($marc);
			#print "Got size\n";
			my $addThisone=1;
			if($count>99999) #ISO2709 MARC record is limited to 99,999 octets 
			{
				print "it's over 99999\n";	
				my @re = @{$mobUtil->trucateMarcToFit($marc)};
				$marc = @re[0];
				$addThisone=@re[1];
				if($addThisone)
				{
					print "Extrainfo Before: $extraInformationOutput\n";
					$extraInformationOutput.=$marc->subfield('907',"a");
					print "Extrainfo After: $extraInformationOutput\n";
				}
			}
			if($addThisone) #ISO2709 MARC record is limited to 99,999 octets 
			{
				#print "About to set encoding\n";
				$marc->encoding( 'UTF-8' );
				#print "About to add it to output\n";
				$output.=$marc->as_usmarc();
				#print "Added it\n";
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
		#print "Decided on $fileName \n";	
		my $marcout = new Loghandler($fileName);
		$marcout->appendLine($output);
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
    my $secondsElapsed = calcTimeDiff($self,$previousTime); ## Timed this, consistently .1 seconds
    # print "Dumpram: $secondsElapsed\n";
	return \@newDump;
 }
 
 sub getTooBigList
 {
	my $self = @_[0];
	my @ret = ($self->{'toobig'},$self->{'toobigtocut'});
	return \@ret;
 }
 
 sub recordQuery
 {
    my $self = shift;
    my $query = shift;
    my @qlog = @{$self->{'query_log'}};
    push @qlog, $query;
    $self->{'query_log'} = \@qlog;
    $self->{'current_query'} = $query;
 }
 
 1;
 
 
