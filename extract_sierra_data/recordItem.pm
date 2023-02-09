#!/usr/bin/perl
#
# recordItem.pm
# 
# Requires:
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# 
# This is basically a structure in perl to store a single field and all of it's subfields
#
# This class requires the subfield data to be separated by the pipe |
# Subfield a would be denoted by |a
# 
# Usage: 
# my $recordItem = new recordItem("010",' ','0',"|asn 96028362");
# 
# Later you can add data like this:
# 
# $recordItem->addData("|bmore data here");
#
# You can get the resulting MARC Field object like this:
#
# my $MARCField  = $recordItem->getMARCField();  #returns object type MARC::Field
#
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24
 
package recordItem; 
 use MARC::Record;
 use strict; 
 use Data::Dumper;
 use Mobiusutil;
 
 
 sub new   #ID, indicator1, indicator2, data
 {
	my $class = shift;
	my @t = ();
	my $mobiusUtil = new Mobiusutil();
    my $self = 
	{
		id => $mobiusUtil->trim(shift),
		indicator1 => shift,
		indicator2 => shift,
		data => shift,
		brokenFields => \@t,
		hasfields => 0
	};
	breakFields($self);
	bless $self, $class;
    return $self;
 }
 
 sub breakFields
 {
	my ($self) = @_[0];
	my @brokenFields = @{$self->{brokenFields}};
	my $data = $self->{data};
	my $id = $self->{id};
	my $indicator1 = $self->{indicator1};
	my $indicator2 = $self->{indicator2};
	my $mobiusUtil = new Mobiusutil();
	
	
	my $indexDel = index($data, '|');
	if ( $indexDel != -1) 
	{
		#print "Splitting $data\n";
		$self->{hasfields} = 1;
        # remove the pipes that come before a non-allowed subfield character, like a [ or ( or )
        $data =~ s/\|([^0-9|^A-Z|^a-z])/$1/g;
        
		my @subSplits = split('\|', $data);
		my @fields;
		foreach(@subSplits)
		{
			if(length($mobiusUtil->trim($_))>1)
			{
				my $field = substr($_,0,1);
                if($field =~ /^[0-9|A-Z|a-z]$/)
                {
                    my $content = substr($_,1);			
                    if($content ne '')
                    {	
                        my $temp = length($content);
                        #print "$field = $content and content is $temp size\n";
                        my $rec = new recordItem($field,$indicator1,$indicator2,$content);
                        push(@brokenFields,$rec);
                        push(@fields,$field);
                    }
                    else
                    {
                        #print "Subfield $field and content '$content' which is empty for $id and will not be added to marc\n";
                    }
                }
            }
		}
		
		if($id eq '945')
		{
			my @tempArray;
			#remove dupliate i entrys on 945 records
			my $foundicount = 0;
			my $foundycount = 0;
			my $int = 0;
			foreach(@fields)
			{
				if($_ eq 'i')
				{
					$foundicount++;
					if($foundicount>1)
					{
						#print "Deleted duplication\n";
					}
					else
					{
						push(@tempArray,@brokenFields[$int]);
					}
				}
				elsif($_ eq 'y')
				{
					$foundycount++;
					if($foundycount>1)
					{
						#print "Deleted duplication\n";
					}
					else
					{
						push(@tempArray,@brokenFields[$int]);
					}
				}
				else
				{
					push(@tempArray,@brokenFields[$int]);
				}
				$int++;
			}
			@brokenFields = @tempArray;
		}
		
		#sort by subfield ID
		my $changed = 1;
		if($id ne '505')
		{
			my $i=0;
			while($i<$#brokenFields)
			{
				
				my $thisRec = @brokenFields[$i]->getID();
				if($i+1 <= $#brokenFields)
				{
					my $thisRecordItem = @brokenFields[$i+1];
					my $nextRec = $thisRecordItem->getID();
					if($nextRec lt $thisRec)
					{
						#print "$nextRec was lower in the alphabet than $thisRec\n";
						$thisRec = @brokenFields[$i];
						@brokenFields[$i]=@brokenFields[$i+1];
						@brokenFields[$i+1] = $thisRec;
						$i-=2;
					}
				}
				$i++;
				if($i<0)
				{
					$i=0;
				}
				
			}
		}
		#print "\n\n\n\n After sort:\n";
		#print Dumper(\@brokenFields);
		
		
	}
	else
	{
		$self->{hasfields} = 0;
	}
	#print "**********DONE Breaking $data\n*****************\n";
	
	$self->{brokenFields} = \@brokenFields;
 } 
 
 sub hasfields
 {
	my $self = @_[0];	
	return $self->{hasfields};
 }
 
 sub getBrokenFields
 {
	my $self = @_[0];
	my @brokenFields = @{$self->{brokenFields}};
	return \@brokenFields;
 }
 
 sub getID
 {
	my $self = @_[0];
	return $self->{id};
 }
 
 sub getData
 {
	my $self = @_[0];
	return $self->{data};	 
 }
 
 sub addData
 {	
	my $self = @_[0];
	my @clear = ();
	
	$self->{data}.=$_[1];
	my $t = $self->{data};
	$self->{brokenFields} = \@clear;
	breakFields($self);
 }
 
 sub getMARCField
 {
 
	my $t = $#_;
	my ($self) = @_[0];
	my @brokenFields = @{$self->{brokenFields}};
	my $ind1 = $self->{indicator1};
	my $ind2 = $self->{indicator2};
	my $id = $self->{id};
	my $ret;
	#test the tag for numeric
	#print "Getting MARC field. id=$id\n";
	my $data = $self->{data};	
	if ($id =~ m/[^0-9.]/ ) { print "$id is not a valid tag\n";}
    else
	{
		if($self->{hasfields} && $id>9)
		{
			for my $i (0..$#brokenFields)
			{
				my $recItem = @brokenFields[$i];			
				if($i==0)
				{
					#print "Adding $id\n";
					$ret = MARC::Field->new($id, $ind1, $ind2, $recItem->getID() => $recItem->getData());
				}
				else
				{
					#my $tt = $recItem->getID();
					#print "sAdding $tt\n";
					$ret->add_subfields( $recItem->getID() => $recItem->getData() );
				}
			}
		}
		else
		{
			
			if($id eq '001' || $id eq '002' || $id eq '003' || $id eq '004' || $id eq '005' || $id eq '006' || $id eq '007' || $id eq '008' || $id eq '009')
			{
				#Different Constructor for these fields
				$ret = MARC::Field->new($id,$data);
			}
			else
			{
			#print "Adding $id = $data\n";
				eval{$ret = MARC::Field->new($id,$ind1,$ind2,$data)};
				 if ($@) 
				 {
				 #print "Could not create MARC Field object - trying to add subfield a\n";
					#errors usually due to a required subfield
					eval{$ret = MARC::Field->new($id,$ind1,$ind2,"a"=>$data)};
					if ($@) 
					{
						 print "Could not add field to MARC\n";
						 print "$id = \"$data\"\n";
					 }
					 else
					 {
						#print "That worked\n";
						#print Dumper($ret);
					 }
				 }
				
			}
		}
	}	
	
	return $ret;
 }
 
 1;