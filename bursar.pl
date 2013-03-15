#!/usr/bin/perl

 use lib qw(../);
 use strict; 
 use Loghandler;
 use Mobiusutil;
 use DBhandler;
 use sierraScraper;
 use Data::Dumper;
 use Date::Manip;
 
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
		my @reqs = ("dbhost","db","dbuser","dbpass","bursaroutputdir");
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
				my $dt = DateTime->now; 
				$dt = $dt->subtract(days=>1);
				if($dt->local_day_of_week() == 1)#correct for weekend
				{				
					$dt = $dt->subtract(days=>2);					
				}
				my $datestamp = $dt->year."-".$mobUtil->padLeft($dt->month,2,'0')."-".$mobUtil->padLeft($dt->day,2,'0');
				my $scraper = new sierraScraper($dbHandler,$log,"SELECT INVOICE_NUM FROM SIERRA_VIEW.FINE WHERE ASSESSED_GMT > TO_DATE('$datestamp','YYYY-MM-DD')");
				$scraper->getBursarInfo($conf{"bursaroutputdir"});
			 }
		}
		$log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile'\n";
		
	}
	
	
}
	

