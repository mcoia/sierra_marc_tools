#!/usr/bin/perl
#
# Mobiusutil.pm
#
# Requires:
#
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# Net::FTP
# Expect
# Net::SSH::Expect
# Encode
# utf8
#
# This is a simple utility class that provides some common functions
#
# Usage:
# my $mobUtil = new Mobiusutil(); #No constructor
# my $conf = $mobUtil->readConfFile($configFile);
#
# Other Functions available:
#   makeEvenWidth
#   sendftp
#   getMarcFromZ3950
#   chooseNewFileName
#   trim
#   findSummonQuery
#   makeCommaFromArray
#   insertDataIntoColumn
#   compare2MARCFiles
#   compare2MARCObjects
#   compare2MARCFields
#   compareStrings
#   expectConnect
#   expectSSHConnect
#
# Blake Graham-Henderson
# MOBIUS
# blake@mobiusconsortium.org
# 2014-2-22


package Mobiusutil;
 use MARC::Record;
 use MARC::File;
 use MARC::File::USMARC;
 use MARC::Charset 'marc8_to_utf8';
 use ZOOM;
 use Net::FTP;
 use Loghandler;
 use Data::Dumper;
 use DateTime;
 #use Expect;
 #use Net::SSH::Expect;
 use Encode;
 use utf8;

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}


sub readConfFile
{
    my %ret = ();
    my $ret = \%ret;
    my $file = @_[1];

    my $confFile = new Loghandler($file);
    if(!$confFile->fileExists())
    {
        print "Config File does not exist\n";
        undef $confFile;
        return false;
    }

    my @lines = @{ $confFile->readFile() };
    undef $confFile;

    foreach my $line (@lines)
    {
        $line =~ s/\n//;  #remove newline characters
        my $cur = trim('',$line);
        my $len = length($cur);
        if($len>0)
        {
            if(substr($cur,0,1)ne"#")
            {

                my $Name, $Value;
                my @s = split (/=/, $cur);
                my $Name = shift @s;
                my $Value = join('=', @s);
                $$ret{trim('',$Name)} = trim('',$Value);
            }
        }
    }

    return \%ret;
}

sub readQueryFile
{
    my %ret = ();
    my $ret = \%ret;
    my $file = @_[1];
    #print "query file: $file\n";
    my $confFile = new Loghandler($file);
    if(!$confFile->fileExists())
    {
        print "Query file does not exist\n";
        undef $confFile;
        return false;
    }

    my @lines = @{ $confFile->readFile() };
    undef $confFile;

    my $fullFile = "";
    foreach my $line (@lines)
    {
        $line =~ s/\n/ASDF!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ASDF/g;  #remove newline characters
        my $cur = trim('',$line);
        my $len = length($cur);
        if($len>0)
        {
            if(substr($cur,0,1)ne"#")
            {
                $line=~s/\t//g;
                $fullFile.=" $line"; #collapse all lines into one string
            }
        }
    }

    my @div = split(";", $fullFile); #split the string by semi colons
    foreach(@div)
    {
        my $Name, $Value;
        ($Name, $Value) = split (/\~\~/, $_); #split each by the equals sign (left of equal is the name and right is the query
        $Value = trim('',$Value);
        $Name =~ s/ASDF!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ASDF//g;  # just in case
        $Value =~ s/ASDF!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ASDF/\n/g;  # put the line breaks back in
        $$ret{trim('',$Name)} = $Value;
    }

    return \%ret;
}

sub makeEvenWidth  #line, width
{
    my $ret;

    if($#_+1 !=3)
    {
        return;
    }
    $line = @_[1];
    $width = @_[2];
    #print "I got \"$line\" and width $width\n";
    $ret=$line;
    if(length($line)>=$width)
    {
        $ret=substr($ret,0,$width);
    }
    else
    {
        while(length($ret)<$width)
        {
            $ret=$ret." ";
        }
    }
    #print "Returning \"$ret\"\nWidth: ".length($ret)."\n";
    return $ret;

}

sub padLeft  #line, width, fill char
{
    my $ret;

    if($#_+1 !=4)
    {
        return;
    }
    $line = @_[1];
    $width = @_[2];
    $fillChar = @_[3];
    #print "I got \"$line\" and width $width\n";
    $ret=$line;
    if(length($line)>=$width)
    {
        $ret=substr($ret,0,$width);
    }
    else
    {
        while(length($ret)<$width)
        {
            $ret=$fillChar.$ret;
        }
    }
    #print "Returning \"$ret\"\nWidth: ".length($ret)."\n";
    return $ret;

}

sub sendftp    #server,login,password,remote directory, array of local files to transfer, Loghandler object
{

    if($#_+1 !=7)
    {
        return;
    }

    my $hostname = @_[1];
    my $login = @_[2];
    my $pass = @_[3];
    my $remotedir = @_[4];
    my @files = @{@_[5]};
    my $log = @_[6];

    $log->addLogLine("**********FTP starting -> $hostname with $login and $pass -> $remotedir");
    my $ftp = Net::FTP->new($hostname, Debug => 0, Passive=> 1)
    or die $log->addLogLine("Cannot connect to ".$hostname);
    $ftp->login($login,$pass)
    or die $log->addLogLine("Cannot login ".$ftp->message);
    $ftp->cwd($remotedir)
    or die $log->addLogLine("Cannot change working directory ", $ftp->message);
    foreach my $file (@files)
    {
        $log->addLogLine("Sending file $file");
        $ftp->put($file)
        or die $log->addLogLine("Sending file $file failed");
    }
    $ftp->quit
    or die $log->addLogLine("Unable to close FTP connection");
    $log->addLogLine("**********FTP session closed ***************");
}

sub getMarcFromZ3950  #Pass values (server,query, Loghander Object)  returns array reference to MARC::Record array
{
    my @ret;

    if($#_+1 !=4)
    {
        return;
    }


    my $DATABASE = @_[1];
    my $query = @_[2];
    my $log = @_[3];


    if ( ! $query )
    {
        $log->addLogLine("Z39.50 Error - Query Required");
        return;
    }

    $log->addLogLine("************Starting Z39.50 Connection -> $DATABASE $query");
    my $connection = new ZOOM::Connection( $DATABASE, 0, count=>1, preferredRecordSyntax => "USMARC" );
    my $results = $connection->search_pqf( qq[$query] );

    my $size = $results->size();
    $log->addLogLine("Received $size records $DATABASE $query");
    my $index = 0;
    for my $i ( 0 .. $results->size()-1 )
    {
        #print $results->record( $i )->render();
        my $record = $results->record( $i )->raw;
        my $marc = MARC::Record->new_from_usmarc( $record );
        push(@ret,$marc);
    }

    #$log->addLogLine("************Ending Z39.50 Connection************");
    $connection->destroy();
    undef $connection, $results;
    return \@ret;
}

sub chooseNewFileName   #path to output folder,file prefix, file extention    returns full path to new file name
{

    my $path = @_[1];
# Add trailing slash if there isn't one
    if(substr($path,length($path)-1,1) ne '/')
    {
        $path = $path.'/';
    }


    my $seed = @_[2];
    my $ext = @_[3];
    my $ret="";
    if( -d $path)
    {
        my $num="";
        $ret = $path . $seed . $num . '.' . $ext;
        while(-e $ret)
        {
            if($num eq "")
            {
                $num=-1;
            }
            $num = $num+1;
            $ret = $path . $seed . $num . '.' . $ext;
        }
    }
    else
    {
        $ret = 0;
    }

    return $ret;
}

sub trim
{
    my $self = shift;
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

sub findQuery       #self, DBhandler(object), school(string), platform(string), addsorcancels(string), queries
{
    my $dbHandler = @_[1];
    my $school = @_[2];
    my $platform = @_[3];
    my $addsOrCancels = @_[4];
    my %queries = %{$_[5]};
    my $dbFromDate = @_[6];

    my $key = $platform."_".$school."_".$addsOrCancels;
    if(!$queries{$key})
    {
        return "-1";
    }
    my $dt = DateTime->now;   # Stores current date and time as datetime object
    my $ndt = DateTime->now;
    my $yesterday = $dt->subtract(days=>1);
    $yesterday = $yesterday->set_hour(0);
    $yesterday = $yesterday->set_minute(0);
    $yesterday = $yesterday->set_second(0);
    #$dt = $yesterday->add(days=>1); #midnight to midnight


#
# Now create the time string for the SQL query
#

    my $fdate = $yesterday->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
    my $ftime = $yesterday->hms;   # Retrieves time as a string in 'hh:mm:ss' format
    my $todate = $ndt;
    my $tdate = $todate->ymd;
    my $ttime = $yesterday->hms;

    # $dbFromDate = "2013-02-16 05:00:00";

    $dbFromDate = "$fdate $ftime" if(!$dbFromDate);

    my $dbToDate = "$tdate $ttime";
    my $query = $queries{$key};
    $query =~s/\$dbFromDate/$dbFromDate/g;
    $query =~s/\$dbToDate/$dbToDate/g;

    return $query;

}

sub makeCommaFromArray
{
    my @array = @{@_[1]};
    my $delimter=',';
    if(@_[2])
    {
        $delimter=@_[2];
    }
    my $ret = "";
    for my $i (0..$#array)
    {
        $ret.="\"".@array[$i]."\"".$delimter;
    }
    $ret = substr($ret,0,length($ret)-(length($delimter)));
    return $ret;
}

sub makeArrayFromComma
{
    my $string = @_[1];
    my @array = split(/,/,$string);
    for my $y(0.. $#array)
    {
        @array[$y]=trim('',@array[$y]);
    }
    return \@array;
}

sub insertDataIntoColumn  #1 based column position
{
    my $ret = @_[1];
    my $data = @_[2];
    my $column = @_[3];
    my $len = length($ret);
    if(length($ret)<($column-1))
    {
        while(length($ret)<($column-1))
        {
            $ret.=" ";
        }
        $ret.=$data;
    }
    else
    {
        my @ogchars = split("",$ret);
        my @insertChars = split("",$data);
        my $len = $#insertChars;
        for my $i (0..$#insertChars)
        {
            @ogchars[$i+$column-1] = @insertChars[$i];
        }
        $ret="";
        foreach(@ogchars)
        {
            $ret.=$_;
        }
    }
    return $ret;

}

sub compare2MARCFiles
{
    my $firstFile = @_[1];
    my $secondFile = @_[2];
    my $log = @_[3];
    my $matchOnTag = @_[4];
    my $matchOnSubField = @_[5];

    my $fileCheck1 = new Loghandler($firstFile);
    my $fileCheck2 = new Loghandler($secondFile);
    my %file1, %file2;
    my @matchedFile1, @matchedFile2;
    my @errors;
    if($fileCheck1->fileExists() && $fileCheck2->fileExists())
    {
        my $file = MARC::File::USMARC->in( $firstFile );
        my $r =0;
        while ( my $marc = $file->next() )
        {
            #print "Record $r\n";
            $r++;
            my $recID;
            if($matchOnTag > 9)
            {
                $recID = $marc->field($matchOnTag)->subfield($matchOnSubField);
            }
            else
            {
                $recID = $marc->field($matchOnTag)->data();
            }
            $recID = uc $recID;
            if(exists($file1{$recID}))
            {
                #print "There were more than 1 of the same records containing same Record Num $recID in file $firstFile\n";
            }
            else
            {
                $file1{$recID} = $marc;
                push(@matchedFile1,$recID);
            }
        }
        $file->close();
        undef $file;
        my $file = MARC::File::USMARC->in( $secondFile );
        while ( my $marc = $file->next() )
        {
            if($matchOnTag > 9)
            {
                $recID = $marc->field($matchOnTag)->subfield($matchOnSubField);
            }
            else
            {
                $recID = $marc->field($matchOnTag)->data();
            }
            $recID = uc $recID;
            if(exists($file2{$recID}))
            {
                #print "There were more than 1 of the same records containing same Record Num $recID in file $secondFile\n";
            }
            else
            {
                $file2{$recID} = $marc;
                push(@matchedFile2,$recID);
            }
        }
        $file->close();
        undef $file;

        my @matched;

        for my $onePos (0..$#matchedFile1)
        {
            $thisOCLCNum = @matchedFile1[$onePos];
            #if($thisOCLCNum eq '.B20004047')
            #{
            #print "$thisOCLCNum\n";
            for my $twoPos(0.. $#matchedFile2)
            {
                if(@matchedFile1[$onePos] eq @matchedFile2[$twoPos])
                {
                    my $leader1 = $file1{@matchedFile1[$onePos]}->leader();
                    my $leader2 = $file2{@matchedFile2[$twoPos]}->leader();
                    my $leaderMatchErrorString="";
                    if(substr($leader1,5,4).substr($leader1,17,3) ne substr($leader2,5,4).substr($leader2,17,3))
                    {
                        $leaderMatchErrorString="Leader \"$leader1\" != \"$leader2\"";
                    }
                    #print "First = ".$file1{@matchedFile1[$onePos]}->encoding()."\n";
                    #print "Second = ".$file2{@matchedFile2[$twoPos]}->encoding()."\n";
                    my $first_utf8_flag = $file1{@matchedFile1[$onePos]}->encoding() eq 'MARC-8'?0:1;
                    my $second_utf8_flag = $file2{@matchedFile2[$twoPos]}->encoding() eq 'MARC-8'?0:1;
                    my @theseErrors = @{compare2MARCObjects("",$file1{@matchedFile1[$onePos]},$first_utf8_flag,$file2{@matchedFile2[$twoPos]},$second_utf8_flag)};
                    push(@matched,@matchedFile1[$onePos]);
                    if(($#theseErrors>-1) || (length($leaderMatchErrorString)!=0))
                    {
                        push(@errors,"Errors for $thisOCLCNum:");
                        push(@errors,"\t$leaderMatchErrorString");
                        foreach(@theseErrors)
                        {
                            push(@errors,"\t$_");
                        }
                    }
                    push(@errors,"\n");
                }
            }
            #}

        }
        #print Dumper(@matched);
        my @notMatchedList;
        my $totalMatched=0;
        while ((my $internal, my $value ) = each(%file1))
        {
            #print "checking $internal\n";
            if(exists $matched[$internal])
            {
                $totalMatched++;
            }
            else
            {
                print "Not Found\n";
                push(@notMatcheList,$internal);
            }
        }
        if($#notMatchedList>-1)
        {
            my $list;
            foreach(@notMatchedList)
            {
                $list.="$_,";
            }
            push(@errors,"File 1 didn't have a sister for these records:\n$list");
        }
        my $recordCount1=keys( %file1 ), $recordCount2=keys( %file2 );
        push(@errors,"$recordCount1 Record(s) in file 1 and $recordCount2 Record(s) in file 2");
        push(@errors,"Matched $totalMatched Record(s) from file 1");

    }
    else
    {
        print "One or both of those files do not exist\n";
    }

    return \@errors;
}

sub compare2MARCObjects
{
    my $marc1 = @_[1];
    my $first_utf8_flag = @_[2];
    my $marc2 = @_[3];
    my $second_utf8_flag = @_[4];
    my @errors;
    my @remainingFields1,@remainingFields2;
    my @marcFields1 = $marc1->fields();
    my @marcFields2 = $marc2->fields();

    foreach(@marcFields1)
    {
        push(@remainingFields1,"".$_->tag());
    }
    foreach(@marcFields2)
    {
        push(@remainingFields2,"".$_->tag());
    }

    for my $fieldPos1(0..$#marcFields1)
    {
        my @matchPos2;
        my $thisField1 = @marcFields1[$fieldPos1];
        #if($thisField1->tag() ne'998')
        #{
        for my $fieldPos2(0..$#marcFields2)
        {
            my $thisField2 = @marcFields2[$fieldPos2];
            if($thisField2->tag() eq $thisField1->tag())
            {
                push(@matchPos2,$fieldPos2);
            }
        }

        if($#matchPos2==0)  #only 1 field
        {
            my @thisErrorList = @{compare2MARCFields("",$thisField1,$first_utf8_flag,@marcFields2[@matchPos2[0]],$second_utf8_flag)};
            if($#thisErrorList>-1)
            {
                push(@errors,"Errors for ".$thisField1->tag());
                foreach(@thisErrorList)
                {
                    push(@errors,"\t$_");
                }
            }

        }
        elsif($#matchPos2>0)
        {
            #print "There were more than 1 matching field tags for ".$thisField1->tag()."\n";
            my $errorCheck=-1;
            my @check;
            for my $pos(0..$#matchPos2)
            {
                push(@check,[@{compare2MARCFields("",$thisField1,$first_utf8_flag,@marcFields2[@matchPos2[$pos]],$second_utf8_flag)}]);
                if($#{@check[$#check]}==-1)
                {
                $errorCheck = $pos;
                }

            }
            if($errorCheck==-1)
            {
                push(@errors,"None of the sister tags(".$thisField1->tag().") matched and here are the errors:");
                foreach(@check)
                {
                    my @subError = @{$_};
                    foreach(@subError)
                    {
                        push(@errors,"\t".$_);
                    }
                }
            }
        }
        else
        {
            push(@errors,"Tag: ".$thisField1->tag()." did not match any tags on the sister MARC Record");
        }
        @matchPos2 = ();
        #}
    }
    return \@errors;
}

sub compare2MARCFields
{
    my $field1 = @_[1];
    my $first_utf8_flag = @_[2];
    my $field2 = @_[3];
    my $second_utf8_flag = @_[4];

    my $tag = $field1->tag();

    my @errors;
    if($field1->tag() ne $field2->tag())
    {
        push(@errors,"Tags do not match");
    }
    else
    {
        if(!($field1->is_control_field()))
        {
            @subFields1 = $field1->subfields();
            @subFields2 = $field2->subfields();
            my $indicators1 = $field1->indicator(1).$field1->indicator(2);
            my $indicators2 = $field2->indicator(1).$field2->indicator(2);
            if($indicators1 ne $indicators2)
            {
                push(@errors,"Tag: $tag Indicators mismatch \"$indicators1\" != \"$indicators2\"");
            }
            for my $fieldPos1(0..$#subFields1)
            {
                my @matchPos2;
                my $thisField1 = @{@subFields1[$fieldPos1]}[0];

                for my $fieldPos2(0..$#subFields2)
                {
                    my $thisField2 = @{@subFields2[$fieldPos2]}[0];
                    if($thisField1 eq $thisField2 )
                    {
                        push(@matchPos2, $fieldPos2);
                    }
                }

                if($#matchPos2==0)  #only 1 field
                {
                    #Compare apples to apples AKA UTF-8 to UTF-8 and not MARC-8 to UTF-8
                    #Thank you MARC::Charset!
                    #It seems that the conversion picks a different character from the UTF-8 Chart and prints the same
                    #but of course they compare different
                    my $comp1 = $first_utf8_flag?(@{@subFields1[$fieldPos1]}[1]):marc8_to_utf8(@{@subFields1[$fieldPos1]}[1]);
                    my $comp2 = $second_utf8_flag?(@{@subFields2[@matchPos2[0]]}[1]):marc8_to_utf8(@{@subFields2[@matchPos2[0]]}[1]);
                    $comp1 = decode_utf8($comp1);
                    $comp2 = decode_utf8($comp2);

                    if(0)#Stop this code from running
                    {
                        my @chars1 = split("",$comp1);
                        my @chars2 = split("",$comp2);
                        for my $i (0..$#chars1)
                        {
                            my $tem1 = @chars1[$i];
                            my $tem2 = @chars2[$i];
                            my $t1 = ord($tem1);
                            my $t2 = ord($tem2);
                            print encode('utf-8',"$tem1 = $t1\n$tem2 = $t2\n");
                        }
                    }
                    #print "$comp1  ne  $comp2\n";
                    if($comp1 ne $comp2)
                    {
                        push(@errors,"Tag: $tag Subfield $thisField1 $comp1 != $comp2");
                    }

                }
                elsif($#matchPos2>0)
                {
                    #print "There were more than 1 matching subfield tags for tag: $tag Subfield: $thisField1\n";
                    my $noErrors=-1;
                    my $comp1 = $first_utf8_flag?(@{@subFields1[$fieldPos1]}[1]):marc8_to_utf8(@{@subFields1[$fieldPos1]}[1]);
                    my $errorListString="";
                    for my $pos(0..$#matchPos2)
                    {
                        my $comp2 =  $second_utf8_flag?(@{@subFields2[@matchPos2[$pos]]}[1]):marc8_to_utf8(@{@subFields2[@matchPos2[$pos]]}[1]);
                        $comp1 = decode_utf8($comp1);
                        $comp2 = decode_utf8($comp2);

                        if(0)#Stop this code from running
                        {
                            my @chars1 = split("",$comp1);
                            my @chars2 = split("",$comp2);
                            for my $i (0..$#chars1)
                            {
                                my $tem1 = @chars1[$i];
                                my $tem2 = @chars2[$i];
                                my $t1 = ord($tem1);
                                my $t2 = ord($tem2);
                                print encode('utf-8',"$tem1 = $t1\n$tem2 = $t2\n");
                            }
                        }
                        if($comp1 eq $comp2)
                        {
                            $noErrors = $pos;
                        }
                        else
                        {
                            $errorListString.="  $comp1 != $comp2";
                        }
                    }
                    if($noErrors==-1)
                    {
                        push(@errors,"Tag: $tag Subfield $thisField1 $errorListString");
                    }
                }
                else
                {
                    push(@errors,"Tag: $tag Subfield $thisField1 Could not find a matching subfield on the sister tag");
                }
                @matchPos2 = ();
            }
        }
        else
        {
            if($field1->data() ne $field2->data())
            {
                push(@errors,"$tag do not match");
            }
        }
    }

    return \@errors;

}

sub compareStrings
{
    my $string1 = @_[1];
    my $string2 = @_[2];
    if(length($string1)!=length($string2))
    {
        #print "\"$string1\" \"$string2\"\nDiffering Lengths\n";
        return 0;
    }
    my @chars1 = split("",$string1);
    my @chars2 = split("",$string2);
    for my $i (0..$#chars1)
    {
        my $tem1 = @chars1[$i];
        my $tem2 = @chars2[$i];
        my $t1 = ord($tem1);
        my $t2 = ord($tem2);

        if(0)
        {
            if(ord($tem1)!=ord($tem2))
            {
                return 0;
            }
        }
        if(@chars1[$i] ne @chars2[$i])
        {
            #print "! $string1 != $string2 - \"".@chars1[$i]."\"($t1) to \"".@chars2[$i]."\"($t2)\n";
            return 0;
        }
    }

    return 1;

}

sub expectSSHConnect
{
    my $login = @_[1];
    my $pass = @_[2];
    my $host = @_[3];
    my @loginPrompt = @{@_[4]};
    my @allPrompts = @{@_[5]};
    my $errorMessage = 1;

    my $h = Net::SSH::Expect->new (
    host => $host,
    password=> $pass,
    user => $login,
    raw_pty => 1
    );

    $h->timeout(30);
    my $login_output = $h->login();

    if(index($login_output,"Choose one (D,C,M,B,A,Q)")>-1)
    {
        $h->send("c");
        $i=0;
        my $screen = $h->read_all();
        foreach(@allPrompts)
        {
            if($i <= $#allPrompts)
            {
                my @thisArray = @{$_};
                my $b = 0;
                foreach(@thisArray)
                {
                    if($b <= $#thisArray)
                    {
                        if(index($screen,@thisArray[$b])>-1)
                        {
                            ## CANNOT GET A CARRIAGE RETURN TO SEND TO THE SSH PROMPT
                            ## HERE IS SOME OF THE CODE I HAVE TRIED (COMMENTED OUT)
                            ## BGH
                            #if(index(@thisArray[$b+1],"\r")>-1)
                            #{
                            #my $l = length(@thisArray[$b+1]);
                            #my $in = index(@thisArray[$b+1],"\r");
                            #my $pos = $in;
                            #print "Len: $l index: $in $pos: $pos\n";

                            #my $cmd = substr(@thisArray[$b+1],0,index(@thisArray[$b+1],"\r"));
                            #print "Converted cmd to \"$cmd\"\n";
                            #$screen = $h->exec($cmd);

                            #}
                            #else
                            #{
                            $h->send(@thisArray[$b+1]);
                            $screen = $h->read_all();
                            #}
                            #print "Found \"".@thisArray[$b]."\"\nSending (\"".@thisArray[$b+1]."\")\n";
                            $b++;

                        }
                        else
                        {
                            #print "Didn't find \"".@thisArray[$b]."\" - Moving onto the next set of prompts\n";
                            #print "Screen is now\n$screen\n";
                            $b = $#thisArray;  ## Stop looping in this sub prompt tree
                        }
                    }
                    $b++;
                }
                $i++;
            }

        }

    }
    else
    {
        $errorMessage = "Didn't get the expected login prompt";
    }

    eval{$h->close();};
    if ($@)
    {
        $errorMessage = "Error closing SSH connect";
    }
    return $errorMessage;

}

sub expectConnect
{
    my $login = @_[1];
    my $pass = @_[2];
    my $host = @_[3];
    my @allPrompts = @{@_[4]};
    my $keyfile = @_[5];
    my $errorMessage = "";
    my @promptsResponded;
    my $timeout  = 30;

    my $connectVar = "ssh $login\@$host";
    $connectVar .=' -i '.$keyfile if $keyfile;
    my $h = Expect->spawn($connectVar);
    #turn off command output to the screen
    $h->log_stdout(0);
    my $acceptkey=1;
    unless ($h->expect($timeout, "yes/no")){$acceptkey=0;}
    if($acceptkey){print $h "yes\r";}
    if(!$keyfile)
    {
        unless ( $h->expect($timeout, "password") ) { return "No Password Prompt"; }
    }
    print $h $pass."\r" if !$keyfile;
    unless ($h->expect($timeout, ":")) { }  #there is a quick screen directly after logging in

    $i=0;
    #print Dumper(@allPrompts);
    foreach(@allPrompts)
    {
        if($i <= $#allPrompts)
        {
            my @thisArray = @{$_};
            my $b = 0;
            foreach(@thisArray)
            {
                if($b < ($#thisArray-1))
                {
                    #Turn on debugging:
                    #$h->exp_internal(1);
                    my $go = 1;
                    unless ($h->expect(@thisArray[$b], @thisArray[$b+1]))
                    {
                        if(@thisArray[$b+3] == 1)  #This value tells us weather it's ok or not if that prompt was not found
                        {
                            my $screen = $h->before();
                            $screen =~s/\[/\r/g;
                            my @chars1 = split("",$screen);
                            my $output;
                            my $pos=0;
                            for my $i (0..$#chars1)
                            {
                                if($pos < $#chars1)
                                {
                                    if(@chars1[$pos] eq ';')
                                    {
                                        $pos+=4;
                                    }
                                    else
                                    {
                                        $output.=@chars1[$pos];
                                        $pos++;
                                    }
                                }
                            }
                            $errorMessage.="Prompt not found: '".@thisArray[$b+1]."' in ".@thisArray[$b]." seconds\r\n\r\nScreen looks like this:\r\n$output\r\n";
                        }
                        $b = $#thisArray;
                        $go=0;
                    }
                    if($go)
                    {
                        print $h @thisArray[$b+2];
                        my $t = @thisArray[$b+2];
                        $t =~ s/\r//g;
                        push(@promptsResponded, "'".@thisArray[$b+1]."' answered '$t'");
                    }
                    $b++;
                    $b++;
                    $b++;
                }
                $b++;
            }
            $i++;
        }
    }

    $h->soft_close();

    $h->hard_close();
    if(length($errorMessage)==0)
    {
        $errorMessage=1;
    }
    push(@promptsResponded, $errorMessage);
    return \@promptsResponded;

}

sub marcRecordSize
{
    my $count=0;
    my $marc = @_[1];
    my $out="";
    eval{$out = $marc->as_usmarc();};
    if($@)
    {
        return 0;
    }
    #print "size: ".length($out)."\n";
    return length($out);

    ## This code below should not execute
    my @fields = $marc->fields();
    foreach(@fields)
    {

        if($_->is_control_field())
        {
            my $subs = $_->data();
            #print "adding control $subs\n";
            $count+=length($subs);
        }
        else
        {
            my @subs = $_->subfields();
            foreach(@subs)
            {
                my @t = @{$_};
                for my $i(0..$#t)
                {
                    #print "adding ".@t[$i]."\n";
                    $count+=length(@t[$i]);
                }
            }
        }
    }
    #print $count."\n";
    return $count;

}

sub trucateMarcToFit
{
    my $marc = @_[1];
    local $@;
    my $count = marcRecordSize('',$marc);
    #print "Recieved $count\n";
    if($count)
    {
        my @fields = $marc->fields();
        my %fieldsToChop=();
        foreach(@fields)
        {
            my $marcField = $_;
            #print $marcField->tag()."\n";

            if(($marcField->tag() > 899) && ($marcField->tag() != 907) && ($marcField->tag() != 998) && ($marcField->tag() != 901))
            {
                my $id = (scalar keys %fieldsToChop)+1;
                #print "adding to chop list: $id\n";
                $fieldsToChop{$id} = $marcField;
            }
        }
        my %deletedFields = ();

        my $worked = 2;

        while($count>99999 && ((scalar keys %deletedFields)<(scalar keys %fieldsToChop)))
        {
            $worked = 1;
            my $foundOne = 0;
            while ((my $internal, my $value ) = each(%fieldsToChop))
            {
                if(!$foundOne)
                {
                    if(!exists($deletedFields{$internal}))
                    {
                        #print "$internal going onto deleted\n";
                        $deletedFields{$internal}=1;
                        $marc->delete_field($value);
                        #print "Chopping: ".$value->tag()."\n";#." contents: ".$value->as_formatted()."\n";
                        #$count-=$internal;
                        $count = marcRecordSize('',$marc);
                        #print "Now it's $count\n";
                        $foundOne=1;
                    }
                }
            }
            #print "deletedFields: ".(scalar keys %deletedFields)."\nto chop: ".(scalar keys %fieldsToChop)."\n";
        }
        if($count>99999)
        {
            $worked=0;
        }
        #print $marc->as_formatted();
        my @ret = ($marc,$worked);
        return \@ret;
    }
    else
    {
        return ($marc,0);
    }

}

sub boxText
{
    shift;
    my $text = shift;
    my $hChar = shift;
    my $vChar = shift;
    my $padding = shift;
    my $ret = "";
    my $totalLength = length($text) + (length($vChar)*2) + ($padding *2) + 2;
    my $heightPadding = ($padding / 2 < 1) ? 1 : $padding / 2;

    # Draw the first line
    my $i = 0;
    while($i < $totalLength)
    {
        $ret.=$hChar;
        $i++;
    }
    $ret.="\n";
    # Pad down to the data line
    $i = 0;
    while( $i < $heightPadding )
    {
        $ret.="$vChar";
        my $j = length($vChar);
        while( $j < ($totalLength - (length($vChar))) )
        {
            $ret.=" ";
            $j++;
        }
        $ret.="$vChar\n";
        $i++;
    }

    # data line
    $ret.="$vChar";
    $i = -1;
    while($i < $padding )
    {
        $ret.=" ";
        $i++;
    }
    $ret.=$text;
    $i = -1;
    while($i < $padding )
    {
        $ret.=" ";
        $i++;
    }
    $ret.="$vChar\n";
    # Pad down to the last
    $i = 0;
    while( $i < $heightPadding )
    {
        $ret.="$vChar";
        my $j = length($vChar);
        while( $j < ($totalLength - (length($vChar))) )
        {
            $ret.=" ";
            $j++;
        }
        $ret.="$vChar\n";
        $i++;
    }
     # Draw the last line
    $i = 0;
    while($i < $totalLength)
    {
        $ret.=$hChar;
        $i++;
    }
    $ret.="\n";
    return $ret;
}


sub generateRandomString
{
    my $length = @_[1];
    my $i=0;
    my $ret="";
    my @letters = ('a','b','c','d','e','f','g','h','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z');
    my $letterl = $#letters;
    my @sym = ('@','#','$');
    my $syml = $#sym;
    my @nums = (1,2,3,4,5,6,7,8,9,0);
    my $nums = $#nums;
    my @all = ([@letters],[@sym],[@nums]);
    while($i<$length)
    {
        #print "first rand: ".$#all."\n";
        my $r = int(rand($#all+1));
        #print "Random array: $r\n";
        my @t = @{@all[$r]};
        #print "rand: ".$#t."\n";
        my $int = int(rand($#t + 1));
        #print "Random value: $int = ".@{$all[$r]}[$int]."\n";
        $ret.= @{$all[$r]}[$int];
        $i++;
    }

    return $ret;
}

sub is_integer
{
   defined @_[1] && @_[1] =~ /^[+-]?\d+$/;
}

1;

