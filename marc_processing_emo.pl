#!/usr/bin/perl


use lib qw(../); 
use Loghandler;
use Mobiusutil;
use Data::Dumper;
use MARC::Record;
use MARC::File;
use File::Path qw(make_path remove_tree);
use File::Copy;
use Encode;
 
my $dirRoot = @ARGV[0];
if(!$dirRoot)
{
    print "Please specify a directory root \n";
    exit;
}

#our $pidfile = "/tmp/marc_processing.pl.pid";

##	if (-e $pidfile)
##	{
##		#Check the processes and see if there is a copy running:
##		my $thisScriptName = $0;
##		my $numberOfNonMeProcesses = scalar grep /$thisScriptName/, (split /\n/, `ps -aef`);
##		# The number of processes running in the grep statement will include this process,
##		# if there is another one the count will be greater than 1
##		if($numberOfNonMeProcesses > 1)
##		{
##			print "Sorry, it looks like I am already running.\nIf you know that I am not, please delete $pidfile\n";
##			exit;
##		}
##		else
##		{
##			#I'm really not running
##			unlink $pidFile;
##		}
##	}

##my $writePid = new Loghandler($pidfile);
##$writePid->addLine("running");
##undef $writePid;

while(1)
{


    my @files;
    @files = @{dirtrav(\@files, $dirRoot)};
    my %functionMaps = (
    'EWL YBP DDA' => 'EWL_YBP_DDA',
	'KC-Towers FOD Avila' => 'KC_Towers_FOD_Avila',
	'KC-Towers FOD MBTS' => 'KC_Towers_FOD_MBTS',
	'KC-Towers FOD MWSU' => 'KC_Towers_FOD_MWSU',
	'KC-Towers FOD NCMC' => 'KC_Towers_FOD_NCMC',
	'KC-Towers FOD NWMSU' => 'KC_Towers_FOD_NWMSU',
	'EMO/Deletes/IR/' => 'EMO_Deletes_IR',
	'EMO/Deletes/Bridges/' => 'EMO_Deletes_Bridges',
	'EMO/Deletes/Everyone/' => 'EMO_Deletes_Everyone',	
	'EMO/New_Update/Archway/' => 'EMO_Updates_Archway',
	'EMO/New_Update/Swan/' => 'EMO_Updates_SWAN',
	'EMO/New_Update/Avalon/' => 'EMO_Updates_Avalon',
	'EMO/New_Update/Bridges/' => 'EMO_Updates_Bridges',
	'EMO/New_Update/Arthur/' => 'EMO_Updates_Arthur',
	'EMO/New_Update/InnReach/' => 'EMO_Updates_IR',
	'EMO/New_Update/ChristianCounty/' => 'EMO_Updates_Christian_County',
	'EMO/New_Update/KC-Towers/' => 'EMO_Updates_KC_Towers',
	'EMO/New_Update/Galahad/' => 'EMO_Updates_Galahad',
			
    );

    foreach(@files)
    {
        my $file = $_;
        my $path;
        my $finalpath;
        our $baseFileName;
        my $fExtension;
        my $originalFileName;
        my $processedFileName;
        my @sp = split('/',$file);
       
       
        $path=substr($file,0,( (length(@sp[$#sp]))*-1) );
    #print "lastE = ".@sp[$#sp]."\n";
        my @fsp = split('\.',@sp[$#sp]);
        $fExtension = pop @fsp;
        $baseFileName = join('.', @fsp);
		$baseFileName= Encode::encode("CP1252", $baseFileName);
        $finalpath = $path."/marc_done_processing";
        
        if( !($path =~ m/marc_done_processing/) && ($fExtension =~ 'mrc'))
        {
            # Make sure we have a function for this directory
            my $functionCall;
            while (my ($key, $value) = each %functionMaps)
            {
                $functionCall = $value if($path =~ m/$key/);
            }
            if($functionCall)
            {
                $functionCall = "\$finalmarc = $functionCall(\$marc);";
                # ensure that our final directory exists
                ensureFinalFolderExists($finalpath);
                $originalFileName = $baseFileName."_org.".$fExtension;
                $processingFileName = $baseFileName.".processing";
                $processedFileName = $baseFileName."_processed.".$fExtension;
print "path = $path  Base = $baseFileName  Orgname = $originalFileName  ProcessingFN = $processingFileName  Processed = $processedFileName\n";
                checkFileReady($file);
                # move($file,$path.$processingFileName);
                moveFile($file,$path.$processingFileName);
                my $marcfile = MARC::File::USMARC->in($path.$processingFileName);
                my $writeOut = '';
                while ( my $marc = $marcfile->next() )
                {
                    my $finalmarc;
                    eval ($functionCall);
                    $writeOut.=$finalmarc->as_usmarc();
                }
                
                my $doneFH = new Loghandler($finalpath.'/'.$processedFileName);
                $doneFH->appendLineRaw($writeOut);
                undef $doneFH;
                moveFile($path.$processingFileName,$finalpath.'/'.$originalFileName);
            }
        }
    }    
    sleep 5;
}

sub moveFile
{
    my $file = @_[0];
    my $destination = @_[1];

# $file =~s/\s/\\ /g;
# $file =~s/&/_/g;
# $destination =~s/\s/\\ /g;
# $destination =~s/&/_/g;

#    system("mv {oldfilename} {newfilename}");
#print "Moving file from $file to $destination\n";

# special characters that Windows inserts in the file name (sometimes).
# The baseFileName just needs to be encoded CP1252. Use Encode Module
    
    my $fhandle = new Loghandler($file);
    
    if( $fhandle->copyFile($destination) )
    {
        if(! (unlink($file)) )
        {
            print "Unable to delete $file";
            exit;
        }
    }
    undef $fhandle;
}

sub EWL_YBP_DDA
{
    my $marc = @_[0];
    my $z001 = $marc->field('001');
    $z001->update("ewlebc".$z001->data());
    my $two45 = $marc->field('245');
    $two45->update( 'h' => "[electronic resource]" );
    my $field655 = MARC::Field->new( '655',' ','0', a => 'Electronic books' );
    $marc->insert_grouped_field( $field655 );
    my $field949 = MARC::Field->new( '949',' ','1', c => '1', h => '090',i=>'wwcii', o => '-', r => '-', s => '-', t => '019', u => '-' );
    $marc->insert_grouped_field( $field949 );
    $marc = prefix856u($marc,"http://library3.webster.edu/login?url=");
    $marc = change856z($marc,"Webster-Eden: Click here to access this online book");
    return $marc;
}

sub manipulate_another_project
{
    my $marc = @_[0];
    
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

sub KC_Towers_FOD_MBTS
{
	my $marc = @_[0];
    my $z001 = $marc->field('001');
    $z001->update("fod".$z001->data());
	my $new_field_655 = MARC::Field->new('655',' ','7','a' => 'Guidance & Counseling Collection.', 2 => 'local');
	$marc->insert_grouped_field( $new_field_655 );
	my $new_field_949 = MARC::Field->new('949',' ','1','h' => '040','i' => '0','l' => 'btacc','r' => 's','s' => '-', 't' => '014', 'u' => '-','z' => '099', 'a' => 'MBTS FILMS ON DEMAND; click MBTS link above to access');
	$marc->insert_grouped_field( $new_field_949 );
	$marc = change856z($marc,"MBTS streaming video; click here to access");
    return $marc;
}

sub KC_Towers_FOD_MWSU
	
{
	my $marc = @_[0];
    my $z001 = $marc->field('001');
    $z001->update("fod".$z001->data());
	my $new_field_949 = MARC::Field->new('949',' ','1', 'a' => 'MW Films on Demand', 'g' => '1', 'h' => '020','i' => '0','l' => 'm2wii', 'o' => '','r' => '-','s' => '-', 't' => '014', 'u' => '','z' => '099', );
	$marc->insert_grouped_field( $new_field_949 );
	$marc = change856z($marc,"MWSU Access");
    return $marc;

}

sub KC_Towers_FOD_NCMC
{
	my $marc = @_[0];
    my $z001 = $marc->field('001');
    $z001->update("fod".$z001->data());
	my $new_field_949 = MARC::Field->new('949', ' ','1', 'a' => 'NCMC Films on Demand', 'g' => '1', 'h' => '030','i' => '0','l' => 'ln3mai', 'o' => '-','r' => '-','s' => '-', 't' => '014', 'u' => '-','z' => '099', );
	$marc->insert_grouped_field( $new_field_949 );
	$marc = change856z($marc,"NCMC Films on Demand; click to access");
    return $marc;
}




sub KC_Towers_FOD_NWMSU

{
	my $marc = @_[0];
    my $z001 = $marc->field('001');
	$z001->update("fod".$z001->data());
	$marc = prefix856u($marc,"http://ezproxy.nwmissouri.edu:2048/login?url=");
	my $new_field_949 = MARC::Field->new('949', ' ','1', 'a' => 'NWO Films on Demand', 'g' => '1', 'h' => '110','i' => '0','l' => 'w4red', 'o' => '-','r' => '-','s' => '-', 't' => '014', 'u' => '-','z' => '099', 'x' => 'Films on Demand collection' );
	$marc->insert_grouped_field( $new_field_949 );
	$marc = change856z($marc,"NORTHWEST streaming video; click to access");
    return $marc;
}

#EMO Deletes IR
sub EMO_Deletes_IR

{
    my $marc = @_[0];
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS INN-Reach eMO Collection' );
    $marc->insert_grouped_field( $field590 );
    return $marc;
}

sub EMO_Deletes_Bridges

{
	my $marc = @_[0];

    my $z001 = $marc->field('001');
    my $z0011= $z001->data();
	$z0011=~s/[^0-9]//g;
	$z001->update("eMOe".$z0011);
	my @e019s = $marc -> field('019');
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
	my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	return $marc;
}

sub EMO_Deletes_Everyone
{
    my $marc = @_[0];
	my $z001 = $marc->field('001');
    $z001->update("eMOe".$z001->data());
	my @e019s = $marc -> field('019');
	    
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
    return $marc;
}
#Updates Archway/ EMO_Updates_Archway
sub EMO_Updates_Archway
{
    my $marc = @_[0];
	my $z001 = $marc->field('001');
	$z001->update("eMOe".$z001->data());
	my @e019s = $marc -> field('019');
	    
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my $new_field_9491 = MARC::Field->new('949', ' ','1', 'v' => 'eBooks on EBSCOhost', 'g' => '1', 'h' => '001','i' => '0','l' => 'eceii', 'o' => '-','r' => 'z','s' => 'i', 't' => '058', 'u' => '-');
	$marc->insert_grouped_field( $new_field_9491 );
	my $new_field_9492 = MARC::Field->new('949', ' ','1', 'v' => 'eBooks on EBSCOhost', 'g' => '1', 'h' => '002','i' => '0','l' => 'jheri', 'o' => '-','r' => 'z','s' => 'i', 't' => '058', 'u' => '-');
	$marc->insert_grouped_field( $new_field_9492 );
	my $new_field_9493 = MARC::Field->new('949', ' ','1', 'v' => 'eBooks on EBSCOhost', 'g' => '1', 'h' => '003','i' => '0','l' => 'cleni', 'o' => '-','r' => 'z','s' => 'i', 't' => '058', 'u' => '-');
	$marc->insert_grouped_field( $new_field_9493 );
	my $new_field_9494 = MARC::Field->new('949', ' ','1', 'v' => 'eBooks on EBSCOhost', 'g' => '1', 'h' => '005','i' => '0','l' => 'pcleb', 'o' => '-','r' => 'z','s' => 'i', 't' => '058', 'u' => '-');
	$marc->insert_grouped_field( $new_field_9494 );

    return $marc;
}

#Updates Galahad/ EMO_Updates_Galahad
sub EMO_Updates_Galahad
{
    my $marc = @_[0];
	my $z001 = $marc->field('001');
	
    $z001->update("eMOe".$z001->data());
	
	my @e019s = $marc -> field('019');
	   
	foreach(@e019s)
    {
        my $thisfield = $_;
		
        $thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my $new_field_9491 = MARC::Field->new('949', ' ','1', 'a' => 'eBook', 'g' => '1', 'h' => '010','i' => '0','l' => 'mcecp', 'o' => '-','r' => '-','s' => '-', 't' => '061', 'u' => '-', 'z' => '099');
	$marc->insert_grouped_field( $new_field_9491 );
	my $new_field_9492 = MARC::Field->new('949', ' ','1', 'a' => 'eBook', 'g' => '1', 'h' => '020','i' => '0','l' => 'skkeb', 'o' => '-','r' => '-','s' => '-', 't' => '061', 'u' => '-', 'z' => '099');
	$marc->insert_grouped_field( $new_field_9492 );
	my $new_field_9493 = MARC::Field->new('949', ' ','1', 'a' => 'eBook', 'g' => '1', 'h' => '030','i' => '0','l' => 'trers', 'o' => '-','r' => 'n','s' => '-', 't' => '061', 'u' => '-', 'z' => '099');
	$marc->insert_grouped_field( $new_field_9493 );
	
    return $marc;
}

#Updates Arthur/ EMO_Updates_Arthur
sub EMO_Updates_Arthur
{
    my $marc = @_[0];
	my $z001 = $marc->field('001');
	$z001->update("eMOe".$z001->data());
	
	my @e019s = $marc -> field('019');
	  
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my $new_field_949 = MARC::Field->new('949', ' ','1', 'a' => 'E-Book', 'g' => '1', 'h' => '0','i' => '0','l' => 'shar2', 'o' => '-','r' => 's','s' => '-', 't' => '015', 'u' => '-', 'z' => '099');
	$marc->insert_grouped_field( $new_field_949 );
	
    return $marc;
}

#Updates Christian County/ EMO_Updates_Christian_County
sub EMO_Updates_Christian_County
{
    my $marc = @_[0];

	my $z001 = $marc->field('001');
	
    $z001->update("eMOe".$z001->data());
	my @e019s = $marc -> field('019');
	    
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my $new_field_949 = MARC::Field->new('949', ' ','1', 'g' => '1', 'q' => '0','l' => 's9ebk', 'r' => '-','s' => 'e', 't' => '0');
	$marc->insert_grouped_field( $new_field_949 );
	
    return $marc;
}

#Updates KC-Towers/ EMO_Updates_KC_Towers
sub EMO_Updates_KC_Towers
{
    my $marc = @_[0];
	my $z001 = $marc->field('001');
	$z001->update("eMOe".$z001->data());
	
	my @e019s = $marc -> field('019');
	    
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my $new_field_949 = MARC::Field->new('949', ' ','1', 'h' => '0','l' => 'share', 's' => 'i', 't' => '014','z' => '099');
	$marc->insert_grouped_field( $new_field_949 );
	
    return $marc;
}

#Updates INN-Reach/ EMO_Updates_IR
sub EMO_Updates_IR
{
    my $marc = @_[0];

    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS INN-Reach eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	return $marc;
}

#Updates Avalon/ EMO_Updates_Avalon
sub EMO_Updates_Avalon
{
	my $marc = @_[0];
	my $z001 = $marc->field('001');
	$z001->update("eMOe".$z001->data());
	
	my @e019s = $marc -> field('019');
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
	
	if ($baseFileName =~ m/\.M(\d+.*?)\.T/) {
        my $bfndate = $1;
		my $bfnyyy=substr($bfndate, 0, 4);
		my $bfnmm=substr($bfndate, 4, 2);
        my $bfnd= $bfnyyy."-".$bfnmm;
		my $new_field_949 = MARC::Field->new('949', ' ','1', 'a' => 'eMO E-Book', 'd' => $bfnd, 'g' => '1', 'h' => '000', 'i' => '0', 'k' => 'load-update', 'l' => 'emo', 'o' => '-', 'r' => 'n', 's' => '-', 't' => '015', 'u' => '-','z' => '099');
		$marc->insert_grouped_field( $new_field_949 );
    }
	my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my @field650s=$marc->field('650');
	
	foreach(@field650s)
    {
        my $thisfield = $_;
		$mytemp1= $thisfield->as_usmarc;
				
				
		if (($mytemp1 =~m/2abisacsh/i) || ($mytemp1 =~m/7abisacsh/i) )
			{
				$marc->delete_fields($thisfield);
					
			}
	}
		
	return $marc;
}
#Updates SWAN/ EMO_Updates_SWAN
sub EMO_Updates_SWAN
{
    my $marc = @_[0];
	my $z001 = $marc->field('001');
    $z001->update("eMOe".$z001->data());
	
	my @e019s = $marc -> field('019');
    
	foreach(@e019s)
    {
        my $thisfield = $_;
		$thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
    my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my @field650s=$marc->field('650');
	
	foreach(@field650s)
    {
        my $thisfield = $_;
		$mytemp1= $thisfield->as_usmarc;
							
		if (($mytemp1 =~m/4aElectronic\sBooks/i) || ($mytemp1 =~m/7aElectronic\sBooks/i) || ($mytemp1 =~m/4aElectronic\sBook/i)||($mytemp1 =~m/7aElectronic\sBook/i))
			{
				$marc->delete_fields($thisfield);
			}
	}
	my @field655s=$marc->field('655');
	
	foreach(@field655s)
    {
        my $thisfield = $_;
		
		$mytemp1= $thisfield->as_usmarc;
						
		if (($mytemp1 =~m/Electronic\sBooks/i) || ($mytemp1 =~m/Electronic\sBooks/i) || ($mytemp1 =~m/Electronic\sBook/i)||($mytemp1 =~m/Electronic\sBook/i))
			{
				$marc->delete_fields($thisfield);
			} 
    }
		
	my $new_field_9491 = MARC::Field->new('949', ' ','1', 'h' => '80','l' => '8vdsi','s' => 'i', 'r' => 'z');
	$marc->insert_grouped_field( $new_field_9491 );
	my $new_field_9492 = MARC::Field->new('949', ' ','1', 'h' => '70','l' => 'trbii','s' => '-', 'r' => 'ns');
	$marc->insert_grouped_field( $new_field_9492 );
	my $new_field_9493 = MARC::Field->new('949', ' ','1', 'h' => '10','l' => 'cneii','s' => '-', 'r' => 's');
	$marc->insert_grouped_field( $new_field_9493 );
	my $new_field_9494 = MARC::Field->new('949', ' ','1', 'h' => '20','l' => 'doeii','s' => '-');
	$marc->insert_grouped_field( $new_field_9494 );
	my $new_field_9495 = MARC::Field->new('949', ' ','1', 'h' => '90','l' => 'eugeb','s' => '-');
	$marc->insert_grouped_field( $new_field_9495 );
	my $new_field_9496 = MARC::Field->new('949', ' ','1', 'h' => '30','l' => 'msebk','s' => '-', 'r' => 's');
	$marc->insert_grouped_field( $new_field_9496 );
	my $new_field_9497 = MARC::Field->new('949', ' ','1', 'h' => '60','l' => 'smeeb','s' => '-', 'r' => 's');
	$marc->insert_grouped_field( $new_field_9497 );
	my $new_field_9498 = MARC::Field->new('949', ' ','1', 'h' => '110','l' => '77er0','s' => '-', 'r' => 'rs');
	$marc->insert_grouped_field( $new_field_9498 );
	my $new_field_9499 = MARC::Field->new('949', ' ','1', 'h' => '40','l' => 'oseei','s' => 'e');
	$marc->insert_grouped_field( $new_field_9499 );
	my $new_field_94910 = MARC::Field->new('949', ' ','1', 'h' => '50','l' => 'bbeei','s' => '-');
	$marc->insert_grouped_field( $new_field_94910 );
	
    return $marc;
}

#Updates Bridges/ EMO_Updates_Bridges
sub EMO_Updates_Bridges
{
	my $marc = @_[0];
	my $z001 = $marc->field('001');
	$z001->update("eMOe".$z001->data());
	
	my @e019s = $marc -> field('019');
	
	foreach(@e019s)
    {
        my $thisfield = $_;
	    $thisfield->update('a' => 'eMOe'.$thisfield->subfield('a'));
    }
	my $field590 = MARC::Field->new( '590',' ',' ', a => 'MOBIUS eMO Collection' );
    $marc->insert_grouped_field( $field590 );
	
	my $filed245s= $marc -> field ('245');
	
	if($filed245s)
	{
		
		my @subfields=();
		if (defined($filed245s->subfield('a'))) {
			push(@subfields,'a',$filed245s->subfield('a'));
		}
		if (defined($filed245s->subfield('p'))) {
			push(@subfields,'p',$filed245s->subfield('p'));
		}
		if (defined($filed245s->subfield('n'))) {
			push(@subfields,'n',$filed245s->subfield('n'));
		}
		push(@subfields,'h','[electronic resource]');
		
		@letters = ('b','c','d','e','f','g','i','j','k','l','m','o','q','r','s','t','u','v','w','x','y','z');
		foreach my $letter (@letters)
		{
			if (defined($filed245s->subfield($letter))) 
			{
				push(@subfields,$letter,$filed245s->subfield($letter));
			
			}
		}
		my $newfiled245s = MARC::Field->new('245', $filed245s->indicator(1), $filed245s->indicator(2), @subfields);
		$filed245s->replace_with($newfiled245s);
	}
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

sub checkFileReady
{
    my $file = @_[0];
    my $worked = open (inputfile, '< '. $file);
    my $trys=0;
    if(!$worked)
    {
        print "******************$file not ready *************\n";
    }
    while (!(open (inputfile, '< '. $file)) && $trys<100)
    {
        print "Trying again attempt $trys\n";
        $trys++;
        sleep(1);
    }
    close(inputfile);
}

sub ensureFinalFolderExists
{

    my $path = shift;
    if ( !(-d $path) )
    {
# print "Creating directory: $path\n";
        make_path($path, {
        verbose => 1,
        mode => 0711,
        });
    }
}

sub dirtrav
{
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

sub DESTROY
{
    print "I'm dying, deleting PID file $pidFile\n";
    unlink $pidFile;
}

exit;
