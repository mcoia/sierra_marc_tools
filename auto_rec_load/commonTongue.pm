#!/usr/bin/perl

package commonTongue;

use lib qw(./);
use Data::Dumper;
use Unicode::Normalize;

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
    addTrace($self, "parseJSON", "Parsing JSON init");
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
    addTrace($self, "parseJSON", "Parsing JSON finished") if $self->{debug};
    return $self;
}

sub calcSierraCheckDigit
{
    my $self = shift;
    my $seed = shift;
    print "calculating checkdigit\n";
    $seed = reverse( $seed );
    my @chars = split("", $seed);
    my $checkDigit = 0;
    for my $i (0..$#chars)
    {
        $checkDigit += @chars[$i] * ($i+2);
    }
    $checkDigit = $checkDigit % 11;
    if( $checkDigit > 9 )
    {
        $checkDigit = 'x';
    }
    print "calculating checkdigit: $checkDigit\n";
    return $checkDigit;
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
    my $vars = shift;
    $self->{log}->addLine($query) if $self->{debug};
    $self->{log}->addLine(Dumper($vars)) if ($vars && $self->{debug});
    return $self->{dbHandler}->query($query, $vars);
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

    my $thisXML = '';
    local $@;
    eval
    {
        # Turn on dying from warnings
        # MARC::Charset can throw warnings here, and we don't want to continue if we get some
        local $SIG{__WARN__} = sub { die @_; };
        $thisXML = $marc->as_xml();
        1;
    } or do
    {
        $marc->encoding('UTF-8');
        $thisXML = $marc->as_xml();
    };

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

sub entityize
{ 
    my($self, $string, $form) = @_;
    $form ||= "";

    if ($form eq 'D')
    {
        $string = NFD($string);
    }
    else
    {
        $string = NFC($string);
    }

    # Convert raw ampersands to entities
    $string =~ s/&(?!\S+;)/&amp;/gso;

    # Convert Unicode characters to entities
    $string =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

    return $string;
}

sub mergeMARC856
{
    my $self = shift;
    my $marc = shift;
    my $marc2 = shift;
    my @eight56s = $marc->field("856");
    my @eight56s_2 = $marc2->field("856");
    my @eights;
    my $original856 = $#eight56s + 1;
    @eight56s = (@eight56s,@eight56s_2);

    my %urls;
    foreach(@eight56s)
    {
        my $thisField = $_;
        my $ind2 = $thisField->indicator(2);
        # Just read the first $u and $z
        my $u = $thisField->subfield("u");
        my $z = $thisField->subfield("z");
        my $s7 = $thisField->subfield("7");

        if($u) #needs to be defined because its the key
        {
            if(!$urls{$u})
            {
                $urls{$u} = $thisField;
            }
            else
            {
                my @nines = $thisField->subfield("9");
                my $otherField = $urls{$u};
                my @otherNines = $otherField->subfield("9");
                my $otherZ = $otherField->subfield("z");
                my $other7 = $otherField->subfield("7");
                if(!$otherZ)
                {
                    if($z)
                    {
                        $otherField->add_subfields('z'=>$z);
                    }
                }
                if(!$other7)
                {
                    if($s7)
                    {
                        $otherField->add_subfields('7'=>$s7);
                    }
                }
                foreach(@nines)
                {
                    my $looking = $_;
                    my $found = 0;
                    foreach(@otherNines)
                    {
                        if($looking eq $_)
                        {
                            $found=1;
                        }
                    }
                    if($found==0 && $ind2 eq '0')
                    {
                        $otherField->add_subfields('9' => $looking);
                    }
                }
                $urls{$u} = $otherField;
            }
        }

    }

    my $finalCount = scalar keys %urls;
    if($original856 != $finalCount)
    {
        $self->{log}->addLine("There was $original856 and now there are $finalCount");
    }

    my @remove = $marc->field('856');
    #$self->{log}->addLine("Removing ".$#remove." 856 records");
    $marc->delete_fields(@remove);


    while ((my $internal, my $mvalue ) = each(%urls))
    {
        $marc->insert_grouped_field( $mvalue );
    }
    return $marc;
}

sub mergeMARCFields
{
    my $self = shift;
    my $marc = shift;
    my $marc2 = shift;
    my $fieldNumber = shift;
    my $subfieldKey = shift;
    my $keyRemoval = shift;
    $keyRemoval = lc $keyRemoval;
    
    my @fields = $marc->field($fieldNumber);
    my @fields_2 = $marc2->field($fieldNumber);
    my %subfieldDedupe = ();
    @fields = (@fields, @fields_2);

    foreach(@fields)
    {
        my $thisField = $_;
        my @subs = $thisField->subfield($subfieldKey);
        foreach(@subs)
        {
            my $thisSubfield = $_;
            $thisSubfield = lc $thisSubfield;
            if( !( ($keyRemoval) && ($thisSubfield =~ m/$keyRemoval/)) )
            {
                $subfieldDedupe{$_} = 1;
            }
        }
    }

    my @remove = $marc->field($fieldNumber);
    $marc->delete_fields(@remove) if $#remove > -1;

    my $field = MARC::Field->new($fieldNumber+0, ' ', ' ', 'b' => 'temp');
    $field->delete_subfield(code => 'b');
    while ((my $internal, my $mvalue ) = each(%subfieldDedupe))
    {
        $field->add_subfields($subfieldKey, $internal)
    }

    if( $field->subfield($subfieldKey) )
    {   
        $marc->insert_grouped_field( $field );
    }
    $self->{log}->addLine($marc->as_formatted());
    return $marc;
}

sub countMARC856Fields
{
    my $self = shift;
    my $marc = shift;
    my @eights = $marc->field("856");
    my $count = 0;
    foreach(@eights)
    {
        my $thisField = $_;
        my $ind2 = $thisField->indicator(2);
        $count++ if ($ind2 ne'2') # Considered "real" when the second indicator is not 2
    }
    return $count;
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