#!/usr/bin/perl


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
 use MARC::Record;
 use MARC::File;
 use MARC::File::USMARC;
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
		
		
		
		my $db = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"});
		
		my $query = "select a.id,a.call_number,b.record from asset.copy a,asset.call_number b where b.record in (select record from asset.call_number where owning_lib in (2,4,101)) and a.call_number=b.id and a.deleted=false";
		
		my @results = @{$db->query($query)};
		my %five00s;
		my @callnumbers=();
		
		foreach(@results)
		{
			my @row = @{$_};
			my $copyid = @row[0];
			my $callnumber = @row[1];
			my $bibid = @row[2];
			$query = "SELECT MARC FROM BIBLIO.RECORD_ENTRY WHERE ID = $bibid and  marc like '%datafield tag=\"500\"%' and marc ~* '(Presented by)|(Donated)|(In Memory of)|(In Honor of)'";
			my @mxml = @{$db->query($query)};
			foreach(@mxml)
			{
				my @row2 =@{$_}; 
				my $xml = @row2[0];
				$xml =~ s/(<leader>.........)./${1}a/;
				my $marc = MARC::Record->new_from_xml($xml);
				my @fives = $marc->field("500");
				foreach(@fives)
				{
					my @data = $_->subfield('a');
					foreach(@data)
					{
						my $data = $_;
						if($data)
						{	
							$data =~ s/'/''/g;
							my $query = "INSERT INTO M_500FIELD_NOTE.POPLAR(copy_id,call_number,bib_id, FIVEHUNDRED) VALUES($copyid,$callnumber,$bibid,'$data')";
							my $ret = $db->update($query);
							if($ret){}
							else
							{
								print "There was an error inserting $data into the DB\n$query\n\n";
							}
						}
					}
					
				}
			}
		
		}
		my $temp = " marc like '%datafield tag=\"500\"%'";
		
		if(0)
		{
			my @files = </tmp/run/littledixie/*.mrc>;
			my @marc = ();
			my $count=0;
			my $file;
			foreach $file (@files) 
			{
				my $mfile = MARC::File::USMARC->in($file);
				while ( my $marc = $mfile->next())
				{
					$log->truncFile("Reading $file -> $count ");
					push(@marc,$marc);
					$log->addLogLine("Done");
					$count++;
				}
			}
			$log->addLogLine(" I read $count records... Now im converting to utf8");
			my $marcout = new Loghandler('/tmp/run/combined_little_dixie_utf8.mrc');
			$marcout->deleteFile();
			my $output;
			
			foreach(@marc)
			{
				my $marc = $_;
				$marc->encoding( 'UTF-8' );			
				$output.=$marc->as_usmarc();
			}
			$marcout->addLine($output);
		}
		$log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile' and 'marcoutdir'\n";
		
	}
 }
 
 exit;