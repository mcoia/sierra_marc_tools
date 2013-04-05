#!/usr/bin/perl


 use strict; 
 use Loghandler;
 use Mobiusutil;
 use DBhandler;
 use Data::Dumper;
 use MARC::File::XML (BinaryEncoding => 'utf8');
 
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
		my @reqs = ("dbhost","db","dbuser","dbpass","marcoutdir");
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
			my $dbHandler;
			
			 eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});};
			 if ($@) {
				$log->addLogLine("Could not establish a connection to the database");
				$valid = 0;
			 }
			 if($valid)
			 {
				
				my $marcOutFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"},"marcout","mrc");
				my $query = "select (select marc from biblio.record_entry where id=a.source) from metabib.title_field_entry a where lower(value) like '%harry pott%' and a.source in (select id from biblio.record_entry where not deleted)";
				my @results = @{$dbHandler->query($query)};
				my @records;
				foreach(@results)
				{
					my $row = $_;
					my @row = @{$row};
					if(@row[0] ne '970' &&@row[0] ne '971' &&@row[0] ne '972')
					{
						my $xml = @row[0];
						$xml =~ s/(<leader>.........)./${1}a/;
						my $marc;
						eval {
							$marc = MARC::Record->new_from_xml($xml);
						};
						if ($@) {
							$log->addLine("could not parse  $@");
						}						
						else
						{
							push(@records,$marc);
						}
					}
				}
				my $output;
				foreach(@records)
				{
				my @eight56s = $_->field('856');
				if($#eight56s>-1)
				{
					$output.=$_->as_usmarc();
				}
				}
				my $outputfile = new Loghandler($marcOutFile);
				$outputfile->addLine($output);
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