#!/usr/bin/perl
# 
# add9s.pl
#
# Usage: ./ebsco_discovery.pl conf_file.conf 
#
# Example Configure file:
# 
# logfile = /tmp/log.log 
# outputfile = /tmp/run/corrected9s.mrc
# 
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
		my @reqs = ("inputdirectory","outputfile"); 
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
			my @marcOutputRecords;
			my @info;
			my @files = grep {-d "$root/$_" && ! /^\.{1,2}$/} readdir($dh);
			for my $b(0..$#files)
			{
				my $file = MARC::File::USMARC->in($files[$b]);
				while ( my $marc = $file->next() ) 
				{	
					my @recID = $marc->field('856');
					if(defined @recID)
					{
						if($#recID>0)
						{
							for my $rec(0..$#recID)
							{	
								my @z = @recID[$rec]->subfield( 'z' );
								my @u = @recID[$rec]->subfield( 'u' );
								my $foundz = 0;
								for my $zz(0..$#z)
								{
									if(index(uc(@z[$zz]),uc("proxy01.mbts.edu"))>-1)
									{
										$foundz=1;
									}
								}
								my $foundu = 0;
								for my $uu(0..$#u)
								{
									if(index(uc(@u[$uu]),"MBTS")>-1)
									{
										$foundu=1;
									}
								}
								my $combine=$foundu+$foundz;
								if($combine==2)
								{
									
								}
								elsif($combine==1)
								{
								}
								else
								{
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
		$log->addLogLine(" ---------------- Script Ending ---------------- ");
	}
	else
	{
		print "Config file does not define 'logfile'\n";
		
	}
}

 exit;