#!/usr/bin/perl

 use lib qw(../);
 use strict; 
 use Loghandler;
 use Mobiusutil;

my $mobUtil = new Mobiusutil();
my $volumnes = new Loghandler("/tmp/run/withvolumes.txt");
my $withoutvolumnes = new Loghandler("/tmp/run/withoutvolumes.txt");
my $volumesoutput = '';
my $withoutvolumnesoutput = '';
opendir(my $dh, "/tmp/temp") or die "can't opendir  $!";
print "opening /tmp/temp\n";
my $loop=0;
while (my $filename = readdir($dh))
{
	#print "$filename\n";
	if($filename =~ /^\./)
	{
		#do nothing with this
		#print "$filename\n";
	}
	else
	{
		if(1)#$loop < 100)
		{
			#print "$filename\n";
			if($filename =~ /merlin/)
			{
				my $thisfile = new Loghandler("/tmp/temp/".$filename);
				print $thisfile->getFileName()."\n";
				my @lines = @{$thisfile->readFile()};
				foreach(@lines)
				{
					#print "$_\n";
					my @cols = split("\t",$_);
					
					if(length($mobUtil->trim(@cols[8]))>0)
					{
						$volumesoutput.=$_;
						#print @cols[8];
					}
					else
					{
						$withoutvolumnesoutput.=$_;
					}
					$loop++;
				}
				
			}
			#print "$loop\n";
		}
		# else
		# {
			# closedir $dh;
			# $volumnes->truncFile($volumesoutput);
			# $withoutvolumnes->truncFile($withoutvolumnesoutput);

			# exit;
		# }
		$loop++;
	}	
}
closedir $dh;
$volumnes->truncFile($volumesoutput);
$withoutvolumnes->truncFile($withoutvolumnesoutput);

 
 exit;