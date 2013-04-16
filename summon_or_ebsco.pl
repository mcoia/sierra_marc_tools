#!/usr/bin/perl
# 
# sierra_marc_start.pl
#
# Usage:
# ./summon_or_ebsco.pl conf_file.conf [adds / cancels] [ebsco / summon]
#
# Example Configure file:
# 
# logfile = /tmp/log.log
# marcoutdir = /tmp
# z3950server = server.address.org/INNOPAC
# dbhost = 192.168.12.45
# db = postgresDB_Name
# dbuser = dbuser
# dbpass = dbpassword
#
#
# This script requires:
#
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# 
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24

 use lib qw(../);
 use strict; 
 use Loghandler;
 use Mobiusutil;
 use DBhandler;
 use recordItem;
 use sierraScraper;
 use Data::Dumper;
 use email;
 use DateTime;
 use utf8;
 use Encode;
 use DateTime::Format::Duration;

 
 #use warnings;
 #use diagnostics; 
		 
 my $configFile = @ARGV[0];
 if(!$configFile)
 {
	print "Please specify a config file\n";
	exit;
 }

 my $mobUtil = new Mobiusutil(); 
 my $conf = $mobUtil->readConfFile($configFile);
 
 if($conf)
 {
	my %conf = %{$conf};
	if ($conf{"logfile"})
	{
		my $log = new Loghandler($conf->{"logfile"});
		$log->addLogLine(" ---------------- Script Starting ---------------- ");
		my @reqs = ("dbhost","db","dbuser","dbpass","port","fileprefix","marcoutdir","cluster","alwaysemail","fromemail","ftplogin","ftppass","ftphost");
		my $valid = 1;
		for my $i (0..$#reqs)
		{
			if(!$conf{@reqs[$i]})
			{
				$log->addLogLine("Required configuration missing from conf file");
				$log->addLogLine(@reqs[$i]." required");
				$valid = 0;
			}
		}
		if($valid)
		{		
			my $cluster = $conf{"cluster"};
			my $type = @ARGV[1];
			my $platform = @ARGV[2]; #ebsco or summon
			my $fileNamePrefix = $conf{"fileprefix"}."cancels-";
			my $remoteDirectory = "/updates";
			if(defined($type))		
			{
				if($type eq "adds")
				{
					$valid = 1;
					$fileNamePrefix = $conf{"fileprefix"}."updates-";
					if($cluster eq "ucm")
					{
						$fileNamePrefix = "Summon_ADDS_UCM_";
					}
				}
				elsif($type eq "cancels")
				{
					$valid = 1;
					if($cluster eq "ucm")
					{
						$fileNamePrefix = "Summon_CANCELS_UCM_";
					}
					$remoteDirectory = "/deletes";
				}
				else
				{
					$valid = 0;
					print "You need to specify the type 'adds' or 'cancels'\n";
				}
			}
			else
			{
				$valid = 0;
				print "You need to specify the type 'adds' or 'cancels'\n";
			}
			if(defined($platform))
			{
				if($platform eq 'summon')
				{}
				else
				{
				$valid = 0;
				
				}
			}
			else			
			{
				print "You need to specify the type 'ebsco' or 'summon'\n";
			}
		
		#All inputs are there and we can proceed
			if($valid)
			{
				my $dbHandler;
				
				 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"});};
				 if ($@) {
					$log->addLogLine("Could not establish a connection to the database");
					$valid = 0;
				 }
				 if($valid)
				 {

					my $dt   = DateTime->now(time_zone => "local"); 	
					my $fdate = $dt->ymd;
					if($cluster eq "ucm")
					{
					#REMOVE HYPHENS FOR UCM (QUEST)
						$fdate = $dt->mdy;
						$fdate =~ s/-//g;
					}
					my $outputMarcFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},$fileNamePrefix.$fdate,"out");#"/tmp/run/mout/jewell-catelog-updates-2013-04-120.out";
					
					if($outputMarcFile ne "0")
					{	
					#Logging and emailing
						$log->addLogLine("$cluster $platform $type *STARTING*");
						$dt   = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
						$fdate = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
						my $ftime = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
						my $dateString = "$fdate $ftime";  # "2013-02-16 05:00:00";
						my @tolist = ($conf{"alwaysemail"});
						my $email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
						$email->send("RMO $cluster - $platform $type Winding Up - Job # $dateString","I have started this process.\r\n\r\nYou will be notified when I am finished\r\n\r\n-MOBIUS Perl Squad-");
					#Logging and emailing
					
	
						#print $outputMarcFile."\n";
						my $marcOutFile = $outputMarcFile;
						my $sierraScraper;
						$valid=1;
						local $@;
						eval{$sierraScraper = new sierraScraper($dbHandler,$log,$mobUtil->findSummonQuery($dbHandler,$cluster,$type));};
						if($@)
						{
							$valid=0;
							$email = new email($conf{"fromemail"},\@tolist,1,1,\%conf);
							$email->send("RMO $cluster - $platform $type FAILED - Job # $dateString","There was a failure when trying to get data from the database.\r\n\r\n I have only seen this in the case where an item has more than 1 bib and is in the same subset of records. Check the cron output for more information.\r\n\r\nThis job is over.\r\n\r\n-MOBIUS Perl Squad-");
							$log->addLogLine("Sierra scraping Failed. The cron standard output will have more clues.");
						}
						if($valid)
						{
							my @marc = @{$sierraScraper->getAllMARC()};
							my $marcout = new Loghandler($marcOutFile);
							$marcout->deleteFile();
							my $output;
							my $recCount=0;
							foreach(@marc)
							{
								my $marc = $_;
								$marc->encoding( 'UTF-8' );
								$output.=$marc->as_usmarc();
								$recCount++;
							}
							if($recCount>0)
							{						
								$marcout->addLine($output);
								my @files = ($marcOutFile);							
								eval{$mobUtil->sendftp($conf{"ftphost"},$conf{"ftplogin"},$conf{"ftppass"},$remoteDirectory,\@files,$log);};
								 if ($@) {
									$log->addLogLine("FTP FAILED");
									$email = new email($conf{"fromemail"},\@tolist,1,1,\%conf);
									$email->send("RMO $cluster - $platform $type FTP FAIL - Job # $dateString","I'm just going to apologize right now, I could not FTP the file to ".$conf{"ftphost"}." ! Remote directory: $remoteDirectory\r\n\r\nYou are going to have to do it by hand. Bummer.\r\n\r\nCheck the log located: ".$conf{"logfile"}." and you will know more about why. Please fix this so that I can FTP the file in the future!\r\n\r\n File:\r\n\r\n$marcOutFile\r\n$recCount record(s).  \r\n\r\n-MOBIUS Perl Squad-");
								 }
							}
							else
							{
								$marcOutFile = "(none)";
							}
							
							#my @errors = @{$mobUtil->compare2MARCFiles($marcOutFile,"/tmp/run/trcc-catalog-updates-2013-03-22.out", $log, 907, "a" )};
							
							#my $errors;
							#foreach(@errors)
							#{
						#		$errors.= $_."\r\n";
					#		}
					#		print $errors;
					#								
					#		$email = new email($conf{"fromemail"},\@tolist,0,0,\%conf);
					#		#$email->send("Errors",encode("utf-8",$errors));
					#		#print "done emailing\n";
							
							if(1)
							{
								my $format = DateTime::Format::Duration->new(
									pattern => '%e days, %H hours, %M minutes, %S seconds'
								);
								my $afterProcess = DateTime->now(time_zone => "local");
								my $difference = $afterProcess - $dt;
								my $duration =  $format->format_duration($difference);
								$log->addLogLine("$cluster $type: $marcOutFile");
								$log->addLogLine("$cluster $type: $recCount Record(s)");
								$log->addLogLine("$cluster $type: Finished");
								$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
								$email->send("RMO $cluster - $platform $type Success - Job # $dateString","Duration: $duration\r\n\r\nThis process finished without any errors!\r\n\r\nIsn't that WONDERFUL?!\r\n\r\nHere is some information:\r\n\r\nOutput File: \t\t$marcOutFile\r\n$recCount Record(s)\r\nFTP location: ".$conf{"ftphost"}."\r\nUserID: ".$conf{"ftplogin"}."\r\nFolder: $remoteDirectory\r\n\r\n-MOBIUS Perl Squad-");
								
							}
						}
						
						$log->addLogLine("$cluster $platform $type *ENDING*");
					}
					else
					{
						$log->addLogLine("Output directory does not exist: ".$conf{"marcoutdir"});
					}
					
				 }
			 }
			 $log->addLogLine(" ---------------- Script Ending ---------------- ");
		 }
	}
	else
	{
		print "Config file does not define 'logfile'\n";		
	}
 }
 
 exit;