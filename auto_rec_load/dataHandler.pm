#!/usr/bin/perl

package dataHandler;

use pQuery;
use Try::Tiny;
use Data::Dumper;
use lib qw(./); 
use Archive::Zip;
use MARC::Record;
use MARC::File;
use MARC::File::XML (BinaryEncoding => 'utf8');
use MARC::File::USMARC;
use Unicode::Normalize;
use File::Path qw(make_path remove_tree);
use parent commonTongue;

our %filesOnDisk = ();
sub new
{
    my ($class, @args) = @_;
    my ($self, $args) = $class->SUPER::new(@args);
    @args = @{$args};
    $self = _init($self, @args);
    return $self;
}

sub _init
{
    my $self = shift;
    $self->{sourceID} = shift;
    $self->{name} = shift;
    $self->{driver} = shift;
    $self->{debugScreenshotDIR} = shift;
    $self->{downloadDIR} = shift;
    $self->{json} = shift;
    $self->{clientID} = shift;
    $self->{thisJobID} = shift;
    $self->{URL} = '';
    $self->{webuser} = '';
    $self->{webpass} = '';
    $self->{dbhost} = '';
    $self->{dbdb} = '';
    $self->{dbuser} = '';
    $self->{dbpass} = '';
    $self->{dbport} = '';
    $self->{clusterID} = -1;
    $self->{postgresConnector} = undef;
    $self->{screenShotStep} = -1;
    $self->{screenShotDIR} = -1;

    if($self->{sourceID} && $self->{dbHandler} && $self->{prefix} && $self->{driver} && $self->{log} && $self->{thisJobID})
    {
        $self = _fillVars($self);
        $self = $self->parseJSON($self->{json});
    }
    else
    {
        $self->setError("Couldn't initialize");
    }

    return $self;
}

sub _fillVars
{
    my ($self) = @_[0];

    my $query = "select 
    cluster.id,
    cluster.postgres_host,
    cluster.postgres_db,
    cluster.postgres_port,
    cluster.postgres_username,
    cluster.postgres_password,
    source.scrape_img_folder
    from
    ".$self->{prefix}.
    "_cluster cluster
    join
    ".$self->{prefix}.
    "_client client on (client.cluster = cluster.id)
    join
    ".$self->{prefix}.
    "_source source on (source.client = client.id)
    where
    source.id = '".$self->{sourceID}."'";

    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $self->{log}->addLine("Cluster vals: ".Dumper(\@row));
        $self->{clusterID} = @row[0];
        $self->{dbhost} = @row[1];
        $self->{dbdb} = @row[2];
        $self->{dbport} = @row[3];
        $self->{dbuser} = @row[4];
        $self->{dbpass} = @row[5];
        $self->{screenShotDIR} = @row[6];
    }

    $self->{error} = 1 if($#results == -1);

    return $self;
}

sub waitForPageLoad
{
    my ($self) = shift;
    my $done = $self->{driver}->execute_script("return document.readyState === 'complete';");
    # print "Page done: $done\n";
    my $stop = 0;
    my $tries = 0;
    
    while(!$done && !$stop)
    {
        $done = $self->{driver}->execute_script("return document.readyState === 'complete';");
        print "Waiting for Page load check: $tries\n";
        $stop = 1 if $tries > 10;
        $tries++;
        sleep 1;
    }
    return $done if !$done;
    $done = 0;
    my $body = getHTMLBody($self);
    sleep 1;
    my $newBody = getHTMLBody($self);
    my $stop = 0;
    $tries = 0;
    # An attempt to make sure the page is done loading any javascript alterations
    while( ($newBody ne $body) && !$stop)
    {
        print "Waiting for Page load check: $tries\n";
        sleep 1;
        $body = $newBody;
        $newBody = getHTMLBody($self);
        $stop = 1 if $tries > 20;
        $tries++;
        $done = 1 if ($newBody eq $body);
    }
    return $done;
}

sub handleLoginPage
{
    my $self = shift;
    my $formType = shift;
    my $userBoxID = shift;
    my $passBoxID = shift;
    my $errorLoginString = shift;
    
    my $worked;
    my $submitFunction = "
        var thisElem;
        function getParentForm(elem)
        {
            console.log(elem.tagName);

            if(elem.tagName.toLowerCase() === 'form')
            {
                return elem;
            }
            else
            {
                console.log(elem.parentElement.nodeName);
                if(elem.parentElement)
                {
                    return getParentForm(elem.parentElement);
                }
                else
                {
                    return undef;
                }
            }
        }

        !!codehere!!

        var formElement = getParentForm(thisElem);
        if(formElement)
        {
            formElement.submit();
            return 1;
        }
        else
        {
            return 0;
        }
    ";

    my $js;
    if($formType eq 'id')
    {
        $js = "
        document.getElementById('" .$userBoxID. "').value='".$self->{webuser}."';
        document.getElementById('" .$passBoxID. "').value='".$self->{webpass}."';
        thisElem = document.getElementById('" .$userBoxID. "');
        ";
    }
    elsif($formType eq 'tagname')
    {
        $js = "
        var doms = document.getElementsByTagName('input');
        var boxfills = {user: 0, pass: 0};
        
        for(var i=0;i<doms.length;i++)
        {
            var thisaction = doms[i].getAttribute('name');
            if(thisaction.match(/" .$userBoxID. "/g))
            {
                doms[i].value = '".$self->{webuser}."';
                thisElem = doms[i];
                boxfills.user = 1;
            }
            if(thisaction.match(/" .$passBoxID. "/g))
            {
                doms[i].value = '".$self->{webpass}."';
                thisElem = doms[i];
                boxfills.pass = 1;
            }
        }
        if(!boxfills.user || !boxfills.pass)
        {
            return 0;
        }
        ";
    }
    $submitFunction  =~ s/!!codehere!!/$js/g;
    $self->{log}->addLine("Executing: $submitFunction");
    my $worked = $self->{driver}->execute_script($submitFunction);
    waitForPageLoad($self);
    takeScreenShot($self, 'handledLoginPage');
    my $error = checkPageForString($self, $errorLoginString);
    $worked = 0 if $error;

    return $worked;
}

sub handleAnchorClick
{
    my $self = shift;
    my $anchorString = shift;
    my $correctPageString = shift;
    my $hrefMatch = shift || 0;
    my $propVal = $hrefMatch ? 'getAttribute("href")' : 'textContent';

    $anchorString = escapeStringForJSRegEX($self, $anchorString);
    $self->addTrace( "handleAnchorClick", $anchorString);


    my $js = "
        var doms = document.getElementsByTagName('a');
        
        for(var i=0;i<doms.length;i++)
        {
            var thisaction = doms[i]." . $propVal . ";
            if(thisaction !== null && thisaction.match(/" . $anchorString . "/gi))
            {
                doms[i].click();
                return 1;
            }
        }
        return 0;
        ";
    $self->{log}->addLine("Executing: $js");
    my $worked = $self->{driver}->execute_script($js);
    waitForPageLoad($self);
    takeScreenShot($self, "handleAnchorClick_$anchorString");
    if($correctPageString)
    {
        $worked = checkIfCorrectPage($self, $correctPageString);
        if(!$worked)
        {
            my $error = $self->flattenArray($correctPageString, 'string');
            $self->setError( "Clicked anchor but didn't find string(s): $error");
            takeScreenShot($self, "handleAnchorClick_$anchorString"."_string_not_found");
        }
    }
    return $worked;
}

sub handleParentAnchorClick
{
    my $self = shift;
    my $childTagType = shift;
    my $childTagStringMatch = shift;
    my $childPropValMatch = shift;
    my $correctPageString = shift;
    my $parentTagType = shift || 'a';


    $self->addTrace( "handleParentAnchorClick", $childTagStringMatch);
    $childTagStringMatch = escapeStringForJSRegEX($self, $childTagStringMatch);

    my $js = "
        var doms = document.getElementsByTagName('".$childTagType."');
        var matched = 0;
        for(var i=0;i<doms.length;i++)
        {
            var thisaction = doms[i]." . $childPropValMatch . ";
            if(thisaction !== null && thisaction.match(/" . $childTagStringMatch . "/gi))
            {
                var parent = findParent(doms[i]);
                if(parent)
                {
                    parent.click();
                    return 1;
                    matched = 1;
                    break;
                }
            }
        }
        return matched;

        function findParent(curNode)
        {
            var tParent = curNode.parentElement;
            if(tParent)
            {
                if(tParent.tagName.match(/" . $parentTagType . "/i))
                {
                    return tParent;
                }
                else
                {
                    return findParent(tParent);
                }
            }
            return 0;
        }
        ";
    $self->{log}->addLine("Executing: $js");
    my $worked = $self->{driver}->execute_script($js);
    waitForPageLoad($self);
    takeScreenShot($self, "handleAnchorClick_$childTagStringMatch");
    if($correctPageString)
    {
        my $tries = 0;
        $worked = checkIfCorrectPage($self, $correctPageString);
        while(!$worked && $tries < 20) # Some websites are completely JS, and the page load isn't reliable, Let's do 20 seconds of page parses
        {
            sleep 1;
            $worked = checkIfCorrectPage($self, $correctPageString);
            $tries++;
        }
        if(!$worked)
        {
            my $error = $self->flattenArray($correctPageString, 'string');
            $self->setError( "Clicked anchor but didn't find string(s): $error");
            takeScreenShot($self, "handleAnchorClick_$childTagStringMatch"."_string_not_found");
        }
        else
        {
            takeScreenShot($self, "handleAnchorClick_after_click");
        }
    }
    return $worked;
}

sub handleDOMTriggerOrSetValue
{
    my $self = shift;
    my $type = shift; # 'setval' or 'action'
    my $DOMID = shift; # this can be null if you supply $domType and $elementProperty instead
    my $data = shift;
    my $domType = shift; # "input" or "textbox", etc.
    my $elementAttributesRef = shift;
    my $elementTextContentMatch = shift;

    my $worked = undef;
    $data =~ s/'/\\'/g;
    $data = "value  = '$data'" if($type eq 'setval');
    %elementAttributes = %{$elementAttributesRef} if($elementAttributesRef);
    $self->addTrace( "handleDOMTriggerFire", $DOMID);
    print "heading to search routine\n";
    $DOMID = findElementByAttributes($self, $domType, 'id', $elementAttributesRef, $elementTextContentMatch) if($elementAttributesRef && $domType);
    print "Received: $DOMID\n";
    if(''.$DOMID eq '0' && ($elementAttributesRef && $domType))
    {
        print "Dropping into action\n";
        # in the case where the target element doesn't have an ID: we just need the search code to perform the action
        findElementByAttributes($self, $domType, 'id', $elementAttributesRef, $elementTextContentMatch, $data);
    }
    else
    {
        my $js = "
            if(document.getElementById('".$DOMID."'))
            {
                document.getElementById('".$DOMID."').$data;
                return 1;
            }
            return 0;
            ";
        
        $self->{log}->addLine("Executing: $js");
        $worked = $self->{driver}->execute_script($js);
        waitForPageLoad($self);
        takeScreenShot($self, "TriggerOrSetValue_$data");
    }
    return $worked;
}

sub findElementByAttributes
{
    my $self = shift;
    my $domType = shift; # "input" or "textbox", etc.
    my $returnProp = shift;
    my $elementAttributesRef = shift;
    my $elementTextContentMatch = shift;
    my $elementAction = shift;

    my %elementAttributes = undef;
    %elementAttributes = %{$elementAttributesRef} if($elementAttributesRef);
    $elementTextContentMatch = escapeStringForJSRegEX($self, $elementTextContentMatch) if ($elementTextContentMatch);
    if(%elementAttributes && $domType && $returnProp)
    {
        my $js = "
        var doms = document.getElementsByTagName('".$domType."');
        var attribs = {";
        while ( (my $key, my $value) = each(%elementAttributes) )
        {
            $js .= "'$key' : '$value',\n";
        }
        $js = substr($js,0,-2);
        $js.="};
        
        for(var i=0;i<doms.length;i++)
        {
            var matched = 0;
            for (var key in attribs)
            {
                if(doms[i].getAttribute(key))
                {
                    var rgxp = new RegExp(attribs[key],'i');
                    if(doms[i].getAttribute(key).match(rgxp))
                    {";
                    if($elementTextContentMatch)
                    {
                        $js.="
                        if(!doms[i].textContent.match(/$elementTextContentMatch/i))
                        {
                            matched = 0;
                            break;
                        }";
                    }
                    $js.="
                        matched = 1;
                    }
                    else
                    {
                        matched = 0;
                        break;
                    }
                }
            }
            if(matched)
            {
                ";
                if($elementAction)
                {
                    $js .= "doms[i].$elementAction;
                    return 1;
                    ";
                }
                $js.="
                if(doms[i].getAttribute('$returnProp'))
                {
                    return doms[i].getAttribute('$returnProp');
                }
            }
        }
        return 0;
        ";
        $self->{log}->addLine("Executing: $js");
        my $worked = $self->{driver}->execute_script($js);
        takeScreenShot($self, "findElementByAttributes_$domType");
        return $worked;
    }
    return 0;
}

sub handleOverDriveTableReadyCheck
{
    my $self = shift;
    my $key = shift;
    $key = escapeStringForJSRegEX($self, $key);
    my $js = "
        var doms = document.getElementsByTagName('div');
        var matched = 0;
        for(var i=0;i<doms.length;i++)
        {
            if(doms[i].parentElement && doms[i].parentElement.tagName.match(/td/i))
            {
                if(doms[i].textContent.match(/$key/i))
                {
                    matched = 1;
                }
                if(matched)
                {
                    for(var j=0;j<doms[i].parentElement.previousElementSibling.children;j++)
                    {
                        if(doms[i].parentElement.previousElementSibling.children[j].tagName.match(/div/i))
                        {
                            return doms[i].parentElement.previousElementSibling.children[j].textContent();
                        }
                    }
                    break;
                }
            }
        }
        return 0;
    ";
    $self->{log}->addLine("Executing: $js");
    my $worked = $self->{driver}->execute_script($js);
    takeScreenShot($self, "overdrive_readyCheck");
    return $worked;
}

sub doWebActionAfewTimes
{
    my $self = shift;
    my $actionCode = shift;
    my $retryCount = shift;
    my $result = 0;

    $actionCode = '$result = ' . $actionCode . ";";
    my $loops = 0;
    $self->{log}->addLine("Executing: $actionCode");
    # return handleAnchorClick($self, "/Insights", "Title status", 1);
    while( ($retryCount > $loops) && !$result )
    {
        eval $actionCode;
        $loops++;
    }
    $self->setError(0) if ($result);
    return $result;
}

sub checkIfCorrectPage
{
    my $self = shift;
    my $string = shift;
    my @strings = @{$self->flattenArray($string, 'array')};
    $self->addTrace( "checkIfCorrectPage", $string);
    my $ret = 1;
    foreach(@strings)
    {
        last if !$ret;
        $ret = checkPageForString($self, $_);
    }
    return $ret;
}

sub checkPageForString
{
    my $self = shift;
    my $string = shift;
    my $caseSensitive = shift || 0;
    my $body = getHTMLBody($self);
    return stringContains($self, $body, $string);
}

sub escapeStringForJSRegEX
{
    my $self = shift;
    my $string = shift;
    # get the string ready for js regex
    $string =~ s/\?/\\?/g;
    $string =~ s/\//\\\//g;
    $string =~ s/\./\\\./g;
    $string =~ s/\[/\\\[/g;
    $string =~ s/\]/\\\]/g;
    $string =~ s/\(/\\\(/g;
    $string =~ s/\)/\\\)/g;
    return $string;
}
sub stringContains
{
    my $self = shift;
    my $string = shift;
    my $string2 = shift;
    my $caseSensitive = shift || 0;
    my $ret = 0;
    if($caseSensitive)
    {
        if($string =~ m/$string2/g)
        {
            $ret = 1;
        }
    }
    else
    {
        if($string =~ m/$string2/gi)
        {
            $ret = 1;
        }
    }
    return $ret;
}

sub stringMatch
{
    my $self = shift;
    my $string = shift;
    my $string2 = shift;
    my $caseSensitive = shift || 0;

    $string =~ $self->trim($string);
    $string2 =~ $self->trim($string2);
    my $ret = 0;
    if($caseSensitive)
    {
        if($string eq $string2)
        {
            $ret = 1;
        }
    }
    else
    {
        if(lc $string eq lc $string2)
        {
            $ret = 1;
        }
    }
    return $ret;
}

sub getCorrectTableHTML
{
    my $self = shift;
    my $searchString = shift;
    my $body = getHTMLBody($self);
    my $ret;
    pQuery("table",$body)->each(sub {
        shift;
        if(!$ret)
        {
            my $thisTable = pQuery($_)->toHtml();
            pQuery("thead > tr > th", $_)->each( sub {
                shift;
                if(!$ret) # save some cycles
                {
                    $ret = $thisTable if(stringMatch($self, pQuery($_)->text(), $searchString));
                }
            });
            if(!$ret) ## maybe the table doesn't have "thead", let's travers tr > th instead
            {
                pQuery("tr > th", $_)->each( sub {
                    shift;
                    if(!$ret) # save some cycles
                    {
                        $ret = $thisTable if(stringMatch($self, pQuery($_)->text(), $searchString));
                    }
                });
            }
            if(!$ret) ## maybe the table doesn't have "th", let's travers tr > td instead
            {
                pQuery("tr > td", $_)->each( sub {
                    shift;
                    if(!$ret) # save some cycles
                    {
                        $ret = $thisTable if(stringMatch($self, pQuery($_)->text(), $searchString));
                    }
                });
            }
        }
    });
    $self->{log}->addLine("Detected table for '$searchString'\n$ret") if $self->{debug};
    return $ret;
}

sub getHrefFromAnchorHTML
{
    my $self = shift;
    my $html = shift;

    $self->{log}->addLine("Getting href from anchor: '$html'") if $self->{debug};
    $html =~ s/^.*?<[aA]\s*.*?href.*?['"]([^'^"]*)['"].*/\1/;
    $self->{log}->addLine("Found: '$html'") if $self->{debug};
    return $html;
}

sub seeIfNewFile
{
    my $self = shift;
    my @files = @{readSaveFolder($self)};
    foreach(@files)
    {
        if(!$filesOnDisk{$_})
        {
            # print "Detected new file: $_\n";
            checkFileReady($self, $self->{downloadDIR} ."/".$_);
            return $self->{downloadDIR} . "/" . $_;
        }
    }
    return 0;
}

sub readSaveFolder
{
    my $self = shift;
    my $init = shift || 0;

    %filesOnDisk = () if $init;
    my @files = ();
    my $pwd = $self->{downloadDIR};
    # print "Opening '".$self->{downloadDIR}."'\n";
    opendir(DIR,$pwd) or die "Cannot open $pwd\n";
    my @thisdir = readdir(DIR);
    closedir(DIR);
    foreach my $file (@thisdir) 
    {
        # print "Checking: $file\n";
        if( ($file ne ".") && ($file ne "..") && !($file =~ /\.part/g))  # ignore firefox "part files"
        {
            # print "Checking: $file\n";
            if (-f "$pwd/$file")
            {
                @stat = stat "$pwd/$file";
                my $size = $stat[7];
                if($size ne '0')
                {
                    push(@files, "$file");
                    if($init)
                    {
                        $filesOnDisk{$file} = 1;
                    }
                }
            }
        }
    }
    $self->{log}->addLine("Files on disk: " . Dumper(\@files)) if $self->{debug};
    return \@files;
}

sub checkFileReady
{
    my $self = shift;
    my $file = shift;
    my @stat = stat $file;
    my $baseline = $stat[7];
    $baseline+=0;
    my $now = -1;
    while($now != $baseline)
    {
        @stat = stat $file;
        $now = $stat[7];
        sleep 1;
        @stat = stat $file;
        $baseline = $stat[7];
        $baseline += 0;
        $now += 0;
    }
}

sub extractCompressedFile
{
    my $self = shift;
    my $file = shift;
    my @ret;
    my @extensionExtracts = @{@_[0]};

    $self->{log}->addLine("extractCompressFile file: [$file]") if $self->{debug};
    # lowercase all of the extensions
    for my $b(0..$#extensionExtracts)
    {
        @extensionExtracts[$b] = lc @extensionExtracts[$b];
    }

    print "Full file: $file \n";
    my $extension = getFileExt($self, $file);
    print "Read Extension: $extension\n";
    my $extractFolder = $self->{downloadDIR} . '/extract';
    ensureFolderExists($self, $extractFolder);
    cleanFolder($self, $extractFolder);
    if(lc $extension =~ m/zip/g)
    {
        # Read a Zip file
        my $zip = Archive::Zip->new();
        my $tries = 0;
        my $giveUpAfter = 10; # I think 10 seconds is enough waiting
        while( !($zip->read( $file ) == AZ_OK) && ($tries < $giveUpAfter) )
        {
            $tries++;
            # sometimes the zip file is too fresh, and we need to let the file system to do whatever it does.
            sleep 1;
        }
        unless ( $zip->read( $file ) == AZ_OK )
        {
            $self->setError( "Could not open $file");
            $self->addTrace( "Could not open $file");
            return 'error reading zip';
        }
        my @list = $zip->memberNames();
        my %fileDedupe = ();
        foreach(@list)
        {
            my $thisMember = $_;
            my $extract = 0;
            if(@extensionExtracts)
            {
                foreach(@extensionExtracts)
                {
                    print "checking extention $_ \n";
                    @splitdots = split(/\./, $thisMember);
                    my $thisExt = getFileExt($self, $thisMember);
                    $extract = 1 if(lc $thisExt =~ m/$_/g);
                }
            }
            else
            {
                $extract = 1;
            }
            if($extract && !$fileDedupe{$thisMember})
            {
                my $outputMemberFilename = $thisMember;
                $outputMemberFilename =~ s/\?//g;
                $outputMemberFilename =~ s/\///g;
                $outputMemberFilename =~ s/\[//g;
                $outputMemberFilename =~ s/\]//g;
                $outputMemberFilename =~ s/\(//g;
                $outputMemberFilename =~ s/\)//g;
                $outputMemberFilename =~ s/\s//g;
                $outputMemberFilename =~ s/\\/\//g;
                $zip->extractMember($thisMember, $extractFolder . "/$outputMemberFilename");
                $fileDedupe{$thisMember} = 1;
                push (@ret, $extractFolder . "/$outputMemberFilename");
            }
        }
    }
    else
    {
        push (@ret, $file);
    }
    return \@ret;
}

sub readMARCFile
{
    my $self = shift;
    my $marcFile = shift;
    my $fExtension = getFileExt($self, $marcFile);
    my $file;
    $self->{log}->addLine("Reading $marcFile");
    $file = MARC::File::USMARC->in($marcFile) if lc $fExtension !=~ m/xml/;
    $file = MARC::File::XML->in($marcFile) if lc $fExtension =~ m/xml/;
    my @ret;
    local $@;
    eval
    {
        while ( my $marc = $file->next() )
        {
            push (@ret, $marc);
        }
        1;  # ok
    } or do
    {
        $file->close();
        @ret = @{readMARCFileRaw($self, $marcFile)};
    };

    $file->close();
    undef $file;
    return \@ret;
}

sub readMARCFileRaw
{
    my $self = shift;
    my $marcFile = shift;

    use IO::File;
    IO::File->input_record_separator("\x1E\x1D");

    my $file = IO::File->new("< $marcFile");

    $self->{log}->addLine("Reading RAW $marcFile");

    my @ret;
    my $count = 0;
    while (my $raw = <$file>)
    {
        $count++;
        my $marc = MARC::Record->new_from_usmarc($raw);
        my @warnings = $marc->warnings();
        if (@warnings)
        {
            $self->addTrace("readMARCFileRaw", "$marcFile could not be fully read. Record $count had warnings");
            $self->setError("$marcFile could not be fully read. Record $count had warnings");
        }
        push (@ret, $marc);
    }

    $file->close();
    IO::File->input_record_separator("\n");
    undef $file;
    undef $count;
    return \@ret;
}

sub getFileExt
{
    my $self = shift;
    my $filename = shift;
    my @fsp = split(/\./,$filename);
    my $ret = pop @fsp;
    return $ret;
}

sub getFileNameWithoutPath
{
    my $self = shift;
    my $filename = shift;
    my @fsp = split(/\//, $filename);
    my $ret = pop @fsp;
    return $ret;
}

sub getsubfield
{
    my $shift = shift;
    my $marc = shift;
    my $tag = shift;
    my $subtag = shift;
    my $ret;
    #print "Extracting $tag $subtag\n";
    if($marc->field($tag))
    {
        if($tag+0 < 10)
        {
            #print "It was less than 10 so getting data\n";
            $ret = $marc->field($tag)->data();
        }
        elsif($marc->field($tag)->subfield($subtag))
        {
            $ret = $marc->field($tag)->subfield($subtag);
        }
    }
    #print "got $ret\n";
    $ret = utf8::is_utf8($ret) ? Encode::encode_utf8($ret) : $ret;
    return $ret;
}

sub createFileEntry
{
    my $self = shift;
    my $file = shift;
    my $key = shift;
    $key = $self->escapeData($key);
    my $query = "INSERT INTO 
    $self->{prefix}"."_file_track (fkey, filename, source, client)
    VALUES(?, ?, ?, ?)";
    my @vals = ($key, $file, $self->{sourceID}, $self->{clientID});
    $self->doUpdateQuery( $query, undef, \@vals);
    return getFileID($self, $key, $file);
}

sub getFileID
{
    my $self = shift;
    my $key = shift;
    my $file = shift;

    my $ret = 0;
    my $query = "select max(id) from $self->{prefix}"."_file_track file
    where
    source = " .$self->{sourceID}. "
    and client = " .$self->{clientID};
    if($file)
    {
        $file = $self->escapeData($file);
        $query .= " and filename = '$file'";
    }
    if($key)
    {
        $key = $self->escapeData($key);
        $query .= " and fkey = '$key'";
    }
    $self->{log}->addLine($query);
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $ret = @row[0];
    }
    return $ret;
}

sub createImportStatusFromRecordArray
{
    my $self = shift;
    my $fileID = shift;
    my $jobID = shift;
    my $rec = shift;
    my $tag = makeTag($self, $fileID);
    my @records = @{$rec};
    my $queryStart = "INSERT INTO 
    $self->{prefix}"."_import_status (file, record_raw, tag, z001, job)\nVALUES\n";
    my @vals = ();
    my $query = $queryStart;
    my $loops = 0;
    foreach(@records)
    {
        $loops++;
        my $record = $self->convertMARCtoXML($_);
        my $z01 = getsubfield($self, $_, '001');
        push (@vals, $fileID);
        push (@vals, $record);
        push (@vals, $tag);
        push (@vals, $z01);
        push (@vals, $jobID);
        $query .= "(?, ?, ?, ?, ?),";
        # chunking
        if($loops % 100 == 0)
        {
            $query = substr($query,0,-1); # remove the last comma
            createImportStatus($self, $query, \@vals);
            @vals = ();
            $query = $queryStart;
            $loops=0;
        }
    }
    if($loops > 0) # in case there was exactly % 100 records, we check that there is more than 0
    {
        $query = substr($query,0,-1); # remove the last comma
        createImportStatus($self, $query, \@vals);
        @vals = ();
        $query = $queryStart;
        $loops=0;
    }
    undef @vals;
    undef $loops;
}

sub getColumnFromCSV
{
    my $self = shift;
    my $file = shift;
    my $columnNameOrPosition = shift || '0'; # default to first column
    my @ret = ();

    my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1 });
    open my $fh, "<:encoding(utf8)", $file or die "$file: $!";
    my $rownum = 0;
    my $colPOS = -1;
    if($columnNameOrPosition =~ m/^\d+$/) # The passed value is numeric, assuming it's a column position number, 0 based
    {
        $colPOS = $columnNameOrPosition;
        print "set colpos = $colPOS\n";
    }

    while (my $row = $csv->getline ($fh))
    {
        if($colPOS == -1) # we've not figured out the column yet
        {
            print "ref:\n";
            print ref $row;
            print "\n";
            my $col = 0;
            foreach(@{$row})
            {
                $_ =~ s/\x{feff}//g;
                $self->{log}->addLine("comparing: '$_' to '$columnNameOrPosition'");
                if( (lc($_)) eq (lc($columnNameOrPosition)) )
                {
                    $colPOS = $col;
                    $self->{log}->addLine("matched");
                }
                $col++;
            }
        }
        else
        {
            push @ret, $row->[$colPOS];
        }
    }
    close $fh;

    return \@ret;
}

sub createImportStatus
{
    my $self = shift;
    my $query = shift;
    my $v = shift;
    my @vals = @{$v};
    my $worked = $self->doUpdateQuery( $query, undef, \@vals );
    return $worked;
}

sub makeTag
{
    my $self = shift;
    my $fileID = shift;
    my $ret = 0;
    my $query = "SELECT concat(cast(date(grab_time) as char),'_',c.name,'_',s.name) as tag from 
    $self->{prefix}"."_file_track f,
    $self->{prefix}"."_client c,
    $self->{prefix}"."_source s
    where
    c.id=f.client and
    s.id=f.source and
    f.id= $fileID";
    $self->addTrace("makeTag","Making Tag");
    $self->{log}->addLine($query);
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $ret = @row[0];
    }
    return $ret;
}

sub createJob
{
    my $self = shift;
    my $query = "INSERT INTO 
    $self->{prefix}"."_job (current_action, type, source)
    VALUES(null, ?, ?)";
    my @vals = ('processmarc', $self->{sourceID});
    $self->doUpdateQuery( $query, undef, \@vals);
    return getJobID($self);
}

sub getJobID
{
    my $self = shift;

    my $ret = 0;
    my $query = "select max(id) from $self->{prefix}"."_job job
    where
    status = 'new' and
    type = 'processmarc'";
    $self->{log}->addLine($query);
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $ret = @row[0];
    }
    return $ret;
}

sub readyJob
{
    my $self = shift;
    my $jobID = shift || $self->{job};
    my $query = "UPDATE $self->{prefix}"."_job SET status = 'ready' where id = $jobID";
    my @vars = ();
    $self->doUpdateQuery( $query, undef, \@vars );
    undef @vars;
}

sub startThisJob
{
    my $self = shift;
    my $query = "UPDATE $self->{prefix}"."_job SET status = 'processing', start_time = NOW() WHERE id = $self->{thisJobID}";
    my @vars = ();
    $self->doUpdateQuery( $query, undef, \@vars );
    undef @vars;
}

sub updateThisJobStatus
{
    my $self = shift;
    my $action = shift;
    my $status = shift || 'processing';
    my $query =
    "UPDATE
    ".$self->{prefix}.
    "_job
    set
    status = ?,
    current_action = ?
    where
    id = ?";
    my @vals = ($status, $action, $self->{thisJobID});
    $self->doUpdateQuery($query, undef, \@vals);
}

sub finishThisJob
{
    my $self = shift;
    my $finalString = shift;
    updateThisJobStatus($self, $finalString, 'finished');
}

sub updateSourceScrapeDate
{
    my $self = shift;
    my $sourceID = shift || $self->{sourceID};
    my $query = "UPDATE $self->{prefix}"."_source SET last_scraped = now() where id = $sourceID";
    my @vars = ();
    $self->doUpdateQuery( $query, undef, \@vars );
    undef @vars;
}

sub decideToProcessFile
{
    my $self = shift;
    my $sourceFileName = shift;
    $sourceFileName = lc $sourceFileName;
    my $ret = "";
    foreach($self->{deletes})
    {
        my $scrap = lc $_;
        if($sourceFileName =~ m/$scrap/g)
        {
            $ret = 1;
        }
    }
    if($self->{adds})
    {
        foreach($self->{adds})
        {
            my $scrap = lc $_;
            if($sourceFileName =~ m/$scrap/g)
            {
                $ret = 1;
                last;
            }
        }
    }
    else
    {
        $ret = 1;
    }
    return $ret;
}

sub ensureFolderExists
{
    my $self = shift;
    my $path = shift;
    my $mode = shift || 0711;
    print "mode: $mode\n";
    if ( !(-d $path) )
    {
        print "creating: '" . $path. "'\n";
        make_path($path, {
        verbose => 1,
        chmod => $mode,
        mode => $mode,
        });
    }
}

sub cleanFolder
{
    my $self = shift;
    my $folder = shift;
    if( (-d $folder) && ($folder ne '/') )
    {
        my @files = ();
        @files = @{$self->dirtrav(\@files,$folder)};
        foreach(@files)
        {
            print "Deleting: $_\n";
            # unlink $_ if(-f $_);
        }
    }
}

sub getHTMLBody
{
    my $self = shift;
    my $body = $self->{driver}->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    $body =~ s/[\r\n]//g;
    return $body;
}

sub cleanScreenShotFolder
{
    my $self = shift;
    ensureFolderExists($self, $self->{screenShotDIR}, 0777);
    cleanFolder($self, $self->{screenShotDIR});
}

sub takeScreenShot
{
    my $self = shift;
    my $action = shift;
    $action =~ s/\s{1,1000}/_/g;
    $action =~ s/\/{1,1000}/_/g;
    $action =~ s/\\{1,1000}/_/g;
    $action =~ s/&{1,1000}/_/g;
    $action =~ s/\?{1,1000}/_/g;

    # remove those high-chart utf8 characters
    $action =~ s/[\x80-\x{FFFF}]//g;

    # keep it reasonable please
    $action = substr($action,0,30);

    $self->{screenShotStep}++;
    # $self->{log}->addLine("screenshot self: ".Dumper($self));
    # print "ScreenShot: ".$self->{debugScreenshotDIR}."/".$self->{name}."_".$self->{screenShotStep}."_".$action.".png\n";
    $self->{driver}->capture_screenshot($self->{debugScreenshotDIR}."/".$self->{name}."_".$self->{screenShotStep}."_".$action.".png", {'full' => 1}) if($self->{debugScreenshotDIR});
    $self->{driver}->capture_screenshot($self->{screenShotDIR}."/".$self->{name}."_".$self->{screenShotStep}."_".$action.".png", {'full' => 1});
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
    undef $self->{postgresConnector};
}

sub hammerTime
{
    my $self = shift;
    my $hashID = shift;
my $js = "
function triggerEventsOnElement(element, hash) {
    
    var matched = 0;
    for(let i = element.length-1; i >= 0; i--) {
        if (element[i].parentElement && element[i].parentElement.tagName.match(/td/i)) {
                if (element[i].textContent.match(hash)) {
                matched = 1;
            }
            if (matched) {
                dispatchCustomEvents(element[i].parentElement.parentElement.parentElement.parentElement);
                dispatchCustomEvents(element[i].parentElement.parentElement.parentElement);
                dispatchCustomEvents(element[i].parentElement.parentElement);
                dispatchCustomEvents(element[i].parentElement);
                break;
            }
        }
    }
}

function dispatchCustomEvents(element) {
    console.log(element);
    var selection = window.getSelection();
    var range = document.createRange();
    range.selectNode(element);
    selection.addRange(range);
    if (document.selection) {
        document.selection.empty();
    }
    console.log(window.getSelection());
    console.log(document.activeElement);
    element.tabIndex = '-1';
    element.focus();
    element.dispatchEvent(new CustomEvent('focus'));
    element.dispatchEvent(new CustomEvent('focusin'));
    element.dispatchEvent(new CustomEvent('enter'));
    element.dispatchEvent(new CustomEvent('pointerup'));
    element.dispatchEvent(new CustomEvent('pointerover'));
    var evt = new CustomEvent('keypress');
    evt.which = 40;
    evt.keyCode = 40;
    element.dispatchEvent(evt);
    element.dispatchEvent(new CustomEvent('change'));
    element.dispatchEvent(new PointerEvent('pointerrawupdate', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('pointerover', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('pointerover', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('pointerenter', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('pointerdown', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('pointermove', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('pointerup', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new PointerEvent('gotpointercapture', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new FocusEvent('focusin', {
        'width': element.getBoundingClientRect().left + window.scrollX,
        'height': element.getBoundingClientRect().top + window.scrollY
    }));
    element.dispatchEvent(new WheelEvent(''));
    element.dispatchEvent(new FocusEvent('focusout'));
    element.dispatchEvent(new FocusEvent('focus'));
    element.dispatchEvent(new MouseEvent('mouseover', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('mousedown', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('mousemove', {'bubbles': true, view: window}));
    document.dispatchEvent(new MouseEvent('scroll', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('mousemove'));
    element.dispatchEvent(new MouseEvent('focus', {'bubbles': true, view: window}));
    evt = new CustomEvent('click');
    element.dispatchEvent(evt);

    element.dispatchEvent(new MouseEvent('mouseover', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('click', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('click', {'bubbles': true, view: window, button: 2}));

    element.dispatchEvent(new PointerEvent('pointerover'));
    element.dispatchEvent(new PointerEvent('pointerenter'));
    element.dispatchEvent(new PointerEvent('pointerdown'));

    element.dispatchEvent(new MouseEvent('mouseover', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('click', {'bubbles': true, view: window}));
    element.dispatchEvent(new MouseEvent('click', {'bubbles': true, view: window, button: 2}));

}

triggerEventsOnElement(document.getElementsByTagName('div'),'$hashID');

";
    
    return $js;
    
}

1;