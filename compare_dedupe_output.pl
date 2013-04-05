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
				my $query = "select marc,marc_altered,id from biblio.record_entry where marc<>marc_altered";
				my @results = @{$dbHandler->query($query)};
				my @records;
				foreach(@results)
				{
				
					my $row = $_;
					my @row = @{$row};
					my $xml = @row[0];
					my $xml2 = @row[1];
					$log->addLine("Comparing record ID: ".@row[2]);
					$xml =~ s/(<leader>.........)./${1}a/;
					$xml2 =~ s/(<leader>.........)./${1}a/;
					my $marc;
					my $marc2;
					eval {
						$marc = MARC::Record->new_from_xml($xml);
						$marc2 = MARC::Record->new_from_xml($xml2);
					};
					if ($@) {
						$log->addLine("could not parse  $@");
					}						
					else
					{
						$log->addLine("Now doing compare\n\n".$marc->as_formatted()."\n\n\n\nto:\n".$marc2->as_formatted);
						my @errors = @{$mobUtil->compare2MARCObjects($marc,$marc2)};
						my $errors;
						foreach(@errors)
						{
							$errors.= $_."\r\n";
						}
						$log->addLine($errors);
					}

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