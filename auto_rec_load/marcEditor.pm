#!/usr/bin/perl

package marcEditor;

use lib qw(./);


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
        log => shift
    };
    return $self;
}

sub manipulateMARC
{
    my $self = shift;
    my $key = shift;
    my $marc = shift;
    my $ret = $marc;
    if ( $map{$key} )
    {
        my $ev = '$ret = ' . $map{$key} .'($self, $marc);';
        print 
        eval $ev;
    }
    return $ret;
}

sub ebook_central_MWSU
{
    my $self = shift;
    my $marc = shift;

    # Add 506
    my $field506 = new MARC
    
    
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


sub prefix856u
{
    my $marc = @_[0];
    my $prefix = @_[1];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;
        $thisfield->update('u' => $prefix.$thisfield->subfield('u') );
    }
    return $marc;
}

sub postfix856u
{
    my $marc = @_[0];
    my $postfix = @_[1];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;
        $thisfield->update('u' => $thisfield->subfield('u').$postfix );
    }
    return $marc;
}

sub indicator856u
{
    my $marc = @_[0];
    my $indicator2 = @_[1];
    #print "indicator:".$ind2;
    my $f856s = $marc->field('856');

        $f856s->update(ind2 => $indicator2 );

    return $marc;
}

sub prepost856z
{
    my $marc = @_[0];
    my $prefix = @_[1];
    my $postfix = @_[2];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;

        $thisfield->update('z' => $prefix.$marc->field('856')->subfield('u').$postfix );
    }

    return $marc;
}

sub change856z
{
    my $marc = @_[0];
    my $subz = @_[1];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;
        $thisfield->update('z' => $subz );
    }
    return $marc;
}

sub remove856u
{
    my $marc = @_[0];
    #my $subz = @_[1];
    my @e856s = $marc->field('856');
    foreach(@e856s)
    {
        my $thisfield = $_;
        $thisfield->delete_subfield(code => 'u');
    }
    return $marc;
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
}


1;