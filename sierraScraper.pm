#!/usr/bin/perl
#
# sierraScraper.pm
# 
# Requires:
# 
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# 
# This code will scrape the sierra database for all of the values that create MARC records
#
# 
# Usage: 
# my $log = new Loghandler("path/to/log/file");
# my $dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});
# 
# my $sierraScraper = new sierraScraper($dbHandler,$log,"SELECT RECORD_ID FROM SIERRA_VIEW.BIB_RECORD LIMIT 10");
#
# You can get the resulting MARC Records in an array of MARC::Records like this:
#
# my @marc = @{$sierraScraper->getAllMARC()};
#
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24

package sierraScraper;
 use MARC::Record;
 use Loghandler;
 use recordItem;
 use strict; 
 use Data::Dumper;
 use Mobiusutil;
 use Date::Manip;
 
 sub new   #DBhandler object,Loghandler object, Array of Bib Record ID's matching sierra_view.bib_record
 {
	my $class = shift;
	my %k=();
	my %d=();
	my %e=();
	my %f=();
	my %g=();
	my %h=();
	my $mobutil = new Mobiusutil();
    my $self = 
	{
		'dbhandler' => shift,
		'log' => shift,
		'bibids' => shift,
		'mobiusutil' => $mobutil,
		'nine45' =>  \%k,
		'nine07' =>  \%d,
		'specials' => \%e,
		'leader' => \%f,
		'standard' => \%g,
		'nine98' => \%h,
		'selects' => ""
	};
	bless $self, $class;
	gatherDataFromDB($self);
    return $self;
 }
 
 sub gatherDataFromDB
 {
	my $self = @_[0];
	figureSelectStatement($self);
	stuffStandardFields($self);
	stuffSpecials($self);
	stuff945($self);
	stuff907($self);
	stuff998alternate($self);
	stuffLeader($self);
 }
 
 sub getSingleStandardFields
 {	
	my ($self) = @_[0];
	my $idInQuestion = @_[1];
	my $log = $self->{'log'};
	my %standard = %{$self->{'standard'}};
	if(exists $standard{$idInQuestion})
	{
		#print "It exists\n";
	}
	return \@{$standard{$idInQuestion}};
 }
 
 sub stuffStandardFields
 {
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my $mobUtil = $self->{'mobiusutil'};
	my %standard = %{$self->{'standard'}};
	my $selects = $self->{'selects'};
	
	my $query = "SELECT A.MARC_TAG,A.FIELD_CONTENT,
	(SELECT MARC_IND1 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
	(SELECT MARC_IND2 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
	RECORD_ID FROM SIERRA_VIEW.VARFIELD_VIEW A WHERE A.RECORD_ID IN($selects) ORDER BY A.MARC_TAG, A.OCC_NUM";
	#print $query."\n";
	my @results = @{$dbHandler->query($query)};
	my @records;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		if(@row[0] ne '970' &&@row[0] ne '971' &&@row[0] ne '972')
		{
			my $recordID = @row[4];
			if(!exists $standard{$recordID})
			{
				my @a = ();
				$standard{$recordID} = \@a;
			}
			my $ind1 = @row[2];
			my $ind2 = @row[3];
			
			if(length($ind1)<1)
			{
				$ind1=' ';
			}
			
			if(length($ind2)<1)
			{
				$ind2=' ';
			}
			
			push(@{$standard{$recordID}},new recordItem(@row[0],$ind1,$ind2,@row[1]));
		}
	}
	$self->{'standard'} = \%standard;
	
 }
 
 sub stuffSpecials
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %specials = %{$self->{'specials'}};
	my $mobiusUtil = $self->{'mobiusutil'};	
	my $selects = $self->{'selects'};
	
	my $concatPhrase = "CONCAT(";
	for my $i(0..39)
	{
		my $string = sprintf( "%02d", $i );  #Padleft 0's for a total of 2 characters
		$concatPhrase.="p$string,";
	}
	$concatPhrase=substr($concatPhrase,0,length($concatPhrase)-1).")";
	my $query = "SELECT CONTROL_NUM,$concatPhrase,RECORD_ID FROM SIERRA_VIEW.CONTROL_FIELD WHERE RECORD_ID IN($selects)";
	#print "$query\n";
	my @results = @{$dbHandler->query($query)};
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[2];
		my $recordItem;
		if(!exists $specials{$recordID})
		{
			my @a = ();
			$specials{$recordID} = \@a;
		}
		if(@row[0] eq '6')
		{
			push(@{$specials{$recordID}},new recordItem('006','','',$mobiusUtil->makeEvenWidth(@row[1],44)));
		}
		elsif(@row[0] eq '7')
		{
			push(@{$specials{$recordID}},new recordItem('007','','',$mobiusUtil->makeEvenWidth(@row[1],44)));
		}
		elsif(@row[0] eq '8')
		{
			push(@{$specials{$recordID}},new recordItem('008','','',$mobiusUtil->makeEvenWidth(@row[1],40)));
		}
	}
	#print Dumper(\%specials);
	$self->{'specials'} = \%specials;
}

sub stuffLeader
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %leader = %{$self->{'leader'}};
	my $mobiusUtil = $self->{'mobiusutil'};	
	my $selects = $self->{'selects'};
	
	my $query = "SELECT
	RECORD_ID,
	RECORD_STATUS_CODE,
	RECORD_TYPE_CODE,
	BIB_LEVEL_CODE,
	CONTROL_TYPE_CODE,
	CHAR_ENCODING_SCHEME_CODE,
	ENCODING_LEVEL_CODE,
	DESCRIPTIVE_CAT_FORM_CODE,
	MULTIPART_LEVEL_CODE
    FROM SIERRA_VIEW.LEADER_FIELD A WHERE A.RECORD_ID IN($selects)";
	#print "$query\n";
	my @results = @{$dbHandler->query($query)};
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		
		for my $i (1..$#row)
		{
			if(length(@row[$i])!=1)
			{
				#print "Leader: Correcting empty field\n";
				@row[$i] = " ";
			}
		}
		
		my $firstPart = @row[1].@row[2].@row[3].@row[4].@row[5];
		my $lastPart = @row[6].@row[7].@row[8];
		#print "First part: $firstPart Last Part: $lastPart\n";
		my @add = ($firstPart,$lastPart);
		if(!exists $leader{$recordID})
		{
			$leader{$recordID} = \@add;
		}
		else
		{
			$log->addLogLine("Leader Scrape: There were more than one leader row returned from query $query");
		}
		
	}
	#print Dumper(\%leader);
	$self->{'leader'} = \%leader;
}

sub stuff945
{

	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nineHundreds = %{$self->{'nine45'}};
	my $mobiusUtil = $self->{'mobiusutil'};
	my $selects = $self->{'selects'};
	
	
	my $query = "SELECT
        (SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID = A.ID),
        A.ID,
        (SELECT MARC_IND1 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
        (SELECT MARC_IND2 FROM SIERRA_VIEW.SUBFIELD_VIEW WHERE VARFIELD_ID=A.ID LIMIT 1),
        CONCAT('|g',A.COPY_NUM) AS \"g\",
        (SELECT CONCAT('|i',BARCODE) FROM SIERRA_VIEW.ITEM_VIEW WHERE ID=A.ID) AS \"i\",
        CONCAT('|j',A.AGENCY_CODE_NUM) AS \"j\",
        CONCAT('|l',A.LOCATION_CODE) AS \"l\",
        CONCAT('|o',A.ICODE2) AS \"o\",
        CONCAT('|p\$',TRIM(TO_CHAR(A.PRICE,'9999999999990.00'))) AS \"p\",
        CONCAT('|q',A.ITEM_MESSAGE_CODE) AS \"q\",
        CONCAT('|r',A.OPAC_MESSAGE_CODE) AS \"r\",
        CONCAT('|s',A.ITEM_STATUS_CODE) AS \"s\",
        CONCAT('|t',A.ITYPE_CODE_NUM) AS \"t\",
        CONCAT('|u',A.CHECKOUT_TOTAL) AS \"u\",
        CONCAT('|v',A.RENEWAL_TOTAL) AS \"v\",
        CONCAT('|w',A.YEAR_TO_DATE_CHECKOUT_TOTAL) AS \"w\",
        CONCAT('|x',A.LAST_YEAR_TO_DATE_CHECKOUT_TOTAL) AS \"x\",
        (SELECT CONCAT('|z',TO_CHAR(CREATION_DATE_GMT, 'MM-DD-YY')) FROM SIERRA_VIEW.RECORD_METADATA WHERE ID=A.ID) AS \"z\"
        FROM SIERRA_VIEW.ITEM_RECORD A WHERE A.ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN ($selects))";
	#print "$query\n";
	my @results = @{$dbHandler->query($query)};
	my %tracking; # links recordItems objects to item Numbers without having to search everytime
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $ind1 = @row[2];
		my $ind2 = @row[3];
		if(length($ind1)<1)
		{
			$ind1=' ';
		}
		
		if(length($ind2)<1)
		{
			$ind2=' ';
		}
		
		my $recordID = @row[0];		
		my $subItemID = @row[1];
		
		
		if(!exists $nineHundreds{$recordID})
		{
			my @a = ();
			my %b;
			$nineHundreds{$recordID} = \@a;
			$tracking{$recordID} = \%b;
		}
		
		my %t = %{$tracking{$recordID}};
		if(!exists $t{$subItemID})
		{
			$t{$subItemID} = $#{$nineHundreds{$recordID}}+1;
			$tracking{$recordID} = \%t;
		}
		else
		{
			$log->addLogLine("945 Scrape: Huston, we have a problem, the query returned more than one of the same item(duplicate 945 record) - $recordID");
		}
		my $all;
		foreach my $b (4..$#row)
		{
			$all = $all.@row[$b];
		}
		push(@{$nineHundreds{$recordID}},new recordItem('945',$ind1,$ind2,$all));
		
	}

	$query = "SELECT
	RECORD_ID,
	VARFIELD_TYPE_CODE,
	MARC_TAG,
	FIELD_CONTENT,
	(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID=A.RECORD_ID) AS \"BIB_ID\",
	RECORD_NUM
	FROM SIERRA_VIEW.VARFIELD_VIEW A WHERE RECORD_ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN($selects))
	AND VARFIELD_TYPE_CODE !='a'";
	#print "$query\n";
	@results = @{$dbHandler->query($query)};
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $trimmedID = $mobiusUtil->trim(@row[2]);
		if(exists $nineHundreds{@row[4]})
		{
			my @thisArray = @{$nineHundreds{@row[4]}};
			if(exists ${$tracking{@row[4]}}{@row[0]})
			{
				my $thisArrayPosition = ${$tracking{@row[4]}}{@row[0]};				
				if(($trimmedID eq '082') || ($trimmedID eq '090') || ($trimmedID eq '086'))
				{
				
					my $thisRecord = @thisArray[$thisArrayPosition];
					$thisRecord->addData(@row[3]);
					my $checkDigit = calcCheckDigit($self,@row[5]);
					$thisRecord->addData("|y.i".@row[5].$checkDigit);
					my $recordID = @row[4];
					my $subItemID = @row[0];
					foreach(@results) # Find Null marc_tag values related to 082 and 090 and 086
					{
						my $rowsearch = $_;
						my @rowsearch = @{$rowsearch};
						if((@rowsearch[0] == @row[0]) && (@rowsearch[2] eq ''))
						{
							if(@rowsearch[1] eq 'b')
							{
								$thisRecord->addData('|i'.@rowsearch[3]);
							}
							elsif(@rowsearch[1] eq 'v')
							{
								$thisRecord->addData('|c'.@rowsearch[3]);
							}
							elsif(@rowsearch[1] eq 'x')
							{
								$thisRecord->addData('|n'.@rowsearch[3]);
							}
							elsif(@rowsearch[1] eq 'm')
							{
								$thisRecord->addData('|m'.@rowsearch[3]);
							}
							else
							{
								if((@rowsearch[1] ne 'n') && (@rowsearch[1] ne 'p')&& (@rowsearch[1] ne 'r'))
								{
									$log->addLogLine("This was a related 082,090,086 item(".@row[0].") and bib($recordID)value but I don't know what it is: ".@rowsearch[1]." = ".@rowsearch[3]);
								}
							}
						}
					}
					@{$nineHundreds{@row[4]}}[$thisArrayPosition] = $thisRecord;
				}
				elsif( $trimmedID ne '')
				{
					$log->addLogLine("I found a row and it looks like this \"$trimmedID\" = ".@row[3]);
					#push(@{$nineHundreds{@row[4]}},new recordItem(@row[2],'','',@row[3]));;
				}
			}
			else
			{
				if(@row[2] eq '086')
				{
					$log->addLogLine("I found a row and it looks like this \"$trimmedID\" = ".@row[3]);
					$log->addLogLine("I'm adding that as a 945");
					push(@{$nineHundreds{@row[4]}},new recordItem('945','','',@row[3]));
				}
				else
				{
					$log->addLogLine("945 scrape: Strange results: ".@row[0]." ".@row[1]." ".@row[2]." ".@row[3]." ".@row[4]);
				}
			}
			
		}
		else
		{
			$log->addLogLine("There were items in varfield_view that didn't appear before now:");
			$log->addLogLine("Bib id  = ".@row[4]." Item id = ".@row[0].",$trimmedID = ".@row[3]);
			$log->addLogLine("This was not added to the marc array");
		}
	}
	$self->{'nine45'} = \%nineHundreds;
}

sub stuff907
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nine07 = %{$self->{'nine07'}};
	my $selects = $self->{'selects'};
	my $query = "SELECT A.ID,RECORD_TYPE_CODE,RECORD_NUM,
	CONCAT(
	CONCAT('|b',TO_CHAR(A.RECORD_LAST_UPDATED_GMT, 'MM-DD-YY')),
	CONCAT('|c',TO_CHAR(A.CREATION_DATE_GMT, 'MM-DD-YY'))
	)
	FROM SIERRA_VIEW.RECORD_METADATA A WHERE A.ID IN($selects)";
	#print "$query\n";
	my @results = @{$dbHandler->query($query)};
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		my $checkDigit = calcCheckDigit($self,$row[2]);
		my $subA = "|a.".@row[1].@row[2].$checkDigit;
		if(!exists $nine07{$recordID})
		{
			my @a = ();
			$nine07{$recordID} = \@a;
		}
		push(@{$nine07{$recordID}},new recordItem('907','','',$subA.@row[3]));
	}
	
	$self->{'nine07'} = \%nine07;
}

sub stuff998
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nine98 = %{$self->{'nine98'}};
	my $mobiusUtil = $self->{'mobiusutil'};
	my $selects = $self->{'selects'};
	my $query = "SELECT ID,
	CONCAT(
	CONCAT('|b',TO_CHAR(CATALOGING_DATE_GMT, 'MM-DD-YY')),
	CONCAT('|c',BCODE1),
	CONCAT('|d',BCODE2),
	CONCAT('|e',BCODE3),
	CONCAT('|f',LANGUAGE_CODE),
	CONCAT('|g',COUNTRY_CODE),
	CONCAT('|h',SKIP_NUM)
	)
	FROM SIERRA_VIEW.BIB_VIEW WHERE ID IN($selects)";
	#print "$query\n";
	my @results = @{$dbHandler->query($query)};
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		if(!exists $nine98{$recordID})
		{
			my @a = ();
			$nine98{$recordID} = \@a;
		}
		else
		{
			#print "$recordID - Error - There is more than one row returned when creating the 998 record\n";
		}
		push(@{$nine98{$recordID}},new recordItem('998','','',@row[1]));
	}
	$query = "SELECT 
	(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID = A.ID),
	SUBSTR(LOCATION_CODE,1,LENGTH(LOCATION_CODE)-2) FROM SIERRA_VIEW.ITEM_RECORD A WHERE A.ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN($selects))";

	#print "$query\n";
	@results = @{$dbHandler->query($query)};
	my %counts;
	my %total;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		my $location = @row[1];
		if(!exists $nine98{$recordID})
		{
			$log->addLogLine("Stuffing 998 Field $recordID - Error - There is more than one row returned when creating the 998 record");
		}
		else
		{
			if(!exists $counts{$recordID})
			{
				#$counts{$recordID} = {};
				${$counts{$recordID}}{$location}=0;
				${$total{$recordID}}=0;
			}
			${$counts{$recordID}}{$location}++;
			${$total{$recordID}}++;
		}
	}
	while ((my $internal, my $value ) = each(%counts))
	{
		my %tt = %{$value};
		my $total = ${$total{$internal}};
		my $addValue = "";
		while((my $internal2, my $value2) = each(%tt))
		{
			if($value2 == 1)
			{
				$addValue.="|a".$internal2;
			}
			else
			{
				$addValue.="|a(".$value2.")".$internal2;
			}
		}
		#print "Adding $addValue\n";
		@{$nine98{$internal}}[0]->addData($addValue."|i$total");
	}
	
	
	$self->{'nine98'} = \%nine98;
}

# This was created to try another method of counting the copies at each of the locations
# based upon the information located in sierra_view.bib_record_location instead of sierra_view.item_record.
# There is some sort of unusual behavior in the sierra desktop client when there is only 1 945 record.
# It looks like it subtracts 1 from the copy number when there is only 1 row returned. Pretty odd.

sub stuff998alternate
{
	my ($self) = @_[0];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my %nine98 = %{$self->{'nine98'}};
	my $mobiusUtil = $self->{'mobiusutil'};
	my $selects = $self->{'selects'};
	my $query = "SELECT ID,
	CONCAT(
	CONCAT('|b',TO_CHAR(CATALOGING_DATE_GMT, 'MM-DD-YY')),
	CONCAT('|c',BCODE1),
	CONCAT('|d',BCODE2),
	CONCAT('|e',BCODE3),
	CONCAT('|f',LANGUAGE_CODE),
	CONCAT('|g',COUNTRY_CODE),
	CONCAT('|h',SKIP_NUM)
	)
	FROM SIERRA_VIEW.BIB_VIEW WHERE ID IN($selects)";
	#print "$query\n";
	my @results = @{$dbHandler->query($query)};
	
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		if(!exists $nine98{$recordID})
		{
			my @a = ();
			$nine98{$recordID} = \@a;
		}
		else
		{
			#print "$recordID - Error - There is more than one row returned when creating the 998 record\n";
		}
		push(@{$nine98{$recordID}},new recordItem('998','','',@row[1]));
	}
	$query = "SELECT 
	BIB_RECORD_ID,LOCATION_CODE,COPIES
	FROM SIERRA_VIEW.BIB_RECORD_LOCATION A WHERE A.BIB_RECORD_ID IN($selects) 
	AND LOCATION_CODE!='multi'";
	
	my $query2="SELECT BIB_RECORD_ID,COUNT(*) FROM SIERRA_VIEW.BIB_RECORD_LOCATION WHERE BIB_RECORD_ID IN ($selects) GROUP BY BIB_RECORD_ID";
	
	#print "$query\n";
	@results = @{$dbHandler->query($query)};
	my @results2 = @{$dbHandler->query($query2)};
	
	my %counts;
	my %total;
	foreach(@results)
	{
		my $row = $_;
		my @row = @{$row};
		my $recordID = @row[0];
		my $location = @row[1];
		my $copies = @row[2];
		if(!exists $nine98{$recordID})
		{
			$log->addLogLine("Stuffing 998 Field $recordID - Error - There is more than one row returned when creating the 998 record");
		}
		else
		{
			if(!exists $counts{$recordID})
			{
				#$counts{$recordID} = {};
				${$counts{$recordID}}{$location}=0;
				${$total{$recordID}}=0;
			}
			my $subtractBy=0;
			foreach(@results2)
			{
				my $row2 = $_;
				my @row2 = @{$row2};
				if(@row2[0] eq $recordID)
				{
					if(@row2[1] eq '1')
					{
						$subtractBy=1;
					}
				}
			}
			my $total = $copies-$subtractBy;
			if($total<1)
			{
				$total=1;
			}
			${$counts{$recordID}}{$location}+=$total;
			${$total{$recordID}}+=$copies;
		}
	}
	while ((my $internal, my $value ) = each(%counts))
	{
		my %tt = %{$value};
		my $total = ${$total{$internal}};
		my $addValue = "";
		while((my $internal2, my $value2) = each(%tt))
		{
			if($value2 == 1)
			{
				$addValue.="|a".$internal2;
			}
			else
			{
				$addValue.="|a(".$value2.")".$internal2;
			}
		}
		#print "Adding $addValue\n";
		@{$nine98{$internal}}[0]->addData($addValue."|i$total");
	}
	
	
	$self->{'nine98'} = \%nine98;
}



 
 sub getSingleMARC
 {
	my ($self) = @_[0];
	my $recID = @_[1];
	my $dbHandler = $self->{'dbhandler'};
	my $log = $self->{'log'};
	my $mobiusUtil = $self->{'mobiusutil'};
	my %nine45 = %{$self->{'nine45'}};
	my %nine07 =%{$self->{'nine07'}};
	my %nine98 =%{$self->{'nine98'}};
	my %specials = %{$self->{'specials'}};
	my %standard = %{$self->{'standard'}};
	my %leader = %{$self->{'leader'}};
	my @try = ('nine45','nine07','nine98','specials','standard');
	my @marcFields;
	
	foreach(@try)
	{
		@marcFields = @{pushMARCArray($self,\@marcFields,$_,$recID)};
	}
	
	#Sort by MARC Tag
	my @tags;
	my $changed = 1;
	while($changed)
	{
		$changed=0;
		for my $i (0..$#marcFields)
		{
			if($i+1<$#marcFields)
			{
				my $thisone = @marcFields[$i]->tag();
				my $nextone;
				eval{$nextone = @marcFields[$i+1]->tag();};
				if ($@) 
				{
					print "Can't call method tag\ni= $i count = $#marcFields \nRecord ID = $recID";
					#print Dumper(@marcFields);
					$log->addLogLine("Can't call method \"tag\" on an undefined value");
				}
				else
				{
					if($nextone lt $thisone)
					{
						$changed=1;
						my $temp = @marcFields[$i];
						@marcFields[$i] = @marcFields[$i+1];
						@marcFields[$i+1] = $temp;
					}
				}
			}
		}
	}
	
	#create MARC:Record Object and stuff fields
	my $ret = MARC::Record->new();
	
	$ret->append_fields( @marcFields );
	#Alter the Leader to match Sierra
	my $leaderString = $ret->leader();
	#print "Leader was $leaderString\n";
	if(exists $leader{$recID})
	{
		my @thisLeaderAdds = @{$leader{$recID}};
		#print Dumper(\@thisLeaderAdds);
		$leaderString = $mobiusUtil->insertDataIntoColumn($leaderString,@thisLeaderAdds[0],6);
		$leaderString = $mobiusUtil->insertDataIntoColumn($leaderString,@thisLeaderAdds[1],18);
		#print "Leader is now $leaderString\n";
		$ret->leader($leaderString);
	}
	$ret->encoding( 'UTF-8' );
	return $ret;
 }
 
 sub pushMARCArray
 {
	my ($self) = @_[0];
	my @marcFields = @{$_[1]};
	my %group = %{$self->{$_[2]}};
	my $recID = @_[3];
	
	my @fields;
	if(exists $group{$recID})
	{
		#print Dumper(\%group);
		@fields = $group{$recID};
		for my $i (0..$#fields)
		{
			my @recordItems = @{@fields[$i]};
			foreach(@recordItems)
			{
				##Sometimes there isn't enough data in the subfield to create a field object
				# So we check for undef value returned from getMARCField()
				my $mfield = $_->getMARCField();  
				if($mfield!=undef)
				{
					push(@marcFields,$mfield);
				}
			}

		}
	}
	return \@marcFields;
 }
 
 sub getAllMARC
 {
	my $self = @_[0];
	my %standard = %{$self->{'standard'}};
	my @marcout;
	
	while ((my $internal, my $value ) = each(%standard))
	{
		push(@marcout,getSingleMARC($self,$internal));
	}
	return \@marcout;
 }
 
 sub figureSelectStatement
 { 
	my $self = @_[0];
	my $test = $self->{'bibids'};
	my $dbHandler = $self->{'dbhandler'};
	my $results = "";
	my $mobUtil = $self->{'mobiusutil'};
	if(ref $test eq 'ARRAY')
	{
		my @ids = @{$test};
		$results = $mobUtil->makeCommaFromArray(\@ids);
	}
	else
	{
		$results = $test;
		if(1)
		{
			my @results;
			eval{@results = @{$dbHandler->query($test)}};
			if (!$@) 			
			{
				my @ids;
				foreach(@results)
				{
					my $row = $_;
					my @row = @{$row};
					push(@ids,@row[0]);
				}
				$results = $mobUtil->makeCommaFromArray(\@ids);
				if(length($results)==0)
				{
					$results=$test;
				}
			}
			else
			{
				$results = "-1";#$test;
			}
		}
	}
	$self->{'selects'}  = $results;
 }
 
 sub calcCheckDigit
 {
	my $seed =@_[1];
	$seed = reverse($seed);
	my @chars = split("", $seed);
	my $checkDigit = 0;
	for my $i (0.. $#chars)
	{
		$checkDigit += @chars[$i] * ($i+2);
	}
	$checkDigit =$checkDigit%11;
	if($checkDigit>9)
	{
		$checkDigit='x';
	}
	return $checkDigit;
 }
 
 sub getBursarInfo
 {
	my $self = @_[0];
	my $selects = $self->{'selects'};
	my $log = $self->{'log'};
	my $dbHandler = $self->{'dbhandler'};
	my $outputPath = @_[1];
	if(-d $outputPath)
	{
		my $query = "SELECT INVOICE_NUM,
		TO_CHAR(ASSESSED_GMT, 'YYMMDD'),
		CHARGE_LOCATION_CODE,
		(SELECT RECORD_NUM FROM SIERRA_VIEW.PATRON_VIEW WHERE ID=A.PATRON_RECORD_ID),
		CONCAT('b',(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE RECORD_ID=A.PATRON_RECORD_ID AND FIELD_TYPE_CODE='b')),
		(SELECT CONCAT(LAST_NAME,', ',FIRST_NAME) FROM SIERRA_VIEW.PATRON_RECORD_FULLNAME WHERE PATRON_RECORD_ID=A.PATRON_RECORD_ID),
		(SELECT CONCAT(
	ADDR1,'\$',
	ADDR2,'\$',ADDR3,'\$',CITY,'\$',REGION,'\$',POSTAL_CODE) FROM SIERRA_VIEW.PATRON_RECORD_ADDRESS WHERE PATRON_RECORD_ID=A.PATRON_RECORD_ID AND PATRON_RECORD_ADDRESS_TYPE_ID=1),
		(SELECT 
		CONCAT(
		PCODE1,'|',
		PCODE2,'|',
		PCODE3,'|',
		PTYPE_CODE)
		FROM SIERRA_VIEW.PATRON_RECORD WHERE ID=A.PATRON_RECORD_ID),
		TRIM(CONCAT('b',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE RECORD_ID=A.ITEM_RECORD_METADATA_ID AND FIELD_TYPE_CODE='b')
		)),
		
		TRIM(CONCAT(	
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='a' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID)),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='b' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID)),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='c' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID)),
		' ',	
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='245' AND TAG='d' AND RECORD_ID=(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID =A.ITEM_RECORD_METADATA_ID))
		)),
		
		TRIM(CONCAT(
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=0 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=1 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=2 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=3 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID),
		' ',
		(SELECT TRIM(CONTENT) FROM SIERRA_VIEW.SUBFIELD WHERE MARC_TAG='050' AND DISPLAY_ORDER=4 AND RECORD_ID=A.ITEM_RECORD_METADATA_ID)
		)),
		(CASE 
			WHEN CHARGE_CODE='1' THEN 'MANUAL CHARGE'
			WHEN CHARGE_CODE='2' THEN 'OVERDUE'
			WHEN CHARGE_CODE='3' THEN 'REPLACEMENT'
			WHEN CHARGE_CODE='4' THEN 'OVERDUEX'
			WHEN CHARGE_CODE='5' THEN 'LOST BOOK'
			WHEN CHARGE_CODE='6' THEN 'OVERDUE RENEWED'
			WHEN CHARGE_CODE='7' THEN 'RENTAL'
			WHEN CHARGE_CODE='8' THEN 'RENTALX'
			WHEN CHARGE_CODE='9' THEN 'DEBIT'
			WHEN CHARGE_CODE='a' THEN 'NOTICE'
			WHEN CHARGE_CODE='b' THEN 'CREDIT CARD'
			WHEN CHARGE_CODE='p' THEN 'PROGRAM'
			END),
		TRIM(TO_CHAR(ITEM_CHARGE_AMT,'9999999999990.00')),
		TRIM(TO_CHAR(PROCESSING_FEE_AMT,'9999999999990.00')),
		TRIM(TO_CHAR(BILLING_FEE_AMT,'9999999999990.00'))		
		FROM SIERRA_VIEW.FINE A WHERE INVOICE_NUM IN ($selects)";
		#print "$query\n";
		my @results = @{$dbHandler->query($query)};		
		my @output;
		my $lowestInvoiceNum=0;
		my $highestInvoiceNum=0;
		my $recordCount = 0;
		my $totalAmt1=0;
		my $totalAmt2=0;
		my $totalAmt3=0;
		
		foreach(@results)
		{
			$recordCount++;
			my $row = $_;
			my @row = @{$row};
			
			my $invoiceNum = @row[0];
			if($lowestInvoiceNum==0)
			{
				$lowestInvoiceNum = $invoiceNum
			}
			elsif($invoiceNum<$lowestInvoiceNum)
			{
				$lowestInvoiceNum = $invoiceNum
			}
			if($highestInvoiceNum==0)
			{
				$highestInvoiceNum = $invoiceNum
			}
			elsif($invoiceNum>$highestInvoiceNum)
			{
				$highestInvoiceNum = $invoiceNum;
			}
			my $addThis;
			
			for my $i (0..$#row)
			{
				my $thisVal = @row[$i];
				if($i==3)  #patronNumber
				{
					$thisVal = "p$thisVal".calcCheckDigit($self,$thisVal);
				}
				if($i==6)
				{
					while(index($thisVal,'$$')>-1)
					{
						$thisVal =~ s/\$\$/\$/; 
					}
					
					if($thisVal eq "\$")
					{
						$thisVal="";
					}
					
				}
				if($i>11)
				{
					$thisVal =~ s/\.//;
					if($i==12)
					{
						$totalAmt1+=$thisVal;
					}
					if($i==13)
					{
						$totalAmt2+=$thisVal;
					}
					if($i==14)
					{
						$totalAmt3+=$thisVal;
					}
				}
				if($thisVal eq '')
				{
					$thisVal ="(no data)";
				}
				$addThis.=$thisVal.'|';
			}
			push(@output,$addThis);
			$addThis=undef;
		}
		
		if($#output > -1)
		{
			my $datestamp = UnixDate("today", "%Y-%m-%d");
			my $mobiusUtil = new Mobiusutil();
			my $header = "HEADER|";
			$header.=$mobiusUtil->padLeft($recordCount,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt1,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt2,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt3,10,'0').'|';
			$header.=$mobiusUtil->padLeft($totalAmt1+$totalAmt2+$totalAmt3,10,'0').'|';
			$header.=$mobiusUtil->padLeft($lowestInvoiceNum,10,'0').'|';
			$header.=$mobiusUtil->padLeft($highestInvoiceNum,10,'0').'|';
			my $dt   = DateTime->now;			
			$header.=substr($dt->year,2,2).$mobiusUtil->padLeft($dt->month,2,'0').$mobiusUtil->padLeft($dt->day,2,'0');
			my @outputFiles = ("bursar.$datestamp.send","bursar2.$datestamp.out");
			foreach(@outputFiles)
			{
				my $bursarOut = new Loghandler($outputPath.'/'.$_);
				$bursarOut->deleteFile();
				$bursarOut->addLine($header);
				foreach(@output)
				{
					$bursarOut->addLine(substr($_,0,length($_)-1));
				}
				$log->addLogLine("Outputted $recordCount record(s) into $outputPath/$_");
			}
			
			return 1;
		}
	}
	else
	{
		$log->addLogLine("Bursar - output path does not exist ($outputPath)");
	}
	return 0;
	
 }
 
 
 1;
 
 