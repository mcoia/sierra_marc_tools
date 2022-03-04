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

    if($self->{sourceID} && $self->{dbHandler} && $self->{prefix} && $self->{driver} && $self->{log})
    {
        $self = fillVars($self);
        $self = $self->parseJSON($self->{json});
    }
    else
    {
        $self->setError("Couldn't initialize");
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

    $self->addTrace( "handleAnchorClick", $anchorString);
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
            my $error = $self->flattenArray($correctPageString, 'string');
            $self->setError( "Clicked anchor but didn't find string(s): $error");
            takeScreenShot($self, "handleAnchorClick_$anchorString"."_string_not_found");
        }
    }
    return $worked;
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
        unless ( $zip->read( $file ) == AZ_OK )
        {
            $self->setError( "Could not open $file");
            $self->addTrace( "Could not open $file");
            return 'error reading zip';
        }
        my @list = $zip->memberNames();
        foreach(@list)
        {
            my $thisMember = $_;
            my $extract = 0;
            if(@extensionExtracts)
            {
                foreach(@extensionExtracts)
                {
                    @splitdots = split(/\./, $thisMember);
                    my $thisExt = getFileExt($self, $thisMember);
                    $extract = 1 if(lc $thisExt =~ m/$_/g);
                }
            }
            else
            {
                $extract = 1;
            }
            if($extract)
            {
                $zip->extractMember($thisMember, $extractFolder . "/$thisMember");
                push (@ret, $extractFolder . "/$thisMember");
            }
        }
    }
    else
    {
        push (@ret, $self->{downloadDIR} . $file);
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
    $file = MARC::File::USMARC->in($marcFile) if $fExtension !=~ m/xml/;
    $file = MARC::File::XML->in($marcFile) if $fExtension =~ m/xml/;
    my @ret;
    local $@;
    eval
    {
        while ( my $marc = $file->next() )
        {
            push (@ret, $marc);
        }
        1;  # ok
    };

    $file->close();
    undef $file;
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
    $self->{prefix}"."_job (current_action)
    VALUES(null)";
    my @vals = ();
    $self->doUpdateQuery( $query, undef, \@vals);
    return getJobID($self);
}

sub getJobID
{
    my $self = shift;

    my $ret = 0;
    my $query = "select max(id) from $self->{prefix}"."_job job
    where
    status = 'new'";
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
    if ( !(-d $path) )
    {
        make_path($path, {
        verbose => 1,
        mode => 0711,
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
            unlink $_ if(-f $_);
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
    print "creating: '" .$self->{screenShotDIR}. "'\n" unless -d $self->{screenShotDIR};
    make_path($self->{screenShotDIR},  {chmod => 0755} )  unless -d $self->{screenShotDIR};
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


1;