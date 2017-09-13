#!/usr/bin/perl

# This 

 use lib qw(../);
 use Loghandler;
 use Mobiusutil;
 use DateTime;
 use DateTime::Format::Duration;
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
		
		my @reqs = ("login","password","host","cluster","alwaysemail","fromemail","secondpassword","secondlogin","globallinkreportemail"); 
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
		if($valid)
		{			
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
			{	
				$cluster = $conf{"cluster"};
				$log->addLogLine("$cluster $type *STARTING*");
				my $dt   = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
				my $fdate = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
				my $ftime = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
				my $dateString = "$fdate $ftime";  # "2013-02-16 05:00:00";
				
				my $friendlyType = "Scope Authority";
				if($type eq "global")
				{
					$friendlyType = "Global Link";
				}
				my @tolist = ($conf{"alwaysemail"});
				$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
				$email->send("RMO $cluster - $friendlyType Winding Up - Job # $dateString","I have started this process.\r\n\r\nYou will be notified when I am finished\r\n\r\n-MOBIUS Perl Squad-");
	# THESE ARRAYS ARE CRAFTED LIKE THIS:
	# Timeout (in seconds), Prompt searching for, Keystroke when prompt is found, True/False to throw error if prompt doesn't appear
	# The reason there are multiple arrays:
	# If a prompt is not found, the rest of the array is skipped and the next array begins
				my @firstPrompts = (				
				50,"ADDITIONAL system functions","a",1,
				10,"Scope Authorit","u",1,
				10,"Login",$conf{"secondlogin"}."\r",1,
				10,"Password",$conf{"secondpassword"}."\r",1,
				10,"Scope authority records now? (y/n)","y",1,
				10,"(Press <RETURN> to start)","\r",1,
				352800,"Choose one","q",1,
				10,"Choose on","q",1
				);
				if($cluster eq 'explore' or $cluster eq 'swbts')
				{
					@firstPrompts = (
					10,"Login",$conf{"secondlogin"}."\r",1,
					10,"Password",$conf{"secondpassword"}."\r",1,					
					50,"ADDITIONAL system functions","a",1,
					10,"Scope Authorit","u",1,
					10,"Login",$conf{"secondlogin"}."\r",1,
					10,"Password",$conf{"secondpassword"}."\r",1,
					10,"Scope authority records now? (y/n)","y",1,
					10,"(Press <RETURN> to start)","\r",1,
					352800,"Choose one","q",1,
					10,"Choose on","q",1
					);
				}
				my @allPrompts = ([@firstPrompts]);
				if($type eq "global")
				{
					@firstPrompts = (
					50,"ADDITIONAL system functions","a",1,
					10,"Maintain record LINKS","l",1,
					10,"Login",$conf{"secondlogin"}."\r",1,
					10,"Password",$conf{"secondpassword"}."\r",1
					);
					if($cluster eq 'explore' or $cluster eq 'swbts')
					{
						@firstPrompts = (
						10,"Login",$conf{"secondlogin"}."\r",1,
						10,"Password",$conf{"secondpassword"}."\r",1,	
						50,"ADDITIONAL system functions","a",1,
						10,"Maintain record LINKS","l",1,
						10,"Login",$conf{"secondlogin"}."\r",1,
						10,"Password",$conf{"secondpassword"}."\r",1
						);
					}
					
					my @more = (
					10,"BOTH rearrange attached records and update","b",0
					);
					
					my @more2 = (
					10,"RANGE of record numbers","r",1,
					10,"Enter starting record","\r",1,
					10,"Enter ending","\r",1,
					10,"Use scoped range?","n",0
					);
					
					my @more3 = (
					10,"Is the range correct?","y",1,
					10,"Choose one (C,I,O,A,Q)","a",1,
					10,"Begin processing?","y",1,
					352800,"records examined","a",1###########
					);
					
					my @second = (				
					10,"Press <SPACE> to continue"," ",0
					);
					
					my @third = (				
					10,"Would you like to view records","y",0,
					10,"P,Q)","p",1,
					10,"Enter full email address:",$conf{"globallinkreportemail"}."\r",1,
					10,"ote","\r",0,
					10,"Choose one (P,Q)","q",1
					);
					
					my @forth = (				
					10,"Choose one (R,B,E,Q","q",1,
					10,"Choose one (M,H,R,I","q",0
					);
					
					my @fifth = (					
					10,"Choose one (R,U,B,Q","q",0,
					10,"Choose one","q",0,
					10,"Choose one","q",0
					);
					
					my @six = (										
					10,"Choose one","q",0,
					10,"Choose one","q",0
					);
					
					
					@allPrompts = ([@firstPrompts],[@more],[@more2],[@more3],[@second],[@third],[@forth],[@fifth],[@six]);
				}
				
				
				my $error = $mobUtil->expectConnect($conf{"login"},$conf{"password"},$conf{"host"},\@allPrompts,$conf{"privatekey"});
				my @errors = @{$error};
				#print Dumper(@errors);
				my $errors = @errors[$#errors];
				my $emailBody;
				for my $i (0..($#errors-1))
				{
					$emailBody.=@errors[$i]."\r\n";
				}
				
				my $format = DateTime::Format::Duration->new(
					pattern => '%e days, %H hours, %M minutes, %S seconds'
					);
				my $afterProcess = DateTime->now(time_zone => "local");
				my $difference = $afterProcess - $dt;
				my $duration =  $format->format_duration($difference);
				if($errors!=1)
				{
					$log->addLogLine("$cluster $type: ERROR: $errors");
					$email = new email($conf{"fromemail"},\@tolist,1,0,\%conf);
					$email->send("RMO $cluster - $friendlyType Fail - Job # $dateString","Duration: $duration\r\n\r\nUnfortunately, there are some errors. Here are all of the prompts that I answered:\r\n\r\n$emailBody\r\n\r\nAnd here are the errors:\r\n\r\n$errors\r\n\r\n-MOBIUS Perl Squad-");
				}
				else
				{
					$log->addLogLine("$cluster $type: Success!");
					$email = new email($conf{"fromemail"},\@tolist,0,1,\%conf);
					$email->send("RMO $cluster - $friendlyType Success - Job # $dateString","Duration: $duration\r\n\r\nThis process finished without any errors!\r\n\r\nIsn't that WONDERFUL?!\r\n\r\nHere are all of the prompts that I answered:\r\n\r\n$emailBody\r\n\r\n-MOBIUS Perl Squad-");
				}
				
			}
		}
		$log->addLogLine("$cluster $type *ENDING*");	
	}
	else
	{
		print "Config file does not define 'logfile' and 'marcoutdir'\n";
		
	}
}

exit;
 
 