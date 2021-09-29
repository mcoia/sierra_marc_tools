#!/usr/bin/perl

package dataHandler;

use pQuery;
use Try::Tiny;
use Data::Dumper;
use lib qw(./); 

our %filesOnDisk = ();
sub new
{
    my ($class, @args) = @_;
    my $self = _init($class, @args);
    bless $self, $class;
    return $self;
}

sub _init
{
    my $self = shift;
    my @trace = ();
    my %files = ();
    $self =
    {
        sourceID => shift,
        name => shift,
        dbHandler => shift,
        prefix => shift,
        driver => shift,
        screenshotDIR => shift,
        log => shift,
        debug => shift,
        downloadDIR => shift,
        json => shift,
        clientID => shift,
        URL => '',
        webuser => '',
        webpass => '',
        dbhost => '',
        dbdb => '',
        dbuser => '',
        dbpass => '',
        dbport => '',
        clusterID => -1,
        error => 0,
        trace => \@trace,
        postgresConnector => undef,
        screenShotStep => 0,
        downloadedFiles => \%files
    };
    if($self->{sourceID} && $self->{dbHandler} && $self->{prefix} && $self->{driver} && $self->{log})
    {
        $self = fillVars($self);
        $self = parseJSON($self);
    }
    else
    {
        setError($self, "Couldn't initialize");
    }
    return $self;
}

sub fillVars
{
    my ($self) = @_[0];

    my $query = "select 
    cluster.id,
    cluster.postgres_host,
    cluster.postgres_db,
    cluster.postgres_port,
    cluster.postgres_username,
    cluster.postgres_password
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

    my @results = @{$self->{dbHandler}->query($query)};
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
    }

    $self->{error} = 1 if($#results == -1);

    return $self;
}

sub parseJSON
{
    my $self = shift;
    if( ref $self->{"json"} eq 'HASH' )
    {
        while ( (my $key, my $value) = each( %{$self->{json}} ) )
        {
            $self->{$key} = $value;
        }
    }
    return $self;
}


sub setSpecificDate
{
    my ($self) = shift;
    my $dbDate = shift;
    if($dbDate =~ m/\d{4}\-\d{1,2}\-\d{1,2}/)
    {
        $self->{specificMonth} = $dbDate;
    }
    else
    {
        $self->{specificMonth} = undef;
    }
}

sub injectMARCToDB
{
    my ($self) = shift;
    my $marcFile = shift;

    # doUpdateQuery($self,$query,"Cleaning Staging $self->{prefix}"."_bnl_stage",\@vals);

}

sub doUpdateQuery
{
    my $self = shift;
    my $query = shift;
    my $stdout = shift;
    my $dbvars = shift;

    $self->{log}->addLine($query);
    $self->{log}->addLine(Dumper($dbvars)) if $self->{debug};
    print "$stdout\n";

    $self->{dbHandler}->updateWithParameters($query, $dbvars);
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
        $tries++;
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

    addTrace($self, "handleAnchorClick", $anchorString);
    # get the string ready for js regex
    $anchorString =~ s/\?/\\?/g;
    $anchorString =~ s/\//\\\//g;
    $anchorString =~ s/\./\\\./g;
    $anchorString =~ s/\[/\\\[/g;
    $anchorString =~ s/\]/\\\]/g;
    $anchorString =~ s/\(/\\\(/g;
    $anchorString =~ s/\)/\\\)/g;

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
            my $error = flattenArray($self, $correctPageString, 'string');
            setError($self, "Clicked anchor but didn't find string(s): $error");
            takeScreenShot($self, "handleAnchorClick_$anchorString"."_string_not_found");
        }
    }
    return $worked;
}

sub setError
{
    my $self = shift;
    my $error = shift;
    $self->{error} = $error;
}

sub getError
{
    my $self = shift;
    return $self->{error};
}

sub addTrace
{
    my $self = shift;
    my $func = shift;
    my $add = shift;
    $add = flattenArray($self, $add, 'string');
    my @t = @{$self->{trace}};
    push (@t, $func .' / ' . $add);
    $self->{trace} = \@t;
}

sub getTrace
{
    my $self = shift;
    return $self->{trace};
}

sub flattenArray
{
    my $self = shift;
    my $array = shift;
    my $desiredResult = shift;
    my $retString = "";
    my @retArray = ();
    if(ref $array eq 'ARRAY')
    {
        my @a = @{$array};
        foreach(@a)
        {
            $retString .= "$_ / ";
            push (@retArray, $_);
        }
        $retString = substr($retString, 0, -3); # lop off the last trailing ' / '
    }
    elsif(ref $array eq 'HASH')
    {
        my %a = %{$array};
        while ( (my $key, my $value) = each(%a) )
        {
            $retString .= "$key = $value / ";
            push (@retArray, ($key, $value));
        }
        $retString = substr($retString, 0, -3); # lop off the last trailing ' / '
    }
    else # must be a string
    {
        $retString = $array;
        @retArray = ($array);
    }
    return \@retArray if ( lc($desiredResult) eq 'array' );
    return $retString;
}

sub checkIfCorrectPage
{
    my $self = shift;
    my $string = shift;
    my @strings = @{flattenArray($self, $string, 'array')};
    addTrace($self, "checkIfCorrectPage", $string);
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

    $string =~ trim($self, $string);
    $string2 =~ trim($self, $string2);
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
    my ($self) = shift;
    my @files = @{readSaveFolder($self)};
    foreach(@files)
    {
        if(!$filesOnDisk{$_})
        {
            # print "Detected new file: $_\n";
            checkFileReady($self, $self->{downloadDIR} ."/".$_);
            return $self->{saveFolder} . "/" . $_;
        }
    }
    return 0;
}

sub readSaveFolder
{
    my ($self) = shift;
    my $init = shift || 0;

    %filesOnDisk = () if $init;
    my $pwd = $self->{downloadDIR};
    # print "Opening '".$self->{saveFolder}."'\n";
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
    return \@files;
}

sub checkFileReady
{
    my ($self) = shift;
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

sub getHTMLBody
{
    my ($self) = shift;
    my $body = $self->{driver}->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    $body =~ s/[\r\n]//g;
    return $body;
}

sub escapeData
{
    my $self = shift;
    my $d = shift;
    $d =~ s/'/\\'/g;   # ' => \'
    $d =~ s/\\/\\\\/g; # \ => \\
    return $d;
}


sub takeScreenShot
{
    my $self = shift;
    my $action = shift;
    $action =~ s/\s{1,1000}/_/g;
    $action =~ s/\/{1,1000}/_/g;
    $action =~ s/\\{1,1000}/_/g;
    $self->{screenShotStep}++;
    # $self->{log}->addLine("screenshot self: ".Dumper($self));
    # print "ScreenShot: ".$self->{screenshotDIR}."/".$self->{name}."_".$self->{screenShotStep}."_".$action.".png\n";
    $self->{driver}->capture_screenshot($self->{screenshotDIR}."/".$self->{name}."_".$self->{screenShotStep}."_".$action.".png", {'full' => 1});
}

sub trim
{
    my $self = shift;
	my $string = shift;
	$string =~ s/^[\t\s]+//;
	$string =~ s/[\t\s]+$//;
	return $string;
}

sub getError
{
    my $self = shift;
    return $self->{error};
}

sub getTrace
{
    my $self = shift;
    return $self->{trace};
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
    undef $self->{postgresConnector};
}


1;