#!/usr/bin/perl

# This 

 use Loghandler;
 use Mobiusutil;
 use Data::Dumper;
 use email;
 
		
 my $configFile = @ARGV[0];
 if(!$configFile)
 {
	print "Please specify a config file\n";
	exit;
 }

 my $mobUtil = new Mobiusutil(); 
 my $conf = $mobUtil->readConfFile($configFile);
 
 if($conf)
 {
	my %conf = %{$conf};
	if ($conf{"logfile"})
	{
	
		my $log = new Loghandler($conf->{"logfile"});
		$log->addLogLine(" ---------------- Script Starting ---------------- ");
		my @reqs = ("login","password","host","cluster","alwaysemail","fromemail","secondpassword"); 
		my $valid = 1;
		for my $i (0..$#reqs)
		{
			if(!$conf{@reqs[$i]})
			{
				$log->addLogLine("Required configuration missing from conf file");
				$log->addLogLine(@reqs[$i]." required");
				$valid = 0;
			}
		}
		my $type = @ARGV[1];
		if(defined($type))		
		{
			if($type eq "scope")
			{
				$valid = 1;
			}
			elsif($type eq "global")
			{
				$valid = 1;
			}
			else
			{
				$valid = 0;
				print "You need to specify the type 'scope' or 'global'\n";
			}
		}
		else
		{
			$valid = 0;
			print "You need to specify the type 'scope' or 'global'\n";
		}
		
		if($valid)
		{	# undef,"(Press <RETURN> to start)","\r",
				
			$cluster = $conf{"cluster"};			
			
			
			my $friendlyType = "Scope Authority";
			if($type eq "global")
			{
				$friendlyType = "Global Link";
			}
			my @tolist = ();
			$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
			$email->send("RMO $cluster - $friendlyType Winding Up","I have started this process.\r\n\r\nYou will be notified when I am finished\r\n\r\n-MOBIUS Perl Squad-");
			
			my @firstPrompts = (
			10,"ADDITIONAL system functions","a",
			10,"Scope Authority Records","u",
			10,"Login","mco\r",
			10,"Password",$conf{"secondpassword"}."\r",
			10,"Scope authority records now? (y/n)","n",
			
			10,"Choose one","q",
			10,"Choose one","q"
			);
			my @allPrompts = ([@firstPrompts]);
			if($type eq "global")
			{
				@firstPrompts = (
				10,"ADDITIONAL system functions","a",
				10,"Maintain record LINKS","l",
				10,"Login","mco\r",
				10,"Password",$conf{"secondpassword"}."\r",
				10,"BOTH rearrange attached records and update","b",
				10,"RANGE of record numbers","r",
				10,"Enter starting record","\r",
				10,"Enter ending","\r",
				10,"Use scoped range?","n",
				10,"Is the range correct?","y",
				10,"Choose one (C,I,O,A,Q)","a",
				10,"Begin processing?","n",
				10,"records examined","a"
				);
				my @second = (				
				10,"Press <SPACE> to continue"," "
				);
				my @third = (				
				10,"Would you like to view records","y",
				10,"Choose one (P,Q)","p",
				10,"Enter full email address:",$conf{"globallinkreportemail"},
				10,"Choose one (P,Q)","q",
				);
				my @forth = (				
				10,"Choose one (R,B,E,Q","q",
				10,"Choose one (R,U,B,Q","q",
				10,"Choose one","q",
				10,"Choose one","q"
				);
				
				
				@allPrompts = ([@firstPrompts],[@second],[@third],[@forth]);
			}
	
			
			$errors = $mobUtil->expectConnect($conf{"login"},$conf{"password"},$conf{"host"},\@allPrompts);			
			if(!$errors)
			{
				$log->addLogLine("$cluster: ERROR: $errors");
				@tolist = ($conf{"alwaysemail"});
				$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
				$email->send("RMO $cluster - $friendlyType Fail","Unfortunatly, there are some errors:\r\n$errors\r\n\r\n-MOBIUS Perl Squad-");
			}
			else
			{
				$log->addLogLine("$cluster: Success!");
				@tolist = ($conf{"alwaysemail"});
				$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
				$email->send("RMO $cluster - $friendlyType Success","This process finished without any errors!\r\n\r\nIsn't that WONDERFUL?!\r\n\r\n-MOBIUS Perl Squad-");
			}
			
		}
		$log->addLogLine(" ---------------- Script Ending ------------------ ");
	}
	else
	{
		print "Config file does not define 'logfile' and 'marcoutdir'\n";
		
	}
}

exit;
 
 