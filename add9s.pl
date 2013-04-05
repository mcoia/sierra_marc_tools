#!/usr/bin/perl
# 
# add9s.pl
#
# Usage: ./add9s.pl conf_file.conf marcinputfile1 marcinputfile2 marcinputfile3 .....
#
# Example Configure file:
# 
# logfile = /tmp/log.log 
# outputfile = /tmp/run/corrected9s.mrc
# schols = PB,GC,LLCL
#
#
# This script requires:
#
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record
# MARC::File
# 
# Blake Graham-Henderson MOBIUS blake@mobiusconsortium.org 2013-1-24
 
 use Loghandler;
 use Mobiusutil;
 use Data::Dumper;
 use MARC::Record;
 use MARC::File;
 
		
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
		my @reqs = ("shortnames","outputfile"); 
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
			my $inputError = 0;
			my @files;
			
			for my $b (1..$#ARGV)
			{
				my $log = new Loghandler(@ARGV[$b]);
				if(!$log->fileExists())
				{
					$inputError = 1;
					print "Could not locate file: ".@ARGV[$b]."\n";
				}
				else
				{
					push(@files, @ARGV[$b]);
				}
			}
			if($inputError)
			{	
				print "Usage ./add9s.pl [conf file] inputfile1 inputfile2 inputfile3 ... ... ... \n";
			}
			else
			{
				my @marcOutputRecords;
				my @schools = split(/,/,$conf{"shortnames"});
				for my $y(0.. $#schools)
				{
				print "Reading ".@schools[$y]."\n";
					@schools[$y]=$mobUtil->trim(@schools[$y]);
				}
				for my $b(0..$#files)
				{
					my $file = MARC::File::USMARC->in($files[$b]);
					while ( my $marc = $file->next() ) 
					{	
						my @recID = $marc->field('856');
						if(defined @recID)
						{
						
							#$marc->delete_fields( @recID );
							for my $rec(0..$#recID)
							{
								#print Dumper(@recID[$rec]);
								for my $t(0.. $#schools)
								{
									my @subfields = @recID[$rec]->subfield( '9' );
									my $schoolexists=0;
									for my $subs(0..$#subfields)
									{
									#print "Comparing ".@subfields[$subs]. " to ".@schools[$t]."\n";
										if(@subfields[$subs] eq @schools[$t])
										{
											print "Same!\n";
											$schoolexists=1;
										}
									}
									#print "School exists: $schoolexists\n";
									if(!$schoolexists)
									{
										#print "adding ".@schools[$t]."\n";
										@recID[$rec]->add_subfields('9'=>@schools[$t]);
									}
								}
							}
							#$marc->insert_fields_ordered(@recID);
						}
						push(@marcOutputRecords,$marc);
					}
				}
				
				my $marcout = new Loghandler($conf{"outputfile"});
				$marcout->deleteFile();
				my $output;
				foreach(@marcOutputRecords)
				{
					my $marc = $_;
					$output.=$marc->as_usmarc();
				}
				$marcout->addLine($output);
				
				#my @errors = @{$mobUtil->compare2MARCFiles($conf{"outputfile"},"/tmp/run/mo2go.20130118_2.dat", $log, "001","")};
				#foreach(@errors)
				#{
				#	print $_."\n";
				#}
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