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
 use email;
 use Encode;
 
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
		
		if(1)
		{
			
			#my @errors = @{$mobUtil->compare2MARCFiles($marcOutFile,"/tmp/run/trcc-catalog-updates-2013-03-22.out", $log, 907, "a" )};
							
							#my $errors;
							#foreach(@errors)
							#{
						#		$errors.= $_."\r\n";
					#		}
					
			my @errors = @{$mobUtil->compare2MARCFiles("/tmp/run/mout/Summon_ADDS_UCM_04172013.out","/tmp/run/testucm.out", $log, 907, "a" )};
			my $errors;
			foreach(@errors)
			{
				$errors.= $_."\r\n";
			}
			print $errors;
			my @tos = ('junk@monsterfro.com','scott@mobiusconsortium.org');										
			my $email = new email('junk@monsterfro.com',\@tos,0,0,\%conf);
			$email->send("Errors",encode("utf-8",$errors));
			print "done emailing\n";
			
			 if(0)
			 {
				 my $marcOutFile = $mobUtil->chooseNewFileName($conf->{"z3950server"},"marcout","mrc");
				 my $marcOutFile = "/jail/marcout";
				 my $marc;# = $mobUtil->makeMarcFromDBID($dbHandler,$log,420907798387);#420907796199);
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
		 
		 $log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile' and 'marcoutdir'\n";
		
	}
 }
 
 exit;