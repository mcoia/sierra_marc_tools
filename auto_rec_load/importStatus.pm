#!/usr/bin/perl

package importStatus;

use lib qw(./);
use Data::Dumper;
use marcEditor;
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
    $self->{importStatusID} = shift;
 
    if($self->{importStatusID} && $self->{dbHandler} && $self->{prefix} && $self->{log})
    {
        $self = fillVars($self);
        if($self->getError())
        {
            $self->addTrace("Error loading import object");
        }
    }
    else
    {
        $self->setError("Couldn't initialize importStatus object");
    }

    return $self;
}

sub fillVars
{
    my $self = shift;
    my $query = "select 
    ais.status,
    ais.record_raw,
    ais.record_tweaked,
    ais.tag,
    ais.z001,
    ais.loaded,
    ais.ils_id,
    ais.itype,
    ais.job,
    aus.id,
    ac.id,
    aus.name,
    ac.name
    from
    ".$self->{prefix}.
    "_import_status ais
    join 
    ".$self->{prefix}.
    "_file_track aft on (aft.id=ais.file)
    join 
    ".$self->{prefix}.
    "_client ac on (ac.id=aft.client)
    join 
    ".$self->{prefix}.
    "_source aus on (aus.id=aft.source)
    where
    ais.id = ".$self->{importStatusID};

    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $self->{log}->addLine("Import status vals: ".Dumper(\@row)) if $self->{debug};
        $self->{status} = @row[0];
        $self->{record_raw} = @row[1];
        $self->{record_tweaked} = @row[2];
        $self->{tag} = @row[3] . $self->{importStatusID}; # The records are unique and get tagged with the seed plus the ID number
        $self->{z001} = @row[4];
        $self->{loaded} = @row[5];
        $self->{ils_id} = @row[6];
        $self->{itype} = @row[7];
        $self->{job} = @row[8];
        $self->{source} = @row[9];
        $self->{client} = @row[10];
        $self->{source_name} = @row[11];
        $self->{client_name} = @row[12];
        $self->{marc_editor_name} = $self->{source_name} . '_' . $self->{client_name};
    }
    $self->{error} = "Couldn't read import status data ID: ". $self->{importStatusID} if($#results == -1);
    die if($#results == -1);

    $query = "select 
    aoft.id,
    aoft.filename
    from
    ".$self->{prefix}.
    "_output_file_track aoft
    where
    aoft.import_id = ".$self->{importStatusID};

    $self->{log}->addLine($query) if $self->{debug};
    @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $self->{output_file_id} = @row[0];
        $self->{output_filename_real} = @row[1]);
    }
    return $self;
}

sub convertMARC
{
    my $self = shift;
    my $type = shift;
    my $beforeFile = shift;
    my $afterFile = shift;
    my $manip = new marcEditor($self->{log}, $self->{debug}, $type);
    my $marc = $self->{record_raw};
    $marc =~ s/(<leader>.........)./${1}a/;
    my $marcobject = MARC::Record->new_from_xml($marc);
    $beforeFile->addLine($marcobject->as_formatted()) if($beforeFile);
    $self->{record_tweaked} = $manip->manipulateMARC($self->{marc_editor_name}, $marcobject, $self->{tag});
    $afterFile->addLine($self->{record_tweaked}->as_formatted()) if($afterFile);
    $self->{record_tweaked} = $self->convertMARCtoXML($self->{record_tweaked});
    undef $marc;
    undef $marcobject;
    return $self->{record_tweaked};
}

sub getTag
{
    my $self = shift;
    return $self->{tag};
}

sub getSourceID
{
    my $self = shift;
    return $self->{source};
}

sub writeDB
{
    my $self = shift;
    my $query = "UPDATE
    ".$self->{prefix}.
    "_import_status ais
    SET
    status = ?,
    record_raw = ?,
    record_tweaked = ?,
    z001 = ?,
    loaded = ?,
    ils_id = ?,
    itype = ?
    WHERE
    id = ?";
    my @vars =
    (
    $self->{status},
    $self->{record_raw},
    $self->{record_tweaked},
    $self->{z001},
    $self->{loaded},
    $self->{ils_id},
    $self->{itype},
    $self->{importStatusID}
    );
    $self->doUpdateQuery($query, undef, \@vars);

    # and update/insert row into output file track

    # case where the output filename was changed during load/save
    if($self->{output_file_id} && $self->{output_filename_real} ne $self->{output_filename})
    {
        $query = "UPDATE
        ".$self->{prefix}.
        "_output_file_track aoft
        SET
        filename = ?
        WHERE
        id = ?";
        my @vars =
        (
        $self->{output_filename},
        $self->{importStatusID}
        );
        $self->doUpdateQuery($query, undef, \@vars);
        $self->{output_filename_real} = $self->{output_filename};
    }
    elsif(!$self->{output_file_id} && $self->{output_filename}) # newly written output
    {
        $query = "INSERT INTO
        ".$self->{prefix}.
        "_output_file_track aoft
        (filename, import_id)
        VALUES(?, ?)";
        my @vars =
        (
        $self->{output_filename},
        $self->{importStatusID}
        );
        $self->doUpdateQuery($query, undef, \@vars);
        $self->{output_filename_real} = $self->{output_filename};
    }
}

sub getTweakedRecord
{
    my $self = shift;
    return $self->{record_tweaked};
}

sub getSource
{
    my $self = shift;
    return $self->{source};
}

sub getItype
{
    my $self = shift;
    return $self->{itype};
}

sub setStatus
{
    my $self = shift;
    $self->{status} = shift;
}

sub setILSID
{
    my $self = shift;
    $self->{ils_id} = shift;
}

sub setLoaded
{
    my $self = shift;
    $self->{loaded} = shift;
}

sub setItype
{
    my $self = shift;
    $self->{itype} = shift;
}

sub setOutputFilename
{
    my $self = shift;
    $self->{output_filename} = shift;
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;