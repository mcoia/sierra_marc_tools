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
        importStatusID => shift
    };
    return $self;
}



sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;