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

package sierraSpecialb;
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
		'title' => "",
		'rps' => 0,
		'pathtothis' =>"",
		'conffile' =>"",
		'recordcount' => 0,
		'maxdbconnection' =>3
	};
	
	my $t = shift;
	my $title = shift;
	$self->{'pathtothis'} = shift;
	$self->{'conffile'} = shift;
	my $m = shift;
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
	my $max = findMinMaxRecordCount($self,$self->{'selects'},"count");
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
    return $self;
 }
 
 sub gatherDataFromDB
 {
	my $self = @_[0];
	my $previousTime = DateTime->now();	
	$self->{'selects'} =~ s/\$recordSearch/RECORD_ID/gi;
	$self->{'selects'} =~ s/\$rangestatement_id//gi;
	$self->{'selects'} =~ s/\$rangestatement_ITEM_RECORD_ID//gi;
	$self->{'selects'} =~ s/\$rangestatement_RECORD_ID//gi;
	stuffStandardFields($self);
	# stuffSpecials($self);
	# stuff945($self);
	# stuff907($self);
	# stuff998alternate($self);
	# stuffLeader($self);
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
	#stuffSpecials($self);
	#print "stuff945\n";
	#stuff945($self);
	#print "stuff907\n";
	#stuff907($self);
	#print "stuff998alternate\n";
	#stuff998alternate($self);
	#print "stuffLeader\n";
	#stuffLeader($self);
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
	my $chunkGoal = 1000;
	my $title = $self->{'title'};
	my $masterfile = new Loghandler($mobUtil->chooseNewFileName('/tmp',"master_$title",'pid'));
	my $previousTime=DateTime->now;
	foreach(@cha)
	{
		$tselects.=$_;
	}
	
	my $maxQuery = $tselects;
	my $minQuery = $tselects;
	my $min = findMinMaxRecordCount($self,$minQuery,"min");
	#print "Min = $min\n";
	my $max = 1;
	$min--;
	$maxQuery =~ s/\$recordSearch/COUNT(\*)/gi;
	$max = findMinMaxRecordCount($self,$maxQuery,"max");
	
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
	my $majorloops=0;
	while($threadsAlive)
	{
		$majorloops++;
		#print "Starting main Thread loop\n";
		my $workingThreads=0;
		my @newThreads=();
		my $threadJustFinished=0;
		#print Dumper(\@threadTracker);
		print "Looping through the threads\n";
		$recordsCollectedTotalPerLoop = $finishedRecordCount;
		foreach(@threadTracker)
		{	
			my @attr = @{$_};
			my $thisPidfile = @attr[0];
			#print "Checking to see if thread $thisPidfile is done\n";
			my $thisOff = @attr[1];
			my $thisInc = @attr[2];
			my $checkcount = @attr[3];
			@attr[3]++;
			my $duser = @attr[4];
			my $continueChecking=1;
			#print "$thisPidfile $thisOff $thisInc: $checkcount\n";
			#give thread time to get started and create pidfile (40 seconds)
			if($checkcount > 2)
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
					}
					else
					{
						my @add = ($thisOff,$thisInc);
						push(@recovers,[@add]);
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
					print "$thisPidfile Thread Finished.... Cleaning up\n";
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
							
							print "This thread died, going to restart it\n";
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
								print "Deleting @lines[0]\n";
								$check->deleteFile();
							}
							#print "Done recovering\n";
						}
						else
						{
							print "Completed thread success, now cleaning\n";
							if( (@lines[1] == 0) && ($majorloops > 100) && ($zeroAdded>50) ) #lets not query the max if this is early in the game
							{
								$zeroAdded++;
								print "Checking findMinMaxRecordCount\n";
								local $@;
								eval{ $max = findMinMaxRecordCount($self,$maxQuery,"max"); };
								if ($@) 
								{
									print "Reconnecting to DB\n";
									my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};
									$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},@dbUsers[0],@dbPasses[0],$conf{"port"});
									$self->{'dbhandler'} = $dbHandler;
									$max = findMinMaxRecordCount($self,$maxQuery,"max");
									if($max < 100)
									{
										$max=1000000;
									}									
								}
								
								print "Got 0 records $zeroAdded times\n";
								if($zeroAdded>1200) #we have looped 2400 times (20 minutes) and not a single record added to the collection. Time to quit.
								{
									$finishedRecordCount = $max;
								}
							}
							else
							{
								print "zeroAdded = 0\n";
								$zeroAdded=0;
							}
							
							$dbUserTrack{$dbuser}--;
							if(@lines[1] !=0)
							{
								print "Assigning toobig\n";
								$self->{'toobig'}.=@lines[2];
								print "Assigning toobigtocut\n";
								$self->{'toobigtocut'}.=@lines[3];
								if(@lines[7]<1)
								{
									print "Assigning Line 7\n";
									@lines[7]=1;
								}
								print "Assigning trps\n";
								my $trps = @lines[1] / @lines[7];
								print "Performed trps\n";
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
								print "Performed chunkGoal\n";
								$rps = $trps;
								#print "Adjusted chunk to $chunkGoal\n";
								push(@dumpedFiles,@lines[0]);
								print "Added dump files to array\n";
								$finishedRecordCount += @lines[1];
								print "Added dump count to total\n";
								#print Dumper(\@dumpedFiles);
							}
							else
							{
								$zeroAdded++;
							}
							
						}
					}
					else
					{
						print "For some reason the thread PID file did not output the expected stuff\n";
					}
					print "Looping back through the rest of running threads\n";
				}
				else
				{
					print "Thread not finished, adding it to \"running\"\n";
					$workingThreads++;
					push(@newThreads,[@attr]);
				}
			}
		}
		@threadTracker=@newThreads;
		print "$workingThreads / $threadsAllowed Threads\n";
		
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
						print "Searching for an available userid\n";
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
								#print "Sending off for range....\n";
								$thisIncrement = calcDBRange($self,$thisOffset,$chunkGoal,$dbHandler,$tselects);								
								print "Got range: $thisIncrement\n";
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
							print "Just pushed thread onto stack\n";
							$pidFileNameStart++;
							if(!$choseRecover)
							{
								$offset=$thisIncrement;
								$increment=$thisIncrement;
							}
						}
						else
						{
							print "Could not find an available db user - going to have to wait\n";
						}
						$workingThreads++;
						print "End of while loop for $workingThreads< ( $threadsAllowed - 1 )\n";
					}
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
			print "Looped to many times with nothing added - Stopping\n";
		}
		
		if($workingThreads==0 && !$threadJustFinished)
		{
			$threadsAlive=0;
		}
		print "Calculating Time\n";
		my $secondsElapsed = calcTimeDiff($self,$previousTime);
		print "Calc minutesElapsed Time\n";
		my $minutesElapsed = $secondsElapsed / 60;
		print "Calc overAllRPS Time\n";
		my $overAllRPS = $finishedRecordCount / $secondsElapsed;
		my $devideTemp = $overAllRPS;
		if($devideTemp<1)
		{
			$devideTemp=1;
		}
		print "Calc remaining Time\n";
		my $remaining = ($max - $finishedRecordCount) / $devideTemp / 60;
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
		print "Sleeping\n";
		sleep(2);
		#print "Looping\n";
	}
	print "Totally Done with thread handler\n";
	$self->{'diskdump'}=\@dumpedFiles;
	$masterfile->deleteFile();
 }
 
 sub findMinMaxRecordCount
 {
	my $self = @_[0];
	my $mm = @_[1];
	my $minmax = @_[2];
	my @cha = split("",$mm);
	my $maxQuery;
	foreach(@cha)
	{
		$maxQuery.=$_;
	}
	$maxQuery =~ s/\$recordSearch/$minmax(ID)/gi;
	$maxQuery =~ s/\$rangestatement_id//gi;
	$maxQuery =~ s/\$rangestatement_ITEM_RECORD_ID//gi;
	$maxQuery =~ s/\$rangestatement_RECORD_ID//gi;
	my $dbHandler = $self->{'dbhandler'};
	my $max = 0;
	print "$maxQuery\n";
	my @results = @{$dbHandler->query($maxQuery)};
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		$max = @row[0];
	}
	print "$max\n";
	return $max;
 }
 
 sub calcDBRange
 {
	#print "starting rangefinding\n";
	my $self = @_[0];
	my $previousTime=DateTime->now;
	my $thisOffset = @_[1];	
	my $chunkGoal = @_[2];
	my $dbHandler = @_[3];
	my $countQ = @_[4];
	my $thisIncrement = $thisOffset;
	
	$countQ =~s/\$recordSearch/COUNT(\*)/gi;
	$countQ =~ s/\$rangestatement_id//gi;
	$countQ =~ s/\$rangestatement_ITEM_RECORD_ID//gi;
	$countQ =~ s/\$rangestatement_RECORD_ID//gi;
	
	my $yeild=0;
	if($chunkGoal<1)
	{
		$chunkGoal=1;
	}
	$thisIncrement+=$chunkGoal;
	return $thisIncrement;
	my $trys = 0;
	while($yeild<$chunkGoal)  ## Figure out how many rows to read into the database to get the goal number of records
	{	
		my $selects = $countQ." AND ID > $thisOffset AND ID <= $thisIncrement";
		#print "$selects\n";
		my @results = @{$dbHandler->query($selects)};
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
			if($trys>20)	#well, 100 * 10 and we didn't get 1000 rows returned, so we are stopping here.
			{
				$yeild=$chunkGoal;
				print "Range finding took 20 loops, giving up\n";
			}
			$thisIncrement+=$chunkGoal+($trys*$chunkGoal);
		}
	}
	my $secondsElapsed = calcTimeDiff($self,$previousTime);
	#print "Range Finding: $secondsElapsed after $trys trys\n";
	
	#print "ending rangefinding\n";
	return $thisIncrement;
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
	my $query = "
select 
(select string_agg(record_num::text,',' order by id) from sierra_view.bib_view where id in (select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id)),
(select string_agg(material_code,',' order by bib_record_id) from sierra_view.bib_record_property where material_code in('a','t') and bib_level_code = 'm' and bib_record_id in (select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id)),
(select string_agg(bib_level_code,',' order by bib_record_id) from sierra_view.bib_record_property svbrp where material_code in('a','t') and bib_level_code = 'm' and svbrp.bib_record_id in (select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id)),
(select string_agg(field_content,',' order by record_id) from SIERRA_VIEW.VARFIELD_VIEW oclcnum where oclcnum.marc_tag = '001' and oclcnum.field_content!~'\D' and oclcnum.record_id in(select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id)),
(select string_agg(p27,',') from SIERRA_VIEW.CONTROL_FIELD where record_id in(select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id) and control_num = 8),
(select string_agg(p28,',') from SIERRA_VIEW.CONTROL_FIELD where record_id in(select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id) and control_num = 8),
(select string_agg(p29,',') from SIERRA_VIEW.CONTROL_FIELD where record_id in(select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id) and control_num = 8),
sviv.barcode,
(select string_agg(field_content,',' order by record_id) from SIERRA_VIEW.VARFIELD_VIEW where record_id = sviv.id and record_type_code ='i' and varfield_type_code='v'),
'i'||sviv.record_num,
svir.itype_code_num,
svir.location_code,
(select string_agg(regexp_replace(field_content,'\|a([^\|]*)|.([\|]*)','\1','g'),',' order by record_id) from SIERRA_VIEW.VARFIELD_VIEW where record_id in(select bib_record_id from SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK where item_record_id=svir.record_id) and marc_tag = '022')
from  
SIERRA_VIEW.ITEM_RECORD svir,
SIERRA_VIEW.ITEM_VIEW sviv
where 
sviv.id=svir.id and
svir.record_id in($selects)";
	#print "$query\n";	
	$pidfile->truncFile($query);
	my @results = @{$dbHandler->query($query)};
	updateQueryDuration($self,$previousTime,$query);
	my @records;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = scalar keys %standard;
		$recordID++;
		if(!exists $standard{$recordID})
		{
			my @a = ();
			$standard{$recordID} = \@a;
		}
		if((length($mobUtil->trim(@row[1]))>0) && (length($mobUtil->trim(@row[2]))>0) && (length($mobUtil->trim(@row[3]))>0))
		{
			push(@{$standard{$recordID}},join("\t",@row));
		}
		else
		{
			push(@{$standard{$recordID}},'');
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
	my %standard = %{$self->{'standard'}};
	my $ret = '';
	foreach(@{$standard{$recID}})
	{
		$ret.=$_."\n";
	}
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
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE RECORD_ID=A.ITEM_RECORD_METADATA_ID AND FIELD_TYPE_CODE='b' LIMIT 1)
		)),
		
		TRIM(CONCAT(	
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='a' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID LIMIT 1)),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='b' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID LIMIT 1)),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='c' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID LIMIT 1)),
		' ',	
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='d' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID LIMIT 1))
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
		#print "$query\n";
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
	if($duration<.1)
	{
		$duration=.1;
	}
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
		my @try = ('standard');
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
			if(length($mobUtil->trim($_))>0)
			{
				$output.=$_;
			}
		}
		if(length($title)>0)
		{
			$title=$title."_";
		}
		my $fileName = $mobUtil->chooseNewFileName("/tmp/temp",$title."temp","txt");
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
	return \@newDump;
 }
 
 sub getTooBigList
 {
	my $self = @_[0];
	my @ret = ($self->{'toobig'},$self->{'toobigtocut'});
	return \@ret;
 }
 
 1;
 
 