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
 
    if($self->{job} && $self->{dbHandler} && $self->{prefix} && $self->{log})
    {
        $self = _fillVars($self);
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

sub _fillVars
{
    my $self = shift;

    my $query = "select 
    id from
    ".$self->{prefix}.
    "_job
    where
    id = ".$self->{job};

    my @results = @{$self->{dbHandler}->query($query)};

    $self->setError("No Job with that ID number: " . $self->{job}) if($#results == -1);
    if($#results > -1)
    {
        $query = "SELECT
        distinct source.json_connection_detail,
        cluster.postgres_host,
        cluster.postgres_db,
        cluster.postgres_port,
        cluster.postgres_username,
        cluster.postgres_password
        FROM
        ".$self->{prefix} ."_import_status import
        join
        ".$self->{prefix} ."_file_track file on (file.id=import.file)
        join
        ".$self->{prefix} ."_source source on (file.source=source.id)
        join
        ".$self->{prefix} ."_client client on (client.id=source.client)
        join
        ".$self->{prefix} ."_cluster cluster on (cluster.id=client.cluster)
        WHERE
        import.job = ".$self->{job};
        @results = @{$self->getDataFromDB($query)};
        foreach(@results)
        {
            my @row = @{$_};
            # Clean some of the json up
            @row[0] =~ s/\n/ /g;
            @row[0] =~ s/\s/ /g;
            $self->{json} = decode_json( @row[0] );
            $self->{dbhost} = @row[1];
            $self->{dbdb} = @row[2];
            $self->{dbport} = @row[3];
            $self->{dbuser} = @row[4];
            $self->{dbpass} = @row[5];

            $self->parseJSON($self->{json});

            setupExternalPGConnection($self) if(!$self->{extPG} && $self->{checkAddsVsUpdates});

            last; # should only be one row returned
        }
    }

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
    $recordTracker{"total"} = 0;
    updateJobStatus($self, 'Job Started');
    markImportsAsWorking($self, \@importIDs, "processing");
    my %fileOutPutDestination = %{outputFileRecordSortingHat($self, \%imports)}; # this routine appends "adds" "deletes" "updates" to each record in position 4
    %fileOutPutDestination = %{addsOrUpdates($self, \%fileOutPutDestination)}; # this routine appends ILSID and a stripped ILSMARC Record in position 5 and 6

    startJob($self);

    my $currentSource = 0;
    my %fileOutput = ();
    my %fileOutputIDMap = ();
    # Convert the marc, store results in the DB, weeding out errors
    my $before = new Loghandler("/mnt/evergreen/tmp/auto_rec_load/before.txt");
    my $after = new Loghandler("/mnt/evergreen/tmp/auto_rec_load/after.txt");
    while($#importIDs > -1)
    {
        $recordTracker{"total"}++;
        my $iID = shift @importIDs;
        my @values = @{$fileOutPutDestination{$iID}};
        my $tag = @values[0];
        my $filename = @values[1];
        my $sourceID = @values[2];
        my $z001 = @values[3];
        my $type = @values[4];
        my $ilsRecordNum = @values[5];
        my $ilsMARC = @values[6];
        if($type eq 'ignore')
        {
            $import->setItype($type);
            $import->writeDB();
            updateImportError($self, $iID, "Filename is ignored");
        }
        else
        {
            if($currentSource != $sourceID)
            {
                writeOutputMARC($self, \%fileOutput, \%fileOutputIDMap, $tag);
                %fileOutput = ();
                %fileOutputIDMap = ();
                $currentSource = $sourceID;
            }
            elsif($recordTracker{"total"} % 20000 == 0 ) # break the output files up roughly every 20k
            {
                writeOutputMARC($self, \%fileOutput, \%fileOutputIDMap, $tag);
                %fileOutput = ();
                %fileOutputIDMap = ();
            }
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
                    print "*********************failed*************************";
                    $self->{log}->addLogLine("\n\nError during Instantiating importStatus ID $iID - " .$@ . "\n\n");
                    updateImportError($self, $iID, "Couldn't read something correctly, error creating importStatus object");
                    $self->addTrace("runJob","Error creating importStatus $iID");
                    $self->setError("One or more import objects failed");
                    $recordTracker{"convertedFailed"}++;
                };
            }
            {
                local $@;
                eval
                {
                    updateJobStatus($self, "Converting MARC importID $iID");
                    print "Converting...\n" if $self->{debug};
                    $import->convertMARC($type);
                    print "Converted...\n" if $self->{debug};
                    $import->setStatus("Converted MARC");
                    $import->setItype($type);

                    $fileOutput{$type} = '' if(!$fileOutput{$type});
                    if(!$fileOutputIDMap{$type})
                    {
                        my @t = ();
                        $fileOutputIDMap{$type} = \@t;
                    }

                    my $marc = MARC::Record->new_from_xml($import->getTweakedRecord());

                    # count the remaining 856's (when we are processing a delete) - and set the flag in the database if none remain
                    if($type eq 'deletes')
                    {
                        my $remaining856s = $self->countMARC856Fields($marc);
                        $import->setNo856s(1) if ($remaining856s == 0);
                    }

                    if($ilsMARC)
                    {
                        print "There was an existing ILS record\nMerging some fields\n" if $self->{debug};
                        $before->addLine($marc->as_formatted());

                        # merge any and all 856 fields (special logic here)
                        $marc = $self->mergeMARC856($marc, $ilsMARC);

                        # merge any and all 890 fields
                        $marc = $self->mergeMARCFields($marc, $ilsMARC, '890', 'a');

                        # merge any and all 891 fields, keeping this record in the delete flag if we have deletes
                        $marc = $self->mergeMARCFields($marc, $ilsMARC, '891', 'a') if($type eq 'deletes');

                        # And if we have a non-delete record, be sure and remove the "delete" flag in the 891 for this one
                        $marc = $self->mergeMARCFields($marc, $ilsMARC, '891', 'a', $import->getmarc_editor_name()) if($type ne 'deletes');

                        $import->setILSID($ilsRecordNum) if $ilsRecordNum; #Turns out we don't need the checkdigit . $self->calcSierraCheckDigit($ilsRecordNum)) 

                        $import->setTweakedRecord($self->convertMARCtoXML($marc));

                        $after->addLine($marc->as_formatted());
                    }
                    print "created marc object...\n" if $self->{debug};
                    if($self->{"outfile_$type"})
                    {
                        $fileOutput{$type} .= $marc->as_usmarc();
                        my @t = @{$fileOutputIDMap{$type}};
                        push (@t, $iID);
                        $fileOutputIDMap{$type} = \@t;
                        $recordTracker{"convertedSuccess"}++;
                        print "writing success\n" if $self->{debug};
                    }
                    else
                    {
                        $import->setStatus("Output Folder: $type is not defined, cannot write to disk");
                        print "writing fail\n" if $self->{debug};
                    }
                    $import->writeDB();
                    1;  # ok
                } or do
                {
                    $self->{log}->addLogLine("Error during converting/writing MARC Status ID $iID - " .$@);
                    updateImportError($self, $iID, "Couldn't manipulate the MARC: importStatus object");
                    $self->addTrace("runJob","Error performing conversion importStatus $iID");
                    $self->setError("One or more import objects failed to perform");
                    $recordTracker{"convertedFailed"}++;
                };
            }
            undef $import;
        }
        if($#importIDs == -1) # get more
        {
            %imports = undef; # Hopefully garbage collector comes :)
            %imports = %{getImportIDs($self)};
            @importIDs = ( keys %imports );
            %fileOutPutDestination = %{outputFileRecordSortingHat($self, \%imports)};
            %fileOutPutDestination = %{addsOrUpdates($self, \%fileOutPutDestination)};
        }
    }
    writeOutputMARC($self, \%fileOutput, \%fileOutputIDMap);
    my $totalLine = "Job's Done; Total: " . $recordTracker{"total"} . " success: " . $recordTracker{"convertedSuccess"} . " fail: " . $recordTracker{"convertedFailed"};
    finishJob($self, $totalLine);
}

sub writeOutputMARC
{
    my $self = shift;
    my $outputRef = shift;
    my $outputIDRef = shift;
    my $tag = shift;
    my %fileOutput = %{$outputRef};
    my %fileMap = %{$outputIDRef};

    while ( (my $type, my $output) = each(%fileOutput) )
    {
        $self->{log}->addLogLine("Writing $type -> ". $self->{"outfile_$type"});
        if( ($self->{"outfile_$type"}) && ($output ne '' ) )
        {
            print "Writing to: " . $self->{"outfile_$type"} . "\n" if $self->{debug};
            my $outputFile = new Loghandler($self->{"outfile_$type"});
            $outputFile->appendLine($output);
            if($fileMap{$type})
            {
                my $outfileID = createOutFileEntry($self, $self->{"outfile_$type"} );
                if($outfileID)
                {
                    my @t = @{$fileMap{$type}};
                    my $ids = "";
                    $ids .= ' ? ,' foreach(@t);
                    $ids = substr($ids, 0, -1);
                    my $query = "UPDATE
                    ".$self->{prefix} ."_import_status ais
                    SET
                    out_file = ?,
                    status = ?
                    WHERE ais.id in( $ids )";
                    my @vals = ($outfileID, "emitted to disk");
                    push (@vals, @t);
                    $self->doUpdateQuery($query, undef, \@vals);
                }
            }
        }
    }

    undef %fileOutput;
    undef %fileMap;
    setupSourceOutputFiles($self, $tag) if $tag;
}

sub createOutFileEntry
{
    my $self = shift;
    my $filename = shift;
    $self->{log}->addLine("createOutFileEntry called: $filename");
    my $ret = findPreExistingOutFileInDB($self, $filename);
    if(!$ret)
    {
        my $premax = getMaxOutFileEntry($self);
        my $query = "
        INSERT INTO 
        ".$self->{prefix} ."_output_file_track (filename)
        values(?)";
        my @vars = ($filename);
        $self->doUpdateQuery($query, undef, \@vars);
        my $postmax = getMaxOutFileEntry($self);
        $ret = $postmax if($postmax ne $premax);
    }
    return $ret;
}

sub findPreExistingOutFileInDB
{
    my $self = shift;
    my $filename = shift;
    my $ret = 0;
    my $query = "
    SELECT MIN(id) FROM
    ".$self->{prefix} ."_output_file_track
    WHERE filename = ?";
    my @vars = ($filename);
    my @results = @{$self->getDataFromDB($query, \@vars)};
    foreach(@results)
    {
        @row = @{$_};
        $ret = @row[0];
    }
    return $ret;
}

sub getMaxOutFileEntry
{
    my $self = shift;
    my $ret = 0;

    $query = "SELECT MAX(id) \"id\" FROM
    ".$self->{prefix} ."_output_file_track";
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $ret = @row['id'];
    }
    return $ret;
}

sub outputFileRecordSortingHat
{
    my $self = shift;
    my $importRef = shift;
    my %imports = %{$importRef};
    my %fileAnswers = ();
    while ( (my $key, my $value) = each(%imports) )
    {
        my @ar = @{$value};
        my $sourceFileName = @ar[1];
        $sourceFileName = lc $sourceFileName;
        # print "Filename: $sourceFileName\n";
        my $answer = "adds";
        if(!$fileAnswers{$sourceFileName})
        {
            if($self->{deletes})
            {
                foreach(@{$self->{deletes}}) #if it's a delete, then we don't do anything
                {
                    my $scrap = lc $_;
                    if($sourceFileName =~ m/$scrap/g)
                    {
                        $fileAnswers{$sourceFileName} = "deletes";
                        $answer = "deletes";
                    }
                }
            }
            if($self->{adds}) # ensuring that there is a match, if none, then ignore the file
            {
                my $found = 0;
                foreach(@{$self->{adds}}) #if "adds" is defined in the json string, then we only want to deal with records that match any of those scraps
                {
                    my $scrap = lc $_;
                    $found =  1 if($sourceFileName =~ m/$scrap/g); 
                }
                $answer = "ignore" if !$found;
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
    my %z001Map = ();
    my $z001IDString = "";

    while ( (my $key, my $value) = each(%imports) )
    {
        my @ar = @{$value};
        my $z001 = @ar[3];
        my $type = @ar[4];
        $self->{log}->addLine("Parsing addsorupdates");
        $self->{log}->addLine(Dumper(\@ar)) if $self->{debug};
        my @empty = ();
        $z001Map{$z001} = \@empty if(!$z001Map{$z001});
        @empty = @{$z001Map{$z001}};
        push (@empty, $key);
        $z001Map{$z001} = \@empty;
        $z001IDString .= "\$ooone\$$z001\$ooone\$,";
    }
    $z001IDString = substr($z001IDString, 0, -1);
    if($z001IDString ne '')
    {
        # Figure out if these bibs are already int he system for the importing library
        # This uses a clever bit of location code magic to narrow the query to only items for this library
        if($self->{locationCodeRegex} && $self->{checkAddsVsUpdates} && $self->{extPG})
        {
            my $query = "
            select vv.field_content,vv.record_id from
            sierra_view.bib_record br
            join sierra_view.bib_record_item_record_link brirl on (brirl.bib_record_id = br.record_id)
            join sierra_view.item_record ir on (ir.record_id = brirl.item_record_id and ir.location_code ~\$\$".$self->{locationCodeRegex}."\$\$)
            join sierra_view.varfield_view vv on (vv.record_id=br.record_id and vv.marc_tag=\$\$001\$\$ and
            vv.field_content in($z001IDString))";
            $self->{log}->addLine($query);
            my @results = @{$self->{extPG}->query($query)};
            foreach(@results)
            {
                my @row = @{$_};
                my @ids = ();
                @ids = @{$z001Map{@row[0]}} if $z001Map{@row[0]};
                foreach(@ids)
                {
                    # print "Looping: $_\n" if $self->{debug};
                    if($imports{$_})
                    {
                        my @ar = @{$imports{$_}};
                        $self->{log}->addLine(Dumper(\@ar)) if $self->{debug};
                        my $type = @ar[4];
                        @ar[4] = "updates" if ($type eq 'adds'); # We only care about distinguishing adds from "updates". deletes are ignoreed here;
                        $self->{log}->addLine(Dumper(\@ar)) if $self->{debug};
                        $imports{$_} = \@ar;
                    }
                }
            }

        }
    }
    # Follow up with another query to find non-library scoped bibs that match these 001's.
    # This will get the 856's,890's,891's that already exist in the system, so that we can merge them onto our incoming record
    # this query looks bad because Sierra uses Postgres Views, and to get the best, most efficient results, queries look crappy (nesting, etc)
    my %z001Map = ();
    my $z001IDString = "";
    while ( (my $key, my $value) = each(%imports) )
    {
        my @ar = @{$value};
        my $z001 = @ar[3];
        my $type = @ar[4];
        my @empty = ();
        $z001Map{$z001} = \@empty if(!$z001Map{$z001});
        @empty = @{$z001Map{$z001}};
        push (@empty, $key);
        $z001Map{$z001} = \@empty;
        $z001IDString .= "\$ooone\$$z001\$ooone\$,";
    }
    $z001IDString = substr($z001IDString, 0, -1);
    if($self->{extPG} && $z001IDString ne '')
    {
        my $query = "
        select * from
        (
            select svvv.record_num,svvv.marc_tag,svvv.marc_ind1,svvv.marc_ind2,svvv.occ_num,svvv.field_content
            from
            sierra_view.varfield_view svvv

            where
            record_id in
            (
                select vv.record_id from
                sierra_view.varfield_view vv
                where
                vv.marc_tag=\$\$001\$\$ and
                vv.field_content in($z001IDString)
            )
        ) as a
        where 
        ( marc_tag=\$\$856\$\$ or marc_tag=\$\$890\$\$ or marc_tag=\$\$891\$\$ or marc_tag=\$\$001\$\$ )
        order by 1,2,5";
        $self->{log}->addLine($query);
        my @results = @{$self->{extPG}->query($query)};
        my $currentRecord = "";
        my $marc_record = undef;
        while($#results > -1)
        {
            my $r = shift @results;
            my @row = @{$r};
            my $record_num = @row[0];
            my $marc_tag = @row[1];
            my $marc_ind1 = @row[2] || ' '; # catch null -> ' ' 
            my $marc_ind2 = @row[3] || ' ';
            my $field_content = @row[5];
            if( $currentRecord != $record_num )
            {
                if($marc_record && $marc_record->field('001') && $marc_record->field('001')->data()) #not the first time through, and we've created a marc record to save into the hash.
                {
                    %imports = %{addsOrUpdates_append($self, \%imports, $marc_record, \%z001Map, $currentRecord)};
                }
                $marc_record = MARC::Record->new();
                $currentRecord = $record_num;
            }
            if($marc_tag+0 > 10)
            {
                # print "'$field_content'\n";
                my @subs = split(/\|/, $field_content);
                my @subs_pass = ();
                foreach(@subs)
                {
                    if(length(substr($_, 0, 1)) > 0)
                    {
                        my $subfield = substr($_, 0, 1);
                        $_ = substr($_, 1);
                        push (@subs_pass, ($subfield, $_));
                    }
                }
                $marc_ind1 = ' ' if length($marc_ind1) != 1;
                $marc_ind2 = ' ' if length($marc_ind2) != 1;
                my $field = MARC::Field->new($marc_tag, $marc_ind1, $marc_ind2, @subs_pass);
                $marc_record->insert_grouped_field($field);
            }
            elsif($marc_tag+0 < 11)
            {
                my $field = MARC::Field->new($marc_tag, $field_content);
                $marc_record->insert_grouped_field($field);
            }
            %imports = %{addsOrUpdates_append($self, \%imports, $marc_record, \%z001Map, $currentRecord)} if( $#results == -1 );
        }
    }

    $self->{log}->addLine(Dumper(\%imports)) if $self->{debug};
    return \%imports;
}

sub addsOrUpdates_append
{
    my $self = shift;
    my $importRef = shift;
    my $marc_record = shift;
    my $z001MapRef = shift;
    my $currentRecord = shift;
    my %imports = %{$importRef};
    my %z001Map = %{$z001MapRef};
    my @ids = @{$z001Map{$marc_record->field('001')->data()}} if $z001Map{$marc_record->field('001')->data()};
    foreach(@ids)
    {
        print "saving Sierra marc import ID: $_\n" if $self->{debug};
        if($imports{$_})
        {
            my @ar = @{$imports{$_}};
            $self->{log}->addLine(Dumper(\@ar)) if $self->{debug};
            push (@ar, $currentRecord);
            push (@ar, $marc_record);
            $self->{log}->addLine(Dumper(\@ar)) if $self->{debug};
            $imports{$_} = \@ar;
        }
    }
    return \%imports;
}

sub runCheckILSLoaded
{
    my $self = shift;
    my %imports = %{getImportIDsNotLoaded($self)}; # only "new" rows
    my @importIDs = ( keys %imports );
    my %importsWithGlue = %{fileILSLoaded($self, \%imports)};
    my $maxID = 0;
    while($#importIDs > -1)
    {
        my $iID = shift @importIDs;
        my @values = @{$importsWithGlue{$iID}};
        my $z001 = @values[0];
        my $tag = @values[1];
        my $filename = @values[2];
        my $loadType = @values[3];
        my $ILSID = @values[4];
        $maxID = $iID if ($iID+0 > $maxID+0);

        if($ILSID || (!$ILSID && $loadType eq 'deletes'))
        {
            $ILSID = -1 if(!$ILSID && $loadType eq 'deletes'); # it's considered loaded when the record is supposed to be deleted and we didn't find the record on the ILS
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
                    $self->{log}->addLogLine("\n\nError during Instantiating importStatus ID $iID - " .$@ . "\n\n");
                    updateImportError($self, $iID, "runCheckILSLoaded - Couldn't read something correctly, error creating importStatus object");
                    $self->addTrace('runCheckILSLoaded',"Error during Instantiating importStatus ID $iID - " .$@);
                };
            }
            {
                # local $@;
                # eval
                # {
                    $import->setLoaded(1);
                    $import->setILSID($ILSID); #. $self->calcSierraCheckDigit($ILSID)); #turns out, we don't need the check digit
                    $import->writeDB();
                    # 1;  # ok
                # } or do
                # {
                    # $self->{log}->addLogLine("Error during updating import for ILS loaded ID $iID - " .$@);
                    # updateImportError($self, $iID, "runCheckILSLoaded - Couldn't manipulate the MARC: importStatus object");
                    # $self->addTrace('runCheckILSLoaded',"Error during updating import for ILS loaded ID $iID - " .$@);
                # };
            }
        }
        undef $import;
        if($#importIDs == -1) # get more
        {
            %imports = undef; # Hopefully garbage collector comes :)
            %importsWithGlue = undef;
            %imports = %{getImportIDsNotLoaded($self, $maxID)}; # only "new" rows
            @importIDs = ( keys %imports );
            %importsWithGlue = %{fileILSLoaded($self, \%imports)};
        }
    }
    removeFilesFromDisk($self);
}

sub fileILSLoaded
{
    my $self = shift;
    my $importRef = shift;
    my %imports = %{$importRef};
    my $z001IDString = "";

    while ( (my $key, my $value) = each(%imports) )
    {
        my @ar = @{$value};
        my $z001 = @ar[0];
        $z001IDString .= "\$ooone\$$z001\$ooone\$,";
    }
    $z001IDString = substr($z001IDString, 0, -1);
    if($z001IDString ne '')
    {
        # this query looks bad because Sierra uses Postgres Views, and to get the best, most efficient results, queries look crappy (nesting, etc)
        if($self->{extPG})
        {
            my $query = "
            select * from
            (
                select svvv.record_num,svvv.marc_tag,svvv.occ_num,svvv.field_content
                from
                sierra_view.varfield_view svvv

                where
                record_id in
                (
                    select vv.record_id from
                    sierra_view.varfield_view vv
                    where
                    vv.marc_tag='001' and
                    vv.field_content in($z001IDString)
                )
            ) as a
            where 
            marc_tag='890' or marc_tag='001'
            order by 1,2,3";
            $self->{log}->addLine($query);
            my @results = @{$self->{extPG}->query($query)};
            my $currentRecord = "";
            my $marc_record = undef;
            while($#results > -1)
            {
                my $r = shift @results;
                my @row = @{$r};
                my $record_num = @row[0];
                my $marcFieldNum = @row[1];
                my $field_content = @row[3];
                if( ($currentRecord != $record_num) )
                {
                    if($marc_record && $marc_record->field('001') && $marc_record->field('001')->data()) #not the first time through, and we've created a marc record to save into the hash.
                    {
                        %imports = %{fileILSLoaded_append($self, \%imports, $marc_record, $currentRecord)};
                    }
                    $marc_record = undef;
                    $marc_record = MARC::Record->new();
                    $currentRecord = $record_num;
                }
                if($marcFieldNum eq '890')
                {
                    # print "'$field_content'\n";
                    my @subs = split(/\|/, $field_content);
                    my @subs_pass = ();
                    foreach(@subs)
                    {
                        if(length(substr($_, 0, 1)) > 0)
                        {
                            my $subfield = substr($_, 0, 1);
                            $_ = substr($_, 1);
                            push (@subs_pass, ($subfield, $_));
                        }
                    }
                    my $field = MARC::Field->new($marcFieldNum, ' ', ' ', @subs_pass);
                    $marc_record->insert_grouped_field($field);
                }
                elsif($marcFieldNum eq '001')
                {
                    my $field = MARC::Field->new($marcFieldNum, $field_content);
                    $marc_record->insert_grouped_field($field);
                }
                %imports = %{fileILSLoaded_append($self, \%imports, $marc_record, $currentRecord)} if( $#results == -1 );
            }
        }
    }
    $self->{log}->addLine(Dumper(\%imports)) if $self->{debug};
    return \%imports;
}

sub fileILSLoaded_append
{
    my $self = shift;
    my $importsRef = shift;
    my $marc_record = shift;
    my $currentRecord = shift;
    my %imports = %{$importsRef};

    my %z001Map = ();
    my %z001TagMap = ();
    my %importIDTagMap = ();
    while ( (my $key, my $value) = each(%imports) )
    {
        my @ar = @{$value};
        my $z001 = @ar[0];
        my $tag = @ar[1];
        my @empty = ();
        $z001Map{$z001} = \@empty if(!$z001Map{$z001});
        @empty = @{$z001Map{$z001}};
        push (@empty, $key);
        $z001Map{$z001} = \@empty;

        my @empty = ();
        $z001TagMap{$z001} = \@empty if(!$z001TagMap{$z001});
        @empty = @{$z001TagMap{$z001}};
        push (@empty, $tag);
        $z001TagMap{$z001} = \@empty;

        # There shouldn't be more than one import ID per tag (they should be unique) but we will allow for it
        my @empty = ();
        $importIDTagMap{$tag} = \@empty if(!$importIDTagMap{$tag});
        @empty = @{$importIDTagMap{$tag}};
        push (@empty, $key);
        $importIDTagMap{$tag} = \@empty;
    }

    my @ids = @{$z001Map{$marc_record->field('001')->data()}} if $z001Map{$marc_record->field('001')->data()};
    my @expectedTags = @{$z001TagMap{$marc_record->field('001')->data()}} if $z001TagMap{$marc_record->field('001')->data()};
    my @e890a = $marc_record->field('890');
    foreach(@e890a)
    {
        my @subs = $_->subfield('a');
        foreach(@subs)
        {
            my $tSub = $_;
            foreach(@expectedTags)
            {
                print "'$tSub'\n'$_'\n";
                if( ($tSub eq $_) && $importIDTagMap{$_} )
                {
                    foreach(@{$importIDTagMap{$_}})
                    {
                        if($imports{$_})
                        {
                            my @ar = @{$imports{$_}};
                            push (@ar, $currentRecord);
                            $imports{$_} = \@ar;
                        }
                    }
                }
            }
        }
    }
    return \%imports;
}

sub removeFilesFromDisk
{
    my $self = shift;
    if($self->{folders})
    {
        while ( (my $key, my $value) = each(%{$self->{folders}}) )
        {
            my @files = ();
            @files = @{$self->dirtrav(\@files, $value)};
            foreach(@files)
            {
                my $done = seeIfFileIsCompletelyLoaded($self, $_);
                print "Removing '$_'\n" if ($done && $self->{debug});
                unlink $_ if $done; #delete the file from disk when all rows in the database claim to be loaded
            }
        }
    }
}

sub seeIfFileIsCompletelyLoaded
{
    my $self = shift;
    my $filename = shift;
    my $ret = 1;
    my $query = "
    SELECT true
    FROM
    ".$self->{prefix} ."_import_status ais
    JOIN ".$self->{prefix} ."_output_file_track oft on (oft.id=ais.out_file)
    WHERE
    ais.loaded = 0 AND
    oft.filename = ?
    GROUP BY 1";
    my @vars = ($filename);
    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->getDataFromDB($query, \@vars)};
    $ret = 0 if $#results > -1; #if any rows are returned, then there is at least one record that has not been loaded
    return $ret;
}

sub setupSourceOutputFiles
{
    my $self = shift;
    my $tag = shift;
    
    if($self->{folders})
    {
        my $mobUtil = new Mobiusutil();
        while ( (my $key, my $value) = each(%{$self->{folders}}) )
        {
            $self->{'outfile_'. $key} = $mobUtil->chooseNewFileName($value, $tag . "_$key", "mrc");
        }
        undef $mobUtil;
    }
    $self->{log}->addLine(Dumper($self)) if $self->{debug};
}

sub setupExternalPGConnection
{
    my $self = shift;
    my @needed = qw(dbhost dbdb dbport dbuser dbpass);
    my $missing = 0;
    print "Starting externalPGConnection\n";
    foreach(@needed)
    {
        $missing = 1 if !($self->{$_});
    }
    if(!$missing)
    {
        print "Starting object creation\n";
        eval{$self->{extPG} = new DBhandler($self->{"dbdb"},$self->{"dbhost"},$self->{"dbuser"},$self->{"dbpass"},$self->{"dbport"});};
        if ($@)
        {
            $self->setError("Could not establish a connection to external DB host: '" . $self->{"dbhost"} . "'");
            undef $self->{extPG};
        }

    }
    print "done externalPGConnection\n";
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
    SELECT ais.id, ais.tag, aft.filename, aft.source, ais.z001 FROM
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

sub getImportIDsNotLoaded
{
    my $self = shift;
    my $minID = shift || 0;
    my $limit = shift || 500;
    my %ret = ();
    my $query = "
    SELECT
    ais.id, ais.z001, concat(ais.tag,ais.id), aoft.filename, ais.itype
    FROM
    ".$self->{prefix} ."_import_status ais
    LEFT JOIN ".$self->{prefix} ."_output_file_track aoft ON (aoft.id=ais.out_file)
    where
    ais.job = ?
    and loaded = 0
    and ais.id > ?
    ORDER BY 1
    LIMIT $limit";
    my @vars = ($self->{job}, $minID);
    my @results = @{$self->getDataFromDB($query, \@vars)};
    foreach(@results)
    {
        my @row = @{$_};
        my $id = shift @row;
        $ret{$id} = \@row;
    }
    return \%ret;
}

sub startJob
{
    my $self = shift;
    my $query =
    "UPDATE
    ".$self->{prefix}.
    "_job
    set
    start_time = NOW()
    where
    id = ?";
    my @vals = ($self->{job});
    $self->doUpdateQuery($query, undef, \@vals);
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
    $self->{extPG}->breakdown() if $self->{extPG};
    ## call destructor
}


1;