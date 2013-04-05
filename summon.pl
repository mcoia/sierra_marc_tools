#!/usr/bin/perl
# 
# sierra_marc_start.pl
#
# Usage:
# ./summon.pl conf_file.conf [adds / cancels]
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

 use strict; 
 use Loghandler;
 use Mobiusutil;
 use DBhandler;
 use recordItem;
 use sierraScraper;
 use Data::Dumper;
 use email;
 use DateTime;
 
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
		my @reqs = ("dbhost","db","dbuser","dbpass","fileprefix","marcoutdir","cluster","alwaysemail","fromemail");
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
			my $fileNamePrefix = $conf{"fileprefix"}."cancels-";
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
		
		
			if($valid)
			{
				my $dbHandler;
				
				 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});};
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
						$fdate = $dt->mdy;
						$fdate =~ s/-//g;
					}
					my $outputMarcFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},$fileNamePrefix.$fdate,"out");
					
					if($outputMarcFile ne "0")
					{	
					#Logging and emailing
						$log->addLogLine("$cluster $type *STARTING*");
						$dt   = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
						$fdate = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
						my $ftime = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
						my $dateString = "$fdate $ftime";  # "2013-02-16 05:00:00";
						my @tolist = ($conf{"alwaysemail"});
						my $email = new email($conf{"fromemail"},\@tolist,0,0,\%conf);
						$email->send("RMO $cluster - Summon $type Winding Up - Job # $dateString","I have started this process.\r\n\r\nYou will be notified when I am finished\r\n\r\n-MOBIUS Perl Squad-");
					#Logging and emailing
					
	
						print $outputMarcFile."\n";
						my $marcOutFile = "/tmp/run/marcout";# $outputMarcFile			
						my $sierraScraper = new sierraScraper($dbHandler,$log,$mobUtil->findSummonQuery($dbHandler,$cluster,$type));

						my @marc = @{$sierraScraper->getAllMARC()};
						my $marcout = new Loghandler($marcOutFile);
						$marcout->deleteFile();
						my $output;
						foreach(@marc)
						{
							my $marc = $_;
							$output.=$marc->as_usmarc();
						}
						$marcout->addLine($output);
						
						my @errors = @{$mobUtil->compare2MARCFiles($marcOutFile,"/tmp/run/galahad_adds.out", $log, 907, "a" )};
						
						my $errors;
						foreach(@errors)
						{
							$errors.= $_."\r\n";
						}
						
						my @tos = ('junk@monsterfro.com');
						$email = new email('junk@monsterfro.com',\@tos,0,0,\%conf);
						$email->send("Errors",$errors);
						print "done emailing\n";
						
						if(0)
						{
							my $format = DateTime::Format::Duration->new(
								pattern => '%e days, %H hours, %M minutes, %S seconds'
							);
							my $afterProcess = DateTime->now(time_zone => "local");
							my $difference = $afterProcess - $dt;
							my $duration =  $format->format_duration($difference);
							if($errors!=1)
							{
								$log->addLogLine("$cluster $type: ERROR: $errors");
								$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
								$email->send("RMO $cluster - Summon $type Error - Job # $dateString","Duration: $duration\r\n\r\nUnfortunately, there are some errors. Here are all of the prompts that I answered:\r\n\r\n   \r\n\r\nAnd here are the errors:\r\n\r\n$errors\r\n\r\n-MOBIUS Perl Squad-");
							}
							else
							{
								$log->addLogLine("$cluster $type: Success!");
								$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
								$email->send("RMO $cluster - Summon $type Success - Job # $dateString","Duration: $duration\r\n\r\nThis process finished without any errors!\r\n\r\nIsn't that WONDERFUL?!\r\n\r\nHere are all of the prompts that I answered:\r\n\r\n  \r\n\r\n-MOBIUS Perl Squad-");
							}
						}
						
						$log->addLogLine("$cluster $type *ENDING*");
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
		print "Config file does not define 'logfile' and 'marcoutdir'\n";
		
	}
 }
 
 exit;