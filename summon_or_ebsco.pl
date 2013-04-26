#!/usr/bin/perl
# 
# summon_or_ebsco.pl
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
		my @reqs = ("dbhost","db","dbuser","dbpass","port","fileprefix","marcoutdir","school","alwaysemail","fromemail","ftplogin","ftppass","ftphost","queryfile","platform");
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
			my $queries = $mobUtil->readQueryFile($conf{"queryfile"});
			if($queries)
			{
				my %queries = %{$queries};
				
				my $school = $conf{"school"};
				my $type = @ARGV[1];
				my $platform = $conf{"platform"};#ebsco or summon
				my $fileNamePrefix = $conf{"fileprefix"}."_cancels_";
				my $remoteDirectory = "/updates";
				if(defined($type))		
				{
					if($type eq "adds")
					{
						$valid = 1;
						$fileNamePrefix = $conf{"fileprefix"}."_updates_";
						if($platform eq 'ebsco')
						{
							$remoteDirectory = "/update";
						}
					}
					elsif(($platform eq 'summon') && ($type eq "cancels"))
					{
						$valid = 1;
						$remoteDirectory = "/deletes";
					}
					elsif($type eq "cancels")
					{
						$valid = 1;
						if($platform eq 'ebsco')
						{
							$remoteDirectory = "/update";
						}
					}
					elsif($type eq "full")
					{
						$valid = 1;
						$remoteDirectory = "/full";
						$fileNamePrefix = $conf{"fileprefix"}."_full_";
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
				if(!defined($platform))
				{
					print "You need to specify the platform 'ebsco' or 'summon'\n";
				}
				else
				{
					$fileNamePrefix=$platform."_".$fileNamePrefix;
				}
			
			#All inputs are there and we can proceed
				if($valid)
				{
					my $dbHandler;
					my $failString = "Success";
					 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"});};
					 if ($@) {
						$log->addLogLine("Could not establish a connection to the database");
						$failString = "Could not establish a connection to the database";
						$valid = 0;
						my @tolist = ($conf{"alwaysemail"});
						my $email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
						$email->send("RMO $school - $platform $type FAILED - $failString","\r\n\r\nThis job is over.\r\n\r\n-MOBIUS Perl Squad-");						
						
					 }
					 if($valid)
					 {

						my $dt   = DateTime->now(time_zone => "local"); 	
						my $fdate = $dt->ymd;
						
						my $outputMarcFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},$fileNamePrefix.$fdate,"mrc");
						
						if($outputMarcFile ne "0")
						{	
						#Logging and emailing
							$log->addLogLine("$school $platform $type *STARTING*");
							$dt    = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
							$fdate = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
							my $ftime = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
							my $dateString = "$fdate $ftime";  # "2013-02-16 05:00:00";
							my @tolist = ($conf{"alwaysemail"});
							my $email = new email($conf{"fromemail"},\@tolist,0,0,\%conf);
							$email->send("RMO $school - $platform $type Winding Up - Job # $dateString","I have started this process.\r\n\r\nYou will be notified when I am finished\r\n\r\n-MOBIUS Perl Squad-");
						#Logging and emailing
						
		
							#print $outputMarcFile."\n";
							my $marcOutFile = $outputMarcFile;
							my $sierraScraper;
							$valid=1;
							my $selectQuery = $mobUtil->findQuery($dbHandler,$school,$platform,$type,$queries);
							
							
							local $@;
							eval{$sierraScraper = new sierraScraper($dbHandler,$log,$selectQuery);};
							if($@)
							{
								$valid=0;
								$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
								$email->send("RMO $school - $platform $type FAILED - Job # $dateString","There was a failure when trying to get data from the database.\r\n\r\n I have only seen this in the case where an item has more than 1 bib and is in the same subset of records. Check the cron output for more information.\r\n\r\nThis job is over.\r\n\r\n-MOBIUS Perl Squad-\r\n\r\n$selectQuery");
								$log->addLogLine("Sierra scraping Failed. The cron standard output will have more clues.\r\n$selectQuery");
								$failString = "Scrape Fail";
							}
							my $recCount=0;
							my $extraInformationOutput = "";
							my $format = DateTime::Format::Duration->new(
								pattern => '%M:%S' #%e days, %H hours,
							);
							my $afterProcess = DateTime->now(time_zone => "local");
							my $difference = $afterProcess - $dt;
							my $duration =  $format->format_duration($difference);
							
							if($valid)
							{
								my @marc = @{$sierraScraper->getAllMARC()};
								my $marcout = new Loghandler($marcOutFile);
								$marcout->deleteFile();
								my $output;
								my $barcodes="";
								foreach(@marc)
								{
									my $marc = $_;
									$marc->encoding( 'UTF-8' );
									my $count = $mobUtil->marcRecordSize($marc);
									if($count<75000) #ISO2709 MARC record is limited to 99,999 octets (this number is calculated differently than my size function so I compare to a lower number)
									{
										#ebsco cancels needs the leader altered
										if(($platform eq 'ebsco' ) && ($type eq 'cancels'))
										{
											my $leader = $marc->leader();
											my @lchars = split('',$leader);
											my $finalLeader = "";										
											@lchars[5] = 'd';
											foreach(@lchars)
											{
												$finalLeader.=$_;
											}
											$marc->leader($finalLeader);
										}
										$barcodes.=$marc->subfield('907',"a");
										$barcodes.="\r\n";
										$output.=$marc->as_usmarc();
										$recCount++;
									}
									else
									{
										$extraInformationOutput.=$marc->subfield('907',"a");
									}
								}
								
								if(length($extraInformationOutput)>0)
								{
									$extraInformationOutput="These records were omitted due to the 100000 size limits: $extraInformationOutput";
								}
								
								if($recCount>0)
								{						
									$marcout->addLine($output);
									my @files = ($marcOutFile);
									if(1)  #switch FTP on and off easily
									{
										eval{$mobUtil->sendftp($conf{"ftphost"},$conf{"ftplogin"},$conf{"ftppass"},$remoteDirectory,\@files,$log);};
										 if ($@) 
										 {
											$log->addLogLine("FTP FAILED");
											$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
											$email->send("RMO $school - $platform $type FTP FAIL - Job # $dateString","I'm just going to apologize right now, I could not FTP the file to ".$conf{"ftphost"}." ! Remote directory: $remoteDirectory\r\n\r\nYou are going to have to do it by hand. Bummer.\r\n\r\nCheck the log located: ".$conf{"logfile"}." and you will know more about why. Please fix this so that I can FTP the file in the future!\r\n\r\n File:\r\n\r\n$marcOutFile\r\n$recCount record(s).  \r\n\r\n-MOBIUS Perl Squad-");
											$failString = "FTP Fail";
											$valid=0;
										 }
									 }
								}
								else
								{
									$marcOutFile = "(none)";
								}
								
								if(0)
								{
									my @errors = @{$mobUtil->compare2MARCFiles($marcOutFile,"/tmp/run/bb.mrc", $log, 907, "a" )};
									
									my $errors;
									foreach(@errors)
									{
										$errors.= $_."\r\n";
									}
									print $errors;
															
									$email = new email($conf{"fromemail"},\@tolist,0,0,\%conf);
									$email->send("Errors",encode("utf-8",$errors));
									#print "done emailing\n";
								}
								if($valid)
								{
									$afterProcess = DateTime->now(time_zone => "local");
									$difference = $afterProcess - $dt;
									$duration =  $format->format_duration($difference);
									$log->addLogLine("$school $platform $type: $marcOutFile");
									$log->addLogLine("$school $platform $type: $recCount Record(s)");
									$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
									$email->send("RMO $school - $platform $type Success - Job # $dateString","Duration: $duration\r\n\r\nThis process finished without any errors!\r\n\r\nHere is some information:\r\n\r\nOutput File: \t\t$marcOutFile\r\n$recCount Record(s)\r\nFTP location: ".$conf{"ftphost"}."\r\nUserID: ".$conf{"ftplogin"}."\r\nFolder: $remoteDirectory\r\n\r\n$extraInformationOutput\r\n\r\n-MOBIUS Perl Squad-\r\n\r\n$selectQuery\r\n\r\nThese are the included records:\r\n$barcodes");
								}
							}
				#OUTPUT TO THE CSV
							if($conf{"csvoutput"})
							{
								 my $csv = new Loghandler($conf{"csvoutput"});
								 my $csvline = "\"$dateString\",\"$school\",\"$platform\",\"$type\",\"$failString\",\"$marcOutFile\",\"$duration\",\"$recCount Record(s)\",\"".$conf{"ftphost"}."\",\"".$conf{"ftplogin"}."\",\"$remoteDirectory\",\"$extraInformationOutput\"";
								 $csv->addLine($csvline);
								 undef $csv;
							 
							}
							
							$log->addLogLine("$school $platform $type *ENDING*");
						}
						else
						{
							$log->addLogLine("Output directory does not exist: ".$conf{"marcoutdir"});
						}
						
					 }
				 }
			 }
		 }
		 $log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile'\n";		
	}
 }
 
 exit;