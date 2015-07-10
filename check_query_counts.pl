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

 my $barcodeCharacterAllowedInEmail=2000;
 
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
		if(-e $conf->{"logfile"})
		{
			print "Logfile ".$conf->{"logfile"}." exists\n";
		}
		else
		{
			print "Logfile ".$conf->{"logfile"}." does not exist (which is ok)\n";
		}
		my @reqs = ("dbhost","db","dbuser","dbpass","port","fileprefix","marcoutdir","school","alwaysemail","fromemail","ftplogin","ftppass","ftphost","queryfile","platform","pathtothis","maxdbconnections");
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
			my $pathtothis = $conf{"pathtothis"};
			my $maxdbconnections = $conf{"maxdbconnections"};
			my $queries = $mobUtil->readQueryFile($conf{"queryfile"});
			if($queries)
			{
				my %queries = %{$queries};
				
				my $school = $conf{"school"};
				my @types = ('adds','cancels','full');				
				my $platform = $conf{"platform"};#ebsco or summon
				my $fileNamePrefix = $conf{"fileprefix"}."_cancels_";
				if(!defined($platform))
				{
					print "You need to specify the platform 'ebsco' or 'summon'\n";
				}
				
				my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
				my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};
				if(scalar @dbUsers != scalar @dbPasses)
				{
					print "Sorry, you need to provide DB usernames equal to the number of DB passwords\n";
					exit;
				}
				
				my $users = $#dbUsers+1;
				my $passes = $#dbPasses+1;
				if($#dbUsers != $#dbPasses)
				{
					
					print "You have $users users and $passes passwords\nThere is a problem\n";
					exit;
				}
				print "Checking $users DB users\n";
				my $userloop = 0;
				my $dbHandler;
				foreach(@dbUsers)
				{
					my $thisuser = $_;
					my $thispass = @dbPasses[$userloop];
					print "$thisuser ";
					local $@;
					eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$thisuser,$thispass,$conf{"port"});};
					if ($@) 
					{
						print "FAILED\n";
					}
					else
					{
						print "Success\n";
					}
					undef $dbHandler;
					$userloop++;
				}
				my $dbuser = @dbUsers[0];
				my $dbpass = @dbPasses[0];					
				eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$dbuser,$dbpass,$conf{"port"});};
				if ($@) 
				{
					print "Could not login with $dbuser\n";
					exit;
				}
				
				my $sierraScraper;
				my %maxes;
				foreach(@types)
				{
					my $type = $_;
					print "**************\nChecking $type for $platform $school\n**************\n";					
					my $selectQuery = $mobUtil->findQuery($dbHandler,$school,$platform,$type,$queries);
					print "Got this query:\n$selectQuery\n";
					print "Checking the yield\n";
					local $@;
					eval{$sierraScraper = new sierraScraper($dbHandler,$log,
					"SELECT \$recordSearch FROM SIERRA_VIEW.BIB_RECORD WHERE RECORD_ID=1",
					$type,$conf{"school"},$pathtothis,$configFile,$maxdbconnections);};
					if($@)
					{
						print "Error starting the software\n";
					}
					else
					{
						my $max = $sierraScraper->findMaxRecordCount($selectQuery);
						$maxes{$type} = $max;
					}
				}
				print "**************\nFinal Yields\n**************\n";
				print $maxes{"adds"} . " adds\n";
				print $maxes{"cancels"} . " cancels\n";
				print $maxes{"full"} . " full\n";
				
			 }
		 }
	}
	else
	{
		print "Config file does not define 'logfile'\n";		
	}
 }
 
 exit;