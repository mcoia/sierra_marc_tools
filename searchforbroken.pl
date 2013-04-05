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
 use pQuery;
 
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
		my @reqs = ("dbhost","db","dbuser","dbpass","alwaysemail","fromemail","results","searchprefix");
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
			my $cluster = $conf->{"cluster"};
			my $output="";
			my $brokenresults = new Loghandler($conf->{"results"});
			my $dbHandler;
			 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});};
			 if ($@) {
				$log->addLogLine("$cluster Could not establish a connection to the database");
				$valid = 0;
			 }
			 if($valid)
			 {
				my $searchprefix = $conf->{"searchprefix"};
				my $query = 
"select RECORD_NUM from SIERRA_VIEW.BIB_VIEW where id in(
(
(
SELECT ID FROM SIERRA_VIEW.RECORD_METADATA WHERE 
(RECORD_LAST_UPDATED_GMT > TO_DATE('2013-01-01','YYYY-MM-DD HH24:MI:MS'))
)
)
)";
				my @ids = ();
				if($brokenresults->fileExists())
				{
					@ids = @{$brokenresults->readFile()};
				}
				my @results = @{$dbHandler->query($query)};
				my $total = $#results+1;
				my $update = new Loghandler("/tmp/run/broke-pid-$cluster.txt");
				my $errorCount=0;
				my @errorList=();
				my $num=0;
				foreach(@results)
				{
					my $alreadyDone = 0;
					$num++;
					my $row = $_;
					my @row = @{$row};
					my $recordID = @row[0];
					my $foundInFile=0;
					foreach(@ids)
					{
						if(!$foundInFile)
						{
							if(index($_,"b$recordID")>-1)
							{
								$alreadyDone=1;
								$foundInFile=1;
								if(index($_,"$searchprefix")>-1)
								{
									$errorCount++;
								}
							}
						}
					}
					
					if(!$alreadyDone)
					{
						my $found=0;
						$output.="b$recordID,";
						pQuery("http://searchmobius.org/search~S0/z?SEARCH=$searchprefix+b$recordID")
						->find("table")->each(sub {
								pQuery($_)->find("tr")->each(sub{
									my $isOCLC = 0;
									pQuery($_)->find(".bibInfoLabel")->each(sub{
										if(index(pQuery($_)->text,"OCLC")>-1)
										{
											$isOCLC=1;
										}
										});
									if($isOCLC)
									{
										if(!$found)
										{
											pQuery($_)->find(".bibInfoData")->each(sub{
											
												if(index(pQuery($_)->text,"b$recordID")>-1)
												{
													$found=1;
													$output.= "\"";
													$output.= pQuery($_)->text;
													$output.= "\"";													
													$errorCount++;
													push(@errorList,$recordID);
												}
											});
										}
									}
								});
							});
							#$output.= "\n";
							$brokenresults->addLine($output);
							$update->truncFile("$cluster\t\t".$num." / $total\t$errorCount error(s)");
							$output="";
							sleep .5;
					}
				}
				
				$log->addLogLine("$cluster Found: $errorCount missing records on innreach");
				if(0)
				{
					$query = "SELECT ID FROM SIERRA_VIEW.BIB_VIEW WHERE RECORD_NUM IN(";
					foreach(@errorList)
					{
						$query.="$_,";
					}
					$query=substr($query,0,length($query)-1).")";
					my $sierraScraper = new sierraScraper($dbHandler,$log,$query);

					my @marc = @{$sierraScraper->getAllMARC()};
					my $marcout = new Loghandler("/tmp/run/marc-broken-$cluster.mrc");
					$marcout->deleteFile();
					my $output;
					foreach(@marc)
					{
						my $marc = $_;
						$output.=$marc->as_usmarc();
					}
					$marcout->addLine($output);
				}
				if(0)
				{
					my @tos = ('junk@monsterfro.com');
					my $email = new email('junk@monsterfro.com',\@tos,0,0,\%conf);
					$email->send("Errors","");
					print "done emailing\n";
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