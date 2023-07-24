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

 use lib qw(.);
 use strict; 
 use Loghandler;
 use Mobiusutil;
 use DBhandler;
 use recordItem;
 use sierraScraper;
 use Data::Dumper;
 use DateTime;
 use utf8;
 use Encode;
 use DateTime::Format::Duration;
 use MARC::Record;
 use MARC::File;
 use MARC::File::USMARC;
 use MARC::Batch;
 use File::stat;
 use File::Path qw(make_path);

 my $barcodeCharacterAllowedInEmail=2000;
 our $log;
 our $dbHandler;
 our %conf;
 our $finalMARCOutHandle;
 our $finalMARCOutHandle_bad;
 our $finalMARCOutHandle_electronic;
 our @allOutputFiles = ();
 our @allOutputFiles_bad = ();
 our @allOutputFiles_electric = ();
 our @previousLocs = ('');

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
	%conf = %{$conf};
	if ($conf{"logfile"})
	{
        my $type = @ARGV[1];
        if($type eq "thread")
        {
            # print "Threadtime\n";
            thread(\%conf);
        }
		$log = new Loghandler($conf->{"logfile"});
        $log->truncFile('');
        my $failString = "Success";
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
        my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
        my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};
        if(scalar @dbUsers != scalar @dbPasses)
        {
            print "Sorry, you need to provide DB usernames equal to the number of DB passwords\n";
            exit;
        }
        eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},@dbUsers[0],@dbPasses[0],$conf{"port"});};
        if ($@)
        {
            $log->addLogLine("Could not establish a connection to the database");
            $failString = "Could not establish a connection to the database";
            exit;
        }

        make_path($conf->{"marcoutdir"} . '/bibs',
        {
            chmod => 0777,
        }) if(!(-e $conf->{"marcoutdir"}. '/bibs'));

        my @locs = @{getLocationCodes()};
        foreach(@locs)
        {
            my $thisLoc = $_;
            overwriteQueryFile($thisLoc);
            push @previousLocs, $thisLoc;

            my $pathtothis = $conf{"pathtothis"};
            my $maxdbconnections = $conf{"maxdbconnections"};
            my $queries = $mobUtil->readQueryFile($conf{"queryfile"});
            if($queries)
            {
                my %queries = %{$queries};

                my $school = $thisLoc;

                $log->addLogLine(" ---------------- Script Starting ---------------- ");
                my $platform = $conf{"platform"};#ebsco or summon
                my $fileNamePrefix = $school;
                my $remoteDirectory = "/updates";

                my $dt   = DateTime->now(time_zone => "local"); 	
                my $fdate = $dt->ymd;

                my $outputMarcFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$fileNamePrefix."_".$fdate,"mrc");
                my $outputMarcFile_bad = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$fileNamePrefix."_".$fdate."_bad","mrc");
                my $outputMarcFile_electronic = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$fileNamePrefix."_".$fdate."_electronic","mrc");

                if($outputMarcFile ne "0")
                {
                    #Logging and emailing
                    $log->addLogLine("$school $platform $type *STARTING*");
                    $dt    = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
                    $fdate = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
                    my $ftime = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
                    my $dateString = "$fdate $ftime";  # "2013-02-16 05:00:00";
                    #Logging and emailing

                    my $marcOutFile = $outputMarcFile;
                    my $marcOutFile_bad = $outputMarcFile_bad;
                    my $marcOutFile_electronic = $outputMarcFile_electronic;
                    my $sierraScraper;
                    $valid=1;
                    my $selectQuery = $mobUtil->findQuery($dbHandler,$school,$platform,$type,$queries,@ARGV[2]);

                    # print "Path: $pathtothis\n";
                    # print $selectQuery."\n";
                    # exit;
                    my $gatherTime = DateTime->now();
                    local $@;
                    eval{$sierraScraper = new sierraScraper($dbHandler,$log,$selectQuery,0,$type,$school,$pathtothis,$configFile,$maxdbconnections, $conf{"libraryname"});};
                    if($@)
                    {
                        $valid=0;
                        print "failed to get data\n";
                        $failString = "Scrape Fail";
                    }

                    my $recCount=0;
                    my $badrecCount=0;
                    my $elecrecCount=0;
                    my $format = DateTime::Format::Duration->new
                    (
                        pattern => '%M:%S' #%e days, %H hours,
                    );
                    my $gatherTime = $sierraScraper->calcTimeDiff($gatherTime);
                    $gatherTime = $gatherTime / 60;
                    #$gatherTime = $format->format_duration($gatherTime);
                    my $afterProcess = DateTime->now(time_zone => "local");
                    my $difference = $afterProcess - $dt;
                    my $duration =  $format->format_duration($difference);
                    my $extraInformationOutput = "";
                    my $couldNotBeCut = "";
                    my $rps;
                    if($valid)
                    {
                        my @all = @{$sierraScraper->getAllMARC()};
                        my @marc = @{@all[0]}; 
                        my @tobig = @{$sierraScraper->getTooBigList()};
                        $extraInformationOutput = @tobig[0];
                        $couldNotBeCut = @tobig[1];
                        unlink $marcOutFile;
                        unlink $marcOutFile_bad;
                        unlink $marcOutFile_electronic;
                        open($finalMARCOutHandle, '>> '.$marcOutFile);
                        binmode($finalMARCOutHandle, ":utf8");
                        open($finalMARCOutHandle_bad, '>> '.$marcOutFile_bad);
                        binmode($finalMARCOutHandle_bad, ":utf8");
                        open($finalMARCOutHandle_electronic, '>> '.$marcOutFile_electronic);
                        binmode($finalMARCOutHandle_electronic, ":utf8");
                        my $output;
                        my $barcodes="";
                        my @back = @{processMARC(\@marc,$platform,$type,$school)};
                        # print Dumper(@back);
                        $extraInformationOutput.=@back[0];
                        $barcodes.=@back[1];
                        $couldNotBeCut.=@back[2];
                        $recCount+=@back[3];
                        $badrecCount+=@back[4];
                        $elecrecCount+=@back[5];

                        if(ref @all[1] eq 'ARRAY')
                        {
                            print "There were some files to process";
                            my @dumpedFiles = @{@all[1]};
                            foreach(@dumpedFiles)
                            {
                                @marc =();
                                my $marcfile = $_;
                                my $check = new Loghandler($marcfile);
                                if($check->fileExists())
                                {
                                    my $file = MARC::File::USMARC->in( $marcfile );
                                    my $r =0;
                                    while ( my $marc = $file->next() ) 
                                    {
                                        $r++;
                                        push(@marc,$marc);
                                    }
                                    $file->close();
                                    undef $file;
                                    print "Read $r records from $_\n";
                                    $check->deleteFile();
                                }
                                my @back = @{processMARC(\@marc,$platform,$type,$school)};
                                $extraInformationOutput.=@back[0];
                                $barcodes.=@back[1];
                                $couldNotBeCut.=@back[2];
                                $recCount+=@back[3];
                                $badrecCount+=@back[4];
                                $elecrecCount+=@back[5];
                            }

                        }
                        close($finalMARCOutHandle);
                        close($finalMARCOutHandle_bad);
                        close($finalMARCOutHandle_electronic);
                        unlink $marcOutFile if $recCount<1;
                        unlink $marcOutFile_bad if $badrecCount<1;
                        unlink $marcOutFile_electronic if $elecrecCount<1;
						push(@allOutputFiles, $marcOutFile) if $recCount>0;
						push(@allOutputFiles_bad, $marcOutFile_bad) if $badrecCount>0;
                        push(@allOutputFiles_electric, $marcOutFile_electronic) if $elecrecCount>0;

                        if(length($extraInformationOutput)>0)
                        {
                            $extraInformationOutput="These records were TRUNCATED due to the 100000 size limits: $extraInformationOutput \r\n\r\n";
                        }
                        if(length($couldNotBeCut)>0)
                        {
                            $couldNotBeCut="These records were OMITTED due to the 100000 size limits: $couldNotBeCut \r\n\r\n";
                        }
                    }

                    $log->addLogLine("$school $platform $type *ENDING*");
                }
                else
                {
                    $log->addLogLine("Output directory does not exist: ".$conf{"marcoutdir"} . '/bibs' );
                }

            }
            $log->addLogLine(" ---------------- Script Ending ---------------- ");
        }
		combineOutput();
	}
}
else
{
    print "Config file does not define 'logfile'\n";		
}
 
sub combineOutput
{
	my $dt   = DateTime->now(time_zone => "local"); 	
	my $fdate = $dt->ymd;
	my $combinedMarcFile = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$conf{"libraryname"}."_".$fdate,"mrc");
	my $combinedMarcFile_bad = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$conf{"libraryname"}."_".$fdate."_bad","mrc");
	my $combinedMarcFile_electric = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$conf{"libraryname"}."_".$fdate."_electronic","mrc");
    my $output_counts = $mobUtil->chooseNewFileName($conf->{"marcoutdir"} . '/bibs',$conf{"libraryname"}."_".$fdate."_bib_counts","txt");
    my %counts = (
    'good' => 0,
    'electronic' => 0,
    'bad' => 0,
    );
	my $combinedMarcFile_handle;
	my $combinedMarcFile_bad_handle;
	my $combinedMarcFile_elec_handle;
    my $output_counts_handle;
	unlink $combinedMarcFile;
	unlink $combinedMarcFile_bad;
	unlink $combinedMarcFile_electric;
    
	open($combinedMarcFile_handle, '>> '.$combinedMarcFile);
	binmode($combinedMarcFile_handle, ":utf8");
	open($combinedMarcFile_bad_handle, '>> '.$combinedMarcFile_bad);
	binmode($combinedMarcFile_bad_handle, ":utf8");
	open($combinedMarcFile_elec_handle, '>> '.$combinedMarcFile_electric);
	binmode($combinedMarcFile_elec_handle, ":utf8");
	foreach(@allOutputFiles)
	{
		my $file = MARC::File::USMARC->in( $_ );
		while ( my $marc = $file->next() )
		{
			eval{ print $combinedMarcFile_handle $marc->as_usmarc(); };
            $counts{'good'}++;
		}
		$file->close();
		undef $file;
        unlink $_;
	}
	foreach(@allOutputFiles_bad)
	{
		my $file = MARC::File::USMARC->in( $_ );
		while ( my $marc = $file->next() )
		{
			eval{ print $combinedMarcFile_bad_handle $marc->as_usmarc(); };
            $counts{'bad'}++;
		}
		$file->close();
		undef $file;
        unlink $_;
	}
    foreach(@allOutputFiles_electric)
	{
		my $file = MARC::File::USMARC->in( $_ );
		while ( my $marc = $file->next() )
		{
			eval{ print $combinedMarcFile_elec_handle $marc->as_usmarc(); };
            $counts{'electronic'}++;
		}
		$file->close();
		undef $file;
        unlink $_;
	}
	close($combinedMarcFile_handle);
	close($combinedMarcFile_bad_handle);
	close($combinedMarcFile_elec_handle);
    
    unlink $output_counts;
	open($output_counts_handle, '>> '.$output_counts);
	binmode($output_counts_handle, ":utf8");
    print $output_counts_handle "Good: " . $counts{'good'} . "\n";
    print $output_counts_handle "Electronic: " . $counts{'electronic'} . "\n";
    print $output_counts_handle "Bad: " . $counts{'bad'} . "\n";
    close($output_counts_handle);
}

 sub processMARC
 {
	my @marc = @{@_[0]};
	my $platform = @_[1];
	my $type = @_[2];
	my $school = @_[3];
	my $marcout = @_[4];
	my $extraInformationOutput='';
	my $barcodes;
	my $couldNotBeCut='';
	my $recCount=0;
    my $badrecCount=0;
    my $electricrecCount=0;
	foreach(@marc)
	{
		my $marc = $_;
		$marc->encoding( 'UTF-8' );
		my @count = @{$mobUtil->trucateMarcToFit($marc)};
        my $bad=0;
		if(@count[1]==1)
		{
			$marc = @count[0];
			print "Extrainformation adding: ".$marc->subfield('907',"a");
			$extraInformationOutput.=$marc->subfield('907',"a");
			print "Now it's\n $extraInformationOutput";
		}
		elsif(@count[1]==0)
		{
            $couldNotBeCut.=$marc->subfield('907',"a");
		}
        $marcout->appendLine($marc->as_usmarc()) if($marcout);
        if(!$marcout)
        {
            if(isMARCElectronic($marc))
            {
                appendFinalMARCFileLine_electronic($marc->as_usmarc());
                $electricrecCount++;
            }
            elsif( $marc->field('001') && $marc->field('008') && $marc->field('245') && $marc->field('907') )
            {
                appendFinalMARCFileLine($marc->as_usmarc());
                $recCount++;
            }
            else
            {
                appendFinalMARCFileLine_bad($marc->as_usmarc());
                $badrecCount++;
            }
        }
	}
	$extraInformationOutput = substr($extraInformationOutput,0,-1);
	my @ret=($extraInformationOutput,$barcodes,$couldNotBeCut,$recCount,$badrecCount,$electricrecCount);
	return \@ret;
 }
 
 sub isMARCElectronic
 {
     my $marc = shift;
     my $f008 = $marc->field('008');
     my $f006 = $marc->field('006');
     my @f856 = $marc->field('856');
     my $headerfound = 0;
     my $linkfound = 0;
     $headerfound = 1 if($f008 && $f008->data() =~ /.......................[oqs]/);
     $headerfound = 1 if($f006 && $f006->data() =~ /......[oqs]/);
     foreach(@f856)
     {
         my $thisField = $_;
         if($thisField->indicator(2) eq '0')
         {
             $linkfound =1 if($thisField->subfield('u'));
         }
     }
    return 1 if $linkfound && $headerfound;
    return 0;
 }

 sub thread
 {
	my %conf = %{@_[0]};
	my $previousTime=DateTime->now;
	my $mobUtil = new Mobiusutil();
	my $offset = @ARGV[2];
	my $increment = @ARGV[3];
	my $limit = $increment-$offset;
	my $pid = @ARGV[4];
	my $dbuser = @ARGV[5];
	my $typ = @ARGV[6];
    my $school = @ARGV[7];
	# print "Type = $typ\n";
	# print "$pid: $offset - $increment $dbuser\n";
    # exit;
	my $dbpass = "";
	my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
	my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};	
	my $i=0;
	foreach(@dbUsers)
	{
		if($dbuser eq $_)
		{
			$dbpass=@dbPasses[$i];
		}
		$i++;
	}
	my $pidWriter = new Loghandler($pid);
	my $log = new Loghandler($conf->{"logfile"});
	my $pathtothis = $conf{"pathtothis"};
	my $queries = $mobUtil->readQueryFile($conf{"queryfile"});
	my $type = @ARGV[1];
	my $platform = $conf{"platform"};
    my $title = $school;
    $title =~ s/[\s\t\\\/'"]/_/g;
    my $rangeWriter = new Loghandler("/tmp/rangepid_$title.pid");
    $rangeWriter->addLine("$offset $increment");
	my $dbHandler;
	eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$dbuser,$dbpass,$conf{"port"});};
	
	if ($@) {
		$pidWriter->truncFile("none\nnone\nnone\nnone\nnone\nnone\n$dbuser\nnone\n1\n$offset\n$increment");
		$rangeWriter->addLine("$offset $increment DEFUNCT");
		print "******************* I DIED DBHANDLER ********************** $pid\n";
	}
	else
	{
		my $dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$dbuser,$dbpass,$conf{"port"});
		#print "Sending off to get thread query: $school, $platform, $type";
		my $selectQuery = $mobUtil->findQuery($dbHandler,$school,$platform,$typ,$queries);		
		$selectQuery=~s/\$recordSearch/SIERRA_VIEW.BIB_RECORD.RECORD_ID/gi;
		$selectQuery.= " AND SIERRA_VIEW.BIB_RECORD.RECORD_ID > $offset AND SIERRA_VIEW.BIB_RECORD.RECORD_ID <= $increment";
		# print "Thread got this query\n\n$selectQuery\n\n";
		$pidWriter->truncFile("0");	
		#print "Thread started\n offset: $offset\n increment: $increment\n pidfile: $pid\n limit: $limit";
		my $sierraScraper;
		local $@;
		# print "Scraping:\n$dbHandler,$log,$selectQuery,$type,".$title.",$pathtothis,$configFile";
		eval{$sierraScraper = new sierraScraper($dbHandler,$log,$selectQuery,0,$type,$title,$pathtothis,$configFile,0,$conf{"libraryname"});};
		if($@)
		{
			#print "******************* I DIED SCRAPER ********************** $pid\n";
			$pidWriter->truncFile("none\nnone\nnone\nnone\nnone\nnone\n$dbuser\nnone\n1\n$offset\n$increment");
            print "Died with query:\n";
            print $sierraScraper->getLastQuery() ."\n";
			$rangeWriter->addLine("$offset $increment DEFUNCT");
			exit;
		}
        my $secondsElapsed = $sierraScraper->calcTimeDiff($previousTime);
        # print "Time to gather: $secondsElapsed\n";
        # print "Done querying DB: $secondsElapsed\n";
		my @diskDump = @{$sierraScraper->getDiskDump()};
		my $disk =@diskDump[0];
		my @marc =();
		my $check = new Loghandler($disk);
		if($check->fileExists())
		{
			local $@;
			my $finishedprocessing=0;
			my $file='';
			eval{
			#print "usmarc->\n";
				$file = MARC::File::USMARC->in( $disk );
				my $r =0;
				while ( my $marc = $file->next() ) 
				{						
					$r++;
					#print "encoding\n";
					#$marc->encoding('UTF-8');
					push(@marc,$marc);
				}
				#print "after pushing\n";
				$file->close();
				undef $file;
				#Just checking for errors - temporary file created and deleted
                my $randNum=int(rand(100000));

                my $marcout = new Loghandler('/tmp/t_'.$randNum.'.mrc');
				#print "processing\n";
				my @back = @{processMARC(\@marc,$platform,$type,$school,$marcout)};
				$finishedprocessing=1;
				$marcout->deleteFile();
			};
			
			if($@ && $finishedprocessing==0)
			{
                print "fail\n";
                print $check->getFileName();
                print "\n";
                # print "Died with query:\n";
                # foreach(@{$sierraScraper->getQueryLog()})
                # {
                    # print $_ ."\n";
                # }
				$check->deleteFile();
				$pidWriter->truncFile("none\nnone\nnone\nnone\nnone\nnone\n$dbuser\nnone\n1\n$offset\n$increment");
				$rangeWriter->addLine("$offset $increment BAD OUTPUT".$check->getFileName()."\t".$@);
				exit;
			}
		}		
		
		my $recordCount = $sierraScraper->getRecordCount();
		my @tobig = @{$sierraScraper->getTooBigList()};
		my $extraInformationOutput = @tobig[0];
		my $couldNotBeCut = @tobig[1];
		my @diskDump = @{$sierraScraper->getDiskDump()};
		my $disk =@diskDump[0];
		my $queryTime = $sierraScraper->getSpeed();
        # print "Time to gather: $secondsElapsed";
		$secondsElapsed = $sierraScraper->calcTimeDiff($previousTime);
        # print "\t\tfinished: $secondsElapsed\n";
		# print "Writing to thread File:\n$disk\n$recordCount\n$extraInformationOutput\n$couldNotBeCut\n$queryTime\n$limit\n$dbuser\n$secondsElapsed\n";
		my $writeSuccess=0;
		my $trys=0;
		while(!$writeSuccess && $trys<100)
		{
			$writeSuccess = $pidWriter->truncFile("$disk\n$recordCount\n$extraInformationOutput\n$couldNotBeCut\n$queryTime\n$limit\n$dbuser\n$secondsElapsed");
			if(!$writeSuccess)
			{
				print "$pid -  Could not write final thread output, trying again: $trys\n";
			}
			$trys++;
		}
		
	}
	
	exit;
 }
 
    sub getLocationCodes
    {
        my $query = <<'splitter';
            select location_code
            from
            sierra_view.bib_record_location
            group by 1
            order by 1

splitter

        my @ret = ();
        my @results = @{$dbHandler->query($query)};
        foreach(@results)
        {
            my $row = $_;
            my @row = @{$row};
            push @ret, @row[0];
        }
        return \@ret;
    }

    sub overwriteQueryFile
    {
        my $loc = shift;
        my $prevl = "";
        $prevl .= "\$\$$_\$\$," foreach(@previousLocs);
        $prevl = substr($prevl,0,-1);
        my $newQuery = "ebsco_$loc";
        $newQuery .= <<'splitter';
_full~~SELECT $recordSearch
                FROM
                sierra_view.bib_record
                join sierra_view.bib_record_location svbrl_inner on (sierra_view.bib_record.id = svbrl_inner.bib_record_id)
                left join sierra_view.bib_record_location prev_svbrl_inner on(prev_svbrl_inner.bib_record_id=sierra_view.bib_record.id and prev_svbrl_inner.location_code in(!!prevl!!))
                left join sierra_view.varfield svv on
                (
                    svv.record_id = sierra_view.bib_record.id and svv.marc_tag='001' and
                    (
                    svv.field_content~*'ebc' or
                    svv.field_content~*'emoe' or
                    svv.field_content~*'ewlebc' or
                    svv.field_content~*'fod' or
                    svv.field_content~*'jstor' or
                    svv.field_content~*'jstoreba' or
                    svv.field_content~*'kan' or
                    svv.field_content~*'lccsd' or
                    svv.field_content~*'lusafari' or
                    svv.field_content~*'park' or
                    svv.field_content~*'ruacls' or
                    svv.field_content~*'safari' or
                    svv.field_content~*'sage' or
                    svv.field_content~*'xrc' or
                    svv.field_content~*'emoeir'
                    )
                )
                where
                svv.record_id is null and
                prev_svbrl_inner.bib_record_id is null
                and svbrl_inner.location_code = $$!!loc!!$$
splitter

        $newQuery =~ s/!!loc!!/$loc/g;
        $newQuery =~ s/!!prevl!!/$prevl/g;

        my $qfile = new Loghandler($conf{'queryfile'});

        $qfile->truncFile($newQuery);
    
    }

sub appendFinalMARCFileLine
{
    my $marc = shift;
    print $finalMARCOutHandle "$marc";
}

sub appendFinalMARCFileLine_bad
{
    my $marc = shift;
    print $finalMARCOutHandle_bad "$marc";
}
sub appendFinalMARCFileLine_electronic
{
    my $marc = shift;
    print $finalMARCOutHandle_electronic "$marc";
}


exit;