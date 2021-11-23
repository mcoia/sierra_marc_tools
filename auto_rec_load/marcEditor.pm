#!/usr/bin/perl

package marcEditor;

use lib qw(./);

use MARC::Record;
use MARC::Field;

our %map = 
(
    "ebook_central_MWSU" => "ebook_central_MWSU"
);

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
        debug => shift,
        type => shift || 'adds'
    };
    return $self;
}

sub manipulateMARC
{
    my $self = shift;
    my $key = shift;
    my $marc = shift;
    my $tag = shift;
print "starting manip\n";
    my $ret = $marc;
    if ( $map{$key} )
    {
        my $ev = '$ret = ' . $map{$key} .'($self, $marc);';
        $self->{log}->addLine("Running " . $map{$key} ) if($self->{debug});
        eval $ev;
    }
    return $ret;
}

sub ebook_central_MWSU
{
    my $self = shift;
    my $marc = shift;

print "Manipulating ebook_central_MWSU\n";
    # Add 506
    my $field506 = MARC::Field->new( '506', undef, undef, 'c' => 'Access restricted to subscribers');
    $marc->insert_grouped_field($field506);

    if($self->{type} eq 'adds')
    {
        # Add 949
        # \1$aMW E-Book$g1$h020$i0$lm2wii$o-$r-$s-$t014$u-$z099$xProQuest Reference E-Book
        my $field949 = MARC::Field->new( '949', undef, 1,
        'a' => 'MW E-Book',
        'h' => '020',
        'o' => '-',
        'r' => '-',
        's' => '-',
        't' => '014',
        'u' => '-',
        'z' => '099',
        'x' => 'ProQuest Reference E-Book',
        );
        $marc->insert_grouped_field($field949);
    }

    $marc = updateSubfields($marc, '856', 'u', 'https://login.ezproxy.missouriwestern.edu/login?url=', 1); # prepend
    $marc = updateSubfields($marc, '856', 'z', 'MWSU E Book');
    $marc = updateSubfields($marc, '856', '5', '6mwsu');

    # Inject a 245$h after all a and p subfields
    my @prefields = ('a','p');
    $marc = createSubfieldBetween($marc, '245', 'h', '[electronic resource (video)]', \@prefields, undef, ' / ');
    return $marc;
}

sub createSubfieldBetween
{
    my $marc = shift;
    my $field = shift;
    my $subfield = shift;
    my $subfieldValue = shift;
    my $presubfieldsRef = shift;
    my $aftersubfieldsRef = shift;
    my $optionalAppend = shift;
    my @preSubfieldCodes;
    my @afterSubfieldCodes;


    if($presubfieldsRef)
    {
       @preSubfieldCodes = @{presubfieldsRef};
    }
    if($aftersubfieldsRef)
    {
       @afterSubfieldCodes = @{aftersubfieldsRef};
    }

    my @fields = $marc->field($field);
    foreach(@fields)
    {
        my $thisfield = $_;
        $thisfield->delete_subfield(code => $subfield); # remove any pre-existing destination subfield
        my @all = $thisfield->subfields();
        $thisfield->delete_subfield(match => qr/./); #wipe everything out
        my $didntPrepend = 0;
        for my $i (0..$#all) #find all of the subfields that we should start with
        {
            if(@all[$i])
            {
                my @combo = @{$_};
                my $found = 0;
                foreach(@preSubfieldCodes)
                {
                    if( ($_ eq @combo[0]) && !$found)
                    {
                        $thisfield->add_subfields(@combo[0] => @combo[1]);
                        delete @all[$i];
                        $found = 1;
                    }
                }
                $didntPrepend = 1 if(!$found);
            }
        }
        $subfieldValue .= $optionalAppend if($optionalAppend && $didntPrepend);

        $thisfield->add_subfields($subfield => $subfieldValue);
        for my $i (0..$#all) #Append the rest of the old subfields back onto th end
        {
            if(@all[$i])
            {
                my @combo = @{$_};
                $thisfield->add_subfields(@combo[0] => @combo[1]);
            }
        }
    }
    return $marc;
}

sub tagMARC
{
    my $self = shift;
    my $marc = shift;
    my $tag = shift;
    
    return $marc;
}

sub KC_Towers_FOD_Avila
{
    my $marc = @_[0];
    my $z001 = $marc->field('001');
    $z001->update("fod".$z001->data());
    my $field949 = MARC::Field->new( '949',' ','1', h => '100', i=>0, l=>'avelr', r => 'z', s => 'i', t => '014', u => '-' );
    $marc->insert_grouped_field( $field949 );
    $marc = prepost856z($marc,"<a href=","><img src=\"/screens/avila_856_icon.jpg \" alt=\"Avila Online Access\"></a>");
    $marc = remove856u($marc);
    #print ("U removed, z takes argument of u as a clickable link"); 
    return $marc;

}

sub updateSubfields
{
    my $marc = shift;
    my $field = shift;
    my $subfield = shift;
    my $value = shift;
    my $prepend = shift || 0;
    my $append = shift || 0;
    my @fields = $marc->field($field);
    foreach(@fields)
    {
        my $thisfield = $_;
        my @all = $thisfield->subfield($subfield);
        for my $i (0..$#all)
        {
            @all[$i] = appendPrepend(@all[$i], $value, $prepend, $append);
        }
        if($#all > -1) # wipe em and make new ones
        {
            $thisfield->delete_subfield(code => $subfield);
            foreach(@all)
            {
                $thisfield->add_subfields($subfield => $_);
            }
        }
        else
        {
            $thisfield->update($subfield => $value );
        }
    }
    return $marc;
}

sub appendPrepend
{
    my $og = shift;
    my $add = shift;
    my $prepend = shift || 0;
    my $append = shift || 0;
    $og = $add.$og if $prepend;
    $og .= $add if $append;
    return $og;
}

sub removeSubfield
{
    my $marc = shift;
    my $field = shift;
    my $subfield = shift;
    my @fields = $marc->field($field);
    foreach(@fields)
    {
        $_->delete_subfield(code => $subfield);
    }
    return $marc;
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;