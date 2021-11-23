#!/usr/bin/perl

package job;

use lib qw(./);
use Data::Dumper;
use JSON;

use Loghandler;
use importStatus;

use parent commonTongue;

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
    $self->{job} = shift;
    $self->{status} = undef;
 
    if($self->{job} && $self->{dbHandler} && $self->{prefix} && $self->{log})
    {
        $self = fillVars($self);
        if($self->getError())
        {
            $self->addTrace("Error loading job");
        }
    }
    else
    {
        $self->setError("Couldn't initialize job object");
    }
    return $self;
}

sub fillVars
{
    my $self = shift;

    my $query = "select 
    id from
    ".$self->{prefix}.
    "_job
    where
    id = ".$self->{job};

    my @results = @{$self->{dbHandler}->query($query)};

    $self->{error} = "No Job with that ID number: " . $self->{job} if($#results == -1);

    return $self;
}

sub runJob
{
    my $self = shift;

    my %imports = %{getImportIDs($self)}; # only "new" rows
    @importIDs = ( keys %imports );

    my %recordTracker = ();
    $recordTracker{"convertedSuccess"} = 0;
    $recordTracker{"convertedFailed"} = 0;
    $recordTracker{"outputSuccess"} = 0;
    $recordTracker{"outputFailed"} = 0;
    $recordTracker{"total"} = 0;
    updateJobStatus($self, 'Job Started');
    markImportsAsWorking($self, \@importIDs, "processing");
    my %fileOutPutDestination = %{addsOrUpdates($self, \%imports)};


my $before = new Loghandler("/mnt/evergreen/tmp/auto_rec_load/before.txt");
my $after = new Loghandler("/mnt/evergreen/tmp/auto_rec_load/after.txt");

    my $currentSource = 0;
    # Convert the marc, store results in the DB, weeding out errors
    while($#importIDs > -1)
    {
        $recordTracker{"total"}++;
        my $iID = shift @importIDs;
        my @values = @{$imports{$iID}};
        my $tag = @values[0];
        my $marcXML = @values[1];
        my $filename = @values[2];
        my $sourceID = @values[3];
        my $import;
        my $perl = '$import = new importStatus($self->{log}, $self->{dbHandler}, $self->{prefix}, $self->{debug}, $iID);';

        # Instantiate the import
        {
            local $@;
            eval
            {
                eval $perl;
                1;  # ok
            } or do
            {
                updateImportError($self, $iID, "Couldn't read something correctly, error creating importStatus object");
                $recordTracker{"convertedFailed"}++;
            };
        }
        {
            local $@;
            eval
            {
                updateJobStatus($self, "Converting MARC importID $iID");
                $import->convertMARC("adds", $before, $after);
                $import->setStatus("Converted MARC");
                
                $import->writeDB();
                $recordTracker{"convertedSuccess"}++;
                1;  # ok
            } or do
            {
                updateImportError($self, $iID, "Couldn't manipulate the MARC: importStatus object");
                $recordTracker{"convertedFailed"}++;
            };
        }
        undef $import;

        if($#importIDs == -1) # get more
        {
            %imports = undef; # Hopefully garbage collector comes :)
            %imports = %{getImportIDs($self)};
            @importIDs = ( keys %imports );
            %fileOutPutDestination = %{addsOrUpdates($self, \%imports)};
        }
    }

    
    # # Write the resulting MARC to output file, sorting them into their approproate output folders
    # my %imports = %{getImportIDsForOutputFile($self)};
    # @importIDs = ( keys %imports );
    # %outputTrack = ();
    # while($#importIDs > -1)
    # {
        # my $iID = shift @importIDs;
        # my @values = $imports{$iID};
        # print Dumper(\@values);
        # exit;
        # my $tag = @values[0];
        # my $marcXML = @values[1];
        # my $filename = @values[2];
        # my $sourceID = @values[2];
        # setupSourceOutputFiles($self, $sourceID, $tag) if($currentSource != $sourceID);
        # $currentSource = $sourceID if($currentSource != $sourceID);
        # # Instantiate the import
        # {
            # local $@;
            # eval
            # {
                # eval $perl;
                # 1;  # ok
            # } or do
            # {
                # updateImportError($self, $iID, "Couldn't read something correctly, error creating importStatus object");
                # $recordTracker{"outputFailed"}++;
            # };
        # }
        # {
            # local $@;
            # eval
            # {
                # updateJobStatus($self, 'Converting MARC importID $iID');
                # $import->convertMARC();
                # $import->setStatus("Converted MARC");
                # $import->writeDB();
                # $recordTracker{"outputSuccess"}++;
                # 1;  # ok
            # } or do
            # {
                # updateImportError($self, $iID, "Couldn't manipulate the MARC: importStatus object");
            # };
        # }
        # undef $import;

        # if($#importIDs == -1) # get more
        # {
            # %imports = undef; # Hopefully garbage collector comes :)
            # %imports = %{getImportIDsForOutputFile($self)};
            # @importIDs = ( keys %imports );
        # }
    # }

}

sub outputFileRecordSortingHat
{
    my $self = shift;
    my $importRef = shift;
    my %imports = %{$importRef};

    my %fileAnswers = ();
    while ( (my $key, my $value) = each(%imports}) )
    {
        my @ar = @{$value};
        my $sourceFileName = @ar[2];
        $sourceFileName = lc $sourceFileName;
        my $answer = "adds";
        if(!$fileAnswers{$sourceFileName})
        {
            foreach($self->{deletes}) #if it's a delete, then we don't do anything
            {
                my $scrap = lc $_;
                if($sourceFileName =~ m/$scrap/g)
                {
                    $fileAnswers{$sourceFileName} = "deletes";
                    $answer = "deletes";
                }
            }
            if($self->{adds}) # ensuring that there is a match, if none, then ignore the file
            {
                my $found = 0;
                foreach($self->{adds}) #if "adds" is defined in the json string, then we only want to deal with records that match any of those scraps
                {
                    my $scrap = lc $_;
                    $found =  1 if($sourceFileName =~ m/$scrap/g); 
                }
                $answer = undef if !$found;
            }
        }
        else
        {
            $answer = $fileAnswers{$sourceFileName};
        }
        push (@ar, $answer);
        $imports{$key} = \@ar;
    }
    return \%imports;
}

sub addsOrUpdates
{
    my $self = shift;
    my $importRef = shift;
    my %imports = %{$importRef};

    if($self->{locationCodeRegex} && $self->{checkAddsVsUpdates} && $self->{extPG})
    {
        my %z001Map = ();
        my $z001IDString = "";
        while ( (my $key, my $value) = each(%imports}) )
        {
            my @ar = @{$value};
            my $z001 = @ar[4];
            my @empty = ();
            $z001Map{$z001} = \@empty if(!$z001Map{$z001});
            @empty = @{$z001Map{$z001}};
            push (@empty, $key);
            $z001Map{$z001} = \@empty;
            $z001IDString .= "'$z001',";
        }
        $z001IDString = substr($z001IDString, 0, -1);
        if($z001IDString !='')
        {
            my $query = "
            select vv.field_content from
            sierra_view.bib_record br
            join sierra_view.bib_record_item_record_link brirl on (brirl.bib_record_id = br.record_id)
            join sierra_view.item_record ir on (ir.record_id = brirl.item_record_id and ir.location_code ~'".$self->{locationCodeRegex}."')
            join sierra_view.varfield_view vv on (vv.record_id=br.record_id and vv.marc_tag='001' and
            vv.field_content in($z001IDString))";
            $self->{log}->addLine($query);
            my @results = @{$self->{extPG}->query($query)};
            foreach(@results)
            {
                my @row = @{$_};
                my @ids;
                @ids = @{$z001Map{@row[0]}} if $z001Map{@row[0]};
                foreach(@ids)
                {
                    $ret{$_} = "updates";
                }
            }
            while ( (my $key, my $value) = each(%imports}) )
            {
                $ret{$key} = "adds" if !$ret{$key};
            }
        }
    }
}

sub setupSourceOutputFiles
{
    my $self = shift;
    my $sourceID = shift;
    my $tag = shift;
    my $query = "SELECT
    source.json_connection_detail,
    cluster.postgres_host,
    cluster.postgres_db,
    cluster.postgres_port,
    cluster.postgres_username,
    cluster.postgres_password
    FROM
    ".$self->{prefix} ."_source source
    join
    ".$self->{prefix} ."_client client on (client.id=source.client)
    join
    ".$self->{prefix} ."_cluster cluster on (cluster.id=client.cluster)
    WHERE
    source.id = $sourceID";
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $self->{json} = decode_json( @row[0] );
        $self->{dbhost} = @row[1];
        $self->{dbdb} = @row[2];
        $self->{dbport} = @row[3];
        $self->{dbuser} = @row[4];
        $self->{dbpass} = @row[5];

        $self->parseJSON($self->{json});

        setupExternalPGConnection($self) if(!$self->{extPG} && $self->{checkAddsVsUpdates});
        $self->{adds_file_prefix} = @row[1];
        if($self->{folders})
        {
            my $mobUtil = new Mobiusutil();
            while ( (my $key, my $value) = each(%{$self->{folders}}) )
            {
                $self->{'outfile_'. $key} = $mobUtil->chooseNewFileName($value, $tag, "mrc");
            }
            undef $mobUtil;
        }
        last; # should only be one row returned
    }
}

sub setupExternalPGConnection
{
    my $self = shift;
    my @needed = qw(dbhost dbdb dbport dbuser dbpass);
    my $missing = 0;
    while(@needed)
    {
        $missing = 1 if !($self->{$_});
    }
    if(!$missing)
    {
        $self->{extPG} = DBhandler($self->{"dbdb"},$self->{"dbhost"},$self->{"dbuser"},$self->{"dbpass"},$self->{"dbport"});
    }
}

sub updateImportError
{
    my $self = shift;
    my $iID = shift;
    my $error = shift;
    my $query = "UPDATE
    ".$self->{prefix} ."_import_status
    SET
    status = ?
    WHERE
    id = ?";
    my @vals = ($error, $iID);
    $self->doUpdateQuery($query, undef, \@vals);
}

sub markImportsAsWorking
{
    my $self = shift;
    my $idsRef = shift;
    my $statusString = shift;
    my @ids = @{$idsRef};
    if($#ids > -1)
    {
        my $commaString = join(',',@ids);
        my $query = "UPDATE
        ".$self->{prefix} ."_import_status
        SET status = ?
        WHERE
        id in( $commaString )";
        my @vals = ($statusString);
        $self->doUpdateQuery($query, undef, \@vals);
    }
}

sub getImportIDs
{
    my $self = shift;
    my $requiredStatus = shift || 'new';
    my $additionalWhere = shift || '';
    my $limit = shift || 500;
    my %ret = ();
    my $query = "
    SELECT ais.id, ais.tag, ais.record_tweaked, aft.filename, aft.source, ais.z001 FROM
    ".$self->{prefix} ."_import_status ais
    JOIN ".$self->{prefix} ."_file_track aft on (aft.id=ais.file)
    WHERE
    ais.job = " .$self->{job} . "
    AND ais.status = '$requiredStatus'
    $additionalWhere
    LIMIT $limit";
    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        my $id = shift @row;
        $ret{$id} = \@row;
    }
    return \%ret;
}

sub clearOutputFileTrackDB
{
    my $self = shift;
    my $idsref = shift;
    my @ids = @{$idsref};
    my $idString = join(',',@ids);
    my $query = "DELETE FROM
    ".$self->{prefix} ."_output_file_track
    WHERE
    import_id in($idString)";
    my @vars = ();
    $self->doUpdateQuery($query, undef, \@vars);
}

sub recordOutputFileDB
{
    my $self = shift;
    my $importIDsref = shift;
    my %ids = %{$importIDsref};
    my $queryStart = "INSERT INTO
    ".$self->{prefix} ."_output_file_track (filename,import_id)
    VALUES
    ";
    my @vars = ();
    my $query = $queryStart;
    while ( (my $key, my $value) = each(%ids) )
    {
        push(@vars, $value);
        push(@vars, $key);
        $query .= "(?, ?),";
    }
    $query = substr($query,0,-1); #remove the last comma
    $self->doUpdateQuery($query, undef, \@vars);
}

sub updateJobStatus
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
    my @vals = ($status, $action, $self->{job});
    $self->doUpdateQuery($query, undef, \@vals);
}

sub finishJob
{
    my $self = shift;
    my $finalString = shift;
    updateJobStatus($self, $finalString, 'finished');
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;