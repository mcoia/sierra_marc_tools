#!/usr/bin/perl
# 
# sierra_marc_start.pl
#
# Usage:
# ./sierra_marc_start.pl conf_file.conf
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
 use utf8;
 no utf8;
 
 #use warnings;
 #use diagnostics; 
		 
 my $configFile = shift;
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
		my @reqs = ("dbhost","db","dbuser","dbpass","z3950server","marcoutdir");
		my $valid = 1;
		for my $i (0..length(@reqs))
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
			my $dbHandler;
			
			 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});};
			 if ($@) {
				$log->addLogLine("Could not establish a connection to the database");
				$valid = 0;
			 }
			 if($valid)
			 {
				#420908010009
				my $marcOutFile = "/jail/marcout";#$mobUtil->chooseNewFileName($conf->{"marcoutdir"},"marcout","mrc");
				my $sierraScraper = new sierraScraper($dbHandler,$log,"SELECT ID FROM SIERRA_VIEW.BIB_VIEW WHERE RECORD_NUM=1215011");# >= 1215001 AND RECORD_NUM <= 1215021");#['420907796199','420907798387']);
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
				
				my @errors = @{$mobUtil->compare2MARCFiles($marcOutFile,"/tmp/run/BLAKE2.out", $log)};
				foreach(@errors)
				{
					print $_."\n";
				}
				 if(0)
				 {
					 my $marcOutFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},"marcout","mrc");
					 my $marcOutFile = "/jail/marcout";
					 my $marc = $mobUtil->makeMarcFromDBID($dbHandler,$log,420907798387);#420907796199);
					 my $marcout = new Loghandler($marcOutFile);
					 $marcout->deleteFile();
					 $marcout->addLine($marc->as_usmarc());
					 #@recordIDs = $mobUtil->findSummonIDs($dbHandler,$log);
					 
				 }
				 if(0)
				 {
					 #my $marcOutFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},"marcout","mrc");
					 
					 my @marcs = @{$mobUtil->getMarcFromQuery($conf{"z3950server"},"\@attr 1=38 \"Writer's market\"",$log)};  #1889374
					 my $outputstring;
					 foreach(@marcs)
					 {
						 $outputstring = $outputstring . $_->as_usmarc();
						 #print "1: \"".$_->field('001')->data()."\"";
						 #print "5: \"".$_->field('005')->data()."\"";
						 #print "8: \"".$_->field('008')->data()."\"";
						 print $_->as_formatted();
					 }
					 #$log->addLogLine("Outputting marc records into $marcOutFile");
					 #my $marcout = new Loghandler($marcOutFile);
					 #$marcout->deleteFile();
					 #$marcout->addLine($outputstring);
				 }
			 }
		 }
		 $log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile' and 'marcoutdir'\n";
		
	}
 }
 
 exit;