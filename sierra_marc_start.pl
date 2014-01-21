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
 use DateTime;
 use utf8;
 use Encode;
 use DateTime::Format::Duration;
 
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
		my $file = MARC::File::USMARC->in('/tmp/run/barcodes.mrc');
		my @final = ();
		my $count=0;
		my @header;
		my @allOutCSV;
		while ( my $marc = $file->next())
		{
			$count++;
			my @marcOutput;
			my @fields = $marc->fields();
			foreach(@fields)
			{
				my $field = $_;
				my $tag = $field->tag();
				
				if($field->is_control_field())
				{
					
				}
				else
				{
					if($field->tag() eq '852')
					{
						my @subfields = $field->subfields();
						foreach(@subfields)
						{
							my @b = @{$_};
							if(@b[0] eq 'p')
							{
								push(@allOutCSV,@b[1]);
							}
						}
					}
				}
			}
			
		}
		my $l = new Loghandler($conf->{"csvout"});
		$l->deleteFile();
		my $txtout = "";
		
		foreach(@allOutCSV)
		{
			$txtout.="$_";
			$l->addLine($txtout);
			$txtout = "";
		}
		
		
		print "Found $count Records outputed: ".$conf->{"csvout"}."\n";
		if(0)
		{
			my @marcs = @{$mobUtil->getMarcFromZ3950("205.173.98.103/INNOPAC:A.T. STILL","\@attr 1=38 \"Writer's market\"",$log)};  #1889374
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
		if(0)
		{
			my @errors = @{$mobUtil->compare2MARCFiles("/tmp/run/marcout.mrc","/tmp/run/NoBarcodeFix.mrc", $log, 907, "a" )};
			my $errors;
			foreach(@errors)
			{
				$errors.= $_."\r\n";
			}
			#print $errors;
			my @tos = ('junk@monsterfro.com','scott@mobiusconsortium.org');										
			my $email = new email('junk@monsterfro.com',\@tos,0,0,\%conf);
			$email->send("Errors",encode("utf-8",$errors));
			print "done emailing\n";
		}
		
		if(0)
		{
				my $dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"});
				my $bcodes = "";
				my $count = 0;
				my $file = MARC::File::USMARC->in('/tmp/run/NoBarcodeFix.mrc');
					my @final = ();
					while ( my $marc = $file->next())
					{
						my $bcode = $marc->subfield('907',"a");
						$bcodes.=",".substr($bcode,2,7);
						$count++;
					}
				$bcodes = substr($bcodes,1,length($bcodes));
				my $selectQuery = "
				SELECT ID FROM SIERRA_VIEW.BIB_VIEW WHERE RECORD_NUM IN($bcodes)";
						print $selectQuery."\n\n$count";
				my $sierraScraper = new sierraScraper($dbHandler,$log,$selectQuery);
				my @marc = @{$sierraScraper->getAllMARC()};
				
				my $marcout = new Loghandler('/tmp/run/marcout.mrc');
				$marcout->deleteFile();
				my $output;
				
				foreach(@marc)
				{
					my $marc = $_;
					$marc->encoding( 'UTF-8' );
					my @count = @{$mobUtil->trucateMarcToFit($marc)};
					#print @count[1]."\n";
					my $addThisone=1;
					if(@count[1]==1)
					{
						$marc = @count[0];
					}
					elsif(@count[1]==0)
					{
						$addThisone=0;
					}
					
					if($addThisone) #ISO2709 MARC record is limited to 99,999 octets 
					{	
						$output.=$marc->as_usmarc();
					}
					
				}
				$marcout->addLine($output);
		}
		if(0)
		{
			
			#my @errors = @{$mobUtil->compare2MARCFiles($marcOutFile,"/tmp/run/trcc-catalog-updates-2013-03-22.out", $log, 907, "a" )};
							
							#my $errors;
							#foreach(@errors)
							#{
						#		$errors.= $_."\r\n";
					#		}
			

			my $firstFile = "/tmp/run/mout/tempmarc0.mrc";
			my $loge = new Loghandler($firstFile);
			my $outputMarcFile = $mobUtil->chooseNewFileName("/tmp/run","dump","mrc");
			my @append = ("/tmp/run/mout/tempmarc0.mrc","/tmp/run/mout/tempmarc1.mrc","/tmp/run/mout/tempmarc4.mrc","/tmp/run/mout/tempmarc7.mrc");
			my $logo = new Loghandler($outputMarcFile);
			my $out="";
			#my @lines = @{$loge->readFile()};
			my $t = "";
			#my $t = @lines[0];
			my $pointer = 0;
			my $fileout=0;
			foreach(@append)
			{
				$loge = new Loghandler($_);
				my @lines = @{$loge->readFile()};
				$out.=@lines[0];
			}
			$loge=new Loghandler("/tmp/run/all.mrc");
			$loge->addLine($out);
			if(0)
			{
			while($pointer<length($t))
			{
				$fileout++;
				if( $fileout%10000000 == 0 )
				{
					$logo->addLine($out);
					$outputMarcFile = $mobUtil->chooseNewFileName("/tmp/run","dump","mrc");
					$logo = new Loghandler($outputMarcFile);
					$out="";
					$fileout=0;
				}
				$out.=substr($t,$pointer,1);
				$pointer++;
			}
			$logo->addLine($out);
			}
			if(0)
			{
			my $writing=1;
			while($pointer<length($t))
			{
				if(!$writing)
				{
				
				my $mod = $pointer % 10;
				if($mod==0)
				{
					my $temp = substr($t,$pointer,50);
					print "$temp\n";
				}
					if(substr($t,$pointer,5) eq 'OCoLC')
					{
						$writing=1;
						$logo->addLine($out);
						$out="";
						$logo = new Loghandler("/tmp/run/after.mrc");
						$pointer-=5;
					}
				}
				else
				{
					if(substr($t,$pointer,10) eq ".b1229987x")
					{
						print "found badness on $pointer\n";
						$writing=0;
					}
					else
					{
						$out.=substr($t,$pointer,1);
					}
				}
				$pointer++;
			}
			}
			$logo->addLine($out);
			if(0)
			{
			my $file = MARC::File::USMARC->in($firstFile);
			my @final = ();
			while ( my $marc = $file->next() )
			{
				my $bcode = $marc->subfield('907',"a");
				if($bcode ne ".b12921968" && $bcode ne ".b12685537")
				{
					#print "$bcode\n";
					my @re = @{$mobUtil->trucateMarcToFit($marc)};
					if($@)
					{
						print "error $bcode\n";
					}
					else
					{
						$marc = @re[0];				
						my $worked = @re[1];
						if($worked==0)
						{
							print "Didn't work: $bcode\n";
						}
						push(@final,$marc);
					}
				}
			}
			print "Now going to outputs";
			my $output;
			foreach(@final)
			{
				my $marc = $_;
				$marc->encoding( 'UTF-8' );
				$output.=$marc->as_usmarc();
			}
my $marcout = new Loghandler("/tmp/run/bigswitch.mrc");
$marcout->deleteFile();
$marcout->addLine($output);
		}
			#my @errors = @{$mobUtil->compare2MARCFiles("/tmp/run/mout/Summon_ADDS_UCM_04172013.out","/tmp/run/testucm.out", $log, 907, "a" )};
			#my $errors;
			#foreach(@errors)
			#{
			#	$errors.= $_."\r\n";
			#}
			#print $errors;
			#my @tos = ('junk@monsterfro.com','scott@mobiusconsortium.org');										
			#my $email = new email('junk@monsterfro.com',\@tos,0,0,\%conf);
			#$email->send("Errors",encode("utf-8",$errors));
			#print "done emailing\n";
			
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