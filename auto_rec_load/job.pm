#!/usr/bin/perl

package job;

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
        job => shift,
        prefix => shift,
        status => undef,
        error => undef
    };
 
    if($self->{job} && $self->{dbHandler} && $self->{prefix} && $self->{log})
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
    my ($self) = @_[0];

    my $query = "select 
    id from
    ".$self->{prefix}.
    "_job
    where
    id = ".$self->{job};

    my @results = @{$self->{dbHandler}->query($query)};
    foreach(@results)
    {

    }

    $self->{error} = 1 if($#results == -1);

    return $self;
}

sub runJob
{
    my $self = shift;
    
}


sub updateJobStatus
{
    my $self = shift;
    my $status = shift;
    my $action = shift;
    my $query =
    "UPDATE
    ".$self->{prefix}.
    "_job
    set
    status = ?,
    current_action ?,
    current_action_num = current_action_num + 1
    where
    id = ?";
    my @vals = ($status, $action, $self->{job});
    $self->{log}->addLine($query) if $self->{debug};
    my @results = @{$self->{dbHandler}->query($query)};
    
    
}

sub finishJob
{
    my $self = shift;
    my $status = shift;
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