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
print "Starting importStatus\n";

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
        $self->{tag} = @row[3];
        $self->{z001} = @row[4];
        $self->{loaded} = @row[5];
        $self->{ils_id} = @row[6];
        $self->{job} = @row[7];
        $self->{source} = @row[8];
        $self->{client} = @row[9];
        $self->{source_name} = @row[10];
        $self->{client_name} = @row[11];
        $self->{marc_editor_name} = $self->{source_name} . '_' . $self->{client_name};
    }

    $self->{error} = "Couldn't read import status data ID: ". $self->{importStatusID} if($#results == -1);
    die if($#results == -1);

    return $self;
}

sub convertMARC
{
    my $self = shift;
    my $type = shift;
    my $beforeFile = shift;
    my $afterFile = shift;
    my $manip = new marcEditor($log, $debug, $type);
    my $marc = $self->{record_raw};
    $marc =~ s/(<leader>.........)./${1}a/;
    my $marcobject = MARC::Record->new_from_xml($marc);
    $beforeFile->addLine($marcobject->as_formatted()) if($beforeFile);
print "Wrote to before\n";
exit;
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
    ils_id = ?
    WHERE
    id = ?";
    my @vars = ($self->{status},$self->{record_raw},$self->{record_tweaked},$self->{z001},$self->{loaded},$self->{ils_id},$self->{importStatusID});
    $self->doUpdateQuery($query, undef, \@vars);
}

sub getSource
{
    my $self = shift;
    return $self->{source};
}

sub setStatus
{
    my $self = shift;
    my $self->{status} = shift;
}

sub setILSID
{
    my $self = shift;
    my $self->{ils_id} = shift;
}

sub setLoaded
{
    my $self = shift;
    my $self->{loaded} = shift;
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;