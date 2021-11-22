#!/usr/bin/perl

package commonTongue;

use lib qw(./);
use Data::Dumper;

sub new
{
    my ($class, @args) = @_;
    my ($self, $args) = _init($class, \@args);
    @args = @{$args};
    bless $self, $class;
    return ($self, \@args);
}

sub _init
{
    my $self = shift;
    my $args = shift;
    my @args = @{$args};
    my @trace = ();
    $self =
    {
        log => shift @args,
        dbHandler => shift @args,
        prefix => shift @args,
        debug => shift @args,
        error => undef,
        trace => \@trace
    };
    return ($self, \@args);
}

sub parseJSON
{
    my $self = shift;
    my $json = shift;
    if( ref $json eq 'HASH' )
    {
        while ( (my $key, my $value) = each( %{$json} ) )
        {
            if(ref $value eq 'HASH')
            {
                my %h = %{$value};
                $self->{$key} = \%h;
            }
            elsif (ref $value eq 'ARRAY')
            {
                my @a = @{$value};
                $self->{$key} = \@a;
            }
            else
            {
                $self->{$key} = $value;
            }
        }
    }
    return $self;
}

sub escapeData
{
    my $self = shift;
    my $d = shift;
    $d =~ s/'/\\'/g;   # ' => \'
    $d =~ s/\\/\\\\/g; # \ => \\
    return $d;
}

sub doUpdateQuery
{
    my $self = shift;
    my $query = shift;
    my $stdout = shift;
    my $dbvars = shift;

    $self->{log}->addLine($query);
    $self->{log}->addLine(Dumper($dbvars)) if $self->{debug};
    print "$stdout\n" if $stdout;

    return $self->{dbHandler}->updateWithParameters($query, $dbvars);
}

sub getDataFromDB
{
    my $self = shift;
    my $query = shift;
    $self->{log}->addLine($query) if $self->{debug};
    return $self->{dbHandler}->query($query);
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

sub trim
{
    my $self = shift;
	my $string = shift;
	$string =~ s/^[\t\s]+//;
	$string =~ s/[\t\s]+$//;
	return $string;
}

sub dirtrav
{
    my $self = shift;
    my @files = @{@_[0]};
    my $pwd = @_[1];
    opendir(DIR,"$pwd") or die "Cannot open $pwd\n";
    my @thisdir = readdir(DIR);
    closedir(DIR);
    foreach my $file (@thisdir) 
    {
        if(($file ne ".") and ($file ne ".."))
        {
            if (-d "$pwd/$file")
            {
                push(@files, "$pwd/$file");
                @files = @{dirtrav(\@files,"$pwd/$file")};
            }
            elsif (-f "$pwd/$file")
            {            
                push(@files, "$pwd/$file");            
            }
        }
    }
    return \@files;
}

sub convertMARCtoXML
{
    my $self = shift;
    my $marc = shift;
    my $thisXML =  $marc->as_xml(); #decode_utf8();

    $thisXML =~ s/\n//sog;
    $thisXML =~ s/^<\?xml.+\?\s*>//go;
    $thisXML =~ s/>\s+</></go;
    $thisXML =~ s/\p{Cc}//go;
    $thisXML = entityize($self, $thisXML);
    $thisXML =~ s/[\x00-\x1f]//go;
    $thisXML =~ s/^\s+//;
    $thisXML =~ s/\s+$//;
    $thisXML =~ s/<record><leader>/<leader>/;
    $thisXML =~ s/<collection/<record/;
    $thisXML =~ s/<\/record><\/collection>/<\/record>/;

    return $thisXML;
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