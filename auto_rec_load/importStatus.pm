#!/usr/bin/perl

package importStatus;

use lib qw(./);

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
    $self =
    {
        log => shift,
        dbHandler => shift,
        log => shift,
        debug => shift,
        importStatusID => shift,
        prefix => shift,
        status => undef,
        record_raw => undef,
        record_tweaked => undef,
        tag => undef,
        z001 => undef,
        loaded => undef,
        ils_id => undef,
        job => undef,
        source_name => undef,
        client_name => undef,
        error => undef
    };

    if($self->{importStatusID} && $self->{dbHandler} &&  $self->{log})
    {
        $self = fillVars($self);
    }
    else
    {
        setError($self, "Couldn't initialize");
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
    stat.id = ".$self->{importStatusID};

    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->{dbHandler}->query($query)};
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
        $self->{source_name} = @row[8];
        $self->{client_name} = @row[9];
    }

    $self->{error} = "Couldn't read import status data ID: ". $self->{importStatusID} if($#results == -1);

    return $self;
}

sub processMARC
{
    my $self = shift;
    
}

sub writeDB
{
    
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


sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;