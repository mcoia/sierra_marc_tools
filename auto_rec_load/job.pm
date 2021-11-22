#!/usr/bin/perl

package job;

use lib qw(./);
use Data::Dumper;
use JSON;
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
    my @importIDs = @{getImportIDs($self)};
    my $records = 0;
    updateJobStatus($self, 'Job Started');
    markImportsAsWorking($self, \@importIDs);
    my $currentSource = 0;
    while($#importIDs > -1)
    {
        $records++;
        my $iID = shift @importIDs;
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
            };
        }
        {
            local $@;
            eval
            {
                updateJobStatus($self, 'Processing import $iID');
                my $marc = $import->convertMARC();
                $import->setConvertedMARC($marc);
                1;  # ok
            } or do
            {
                updateImportError($self, $iID, "Couldn't read something correctly, error creating importStatus object");
            };
        }
        undef $import;

        if($#importIDs) # get more
        {
            @importIDs = @{getImportIDs($self)};
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
    my $ids = shift;
    my $statusString = shift;
    my @ids = @{$ids};
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
    my $limit = shift || 500;
    my @ret = ();
    my $query = "
    SELECT id FROM
    ".$self->{prefix} ."_import_status
    WHERE
    job = " .$self->{job} . "
    AND status = 'new'
    LIMIT $limit";
    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->getDataFromDB($query)};
    foreach(@results)
    {
        my @row = @{$_};
        push (@ret, @row[0]);
    }
    return \@ret;
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
    current_action ?
    where
    id = ?";
    my @vals = ($status, $action, $self->{job});
    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->{dbHandler}->query($query)};
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