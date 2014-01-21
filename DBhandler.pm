#!/usr/bin/perl
#
# DBhandler.pm
# 
# Requires:
# 
# recordItem.pm
# sierraScraper.pm
# DBhandler.pm
# Loghandler.pm
# Mobiusutil.pm
# MARC::Record (from CPAN)
# 
# This code will handle the connection and query to the DB
#
# 
# Usage: 
# my $dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"});
# my $query = "SELECT 
#	(SELECT BIB_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE ITEM_RECORD_ID = A.ID),
#	SUBSTR(LOCATION_CODE,1,LENGTH(LOCATION_CODE)-2) FROM SIERRA_VIEW.ITEM_RECORD A WHERE A.ID IN(SELECT ITEM_RECORD_ID FROM SIERRA_VIEW.BIB_RECORD_ITEM_RECORD_LINK WHERE BIB_RECORD_ID IN(SELECT RECORD_ID FROM SIERRA_VIEW.BIB_RECORD LIMIT 10))";
#
#	my @results = @{$dbHandler->query($query)};
#	foreach(@results)
#	{
#		my $row = $_;
#		my @row = @{$row};
#		my $recordID = @row[0];
#		my $location = @row[1];
#		................
#	}
#	
#
# Blake Graham-Henderson 
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24

package DBhandler;
 #use DBI;
 use DBD::Pg;
 use Loghandler;
 use strict; 
 use Unicode::Normalize;
 use Encode;
 use utf8;
 use Data::Dumper;
 
 
 use String::Multibyte;
 
 
 sub new   #dbname,host,login,password,port
 {
	my $class = shift;
    my $self = 
	{
		dbname => shift,
		host => shift,
		login => shift,
		password => shift,
		port => shift,
		conn => ""
	};
	setupConnection($self);
	bless $self, $class;
    return $self;
 }
 
 sub setupConnection
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $dbname = $self->{dbname};
	my $host = $self->{host};
	my $login = $self->{login};
	my $pass = $self->{password};
	my $port = $self->{port};
	$conn =  DBI->connect("DBI:Pg:dbname=$dbname;host=$host;port=$port", $login, $pass, {pg_utf8_strings => 1,AutoCommit => 1}); #'RaiseError' => 1,post_connect_sql => "SET CLIENT_ENCODING TO 'UTF8'"
	
	$self->{conn} = $conn;
 }
 
 sub update
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $querystring =  @_[1];	

	my $ret = $conn->do($querystring);
	return $ret;
 }
 
 sub query
 {
 
 #
 #All of this messed up code commented out were different efforts to work out some strange
 #and unusual characters coming out of the database. Some of them still throw warnings to the 
 #console but don't seem to halt execution. Example: 
 #"\x{2113}" does not map to iso-8859-1 at /usr/lib64/perl5/Encode.pm line 158.
 #Right now the output to the marc records are correct but output to the console looks wrong.
 #This is probably due to multibyte unicode characters not being shown for the locale of my session.
 #
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $querystring =  @_[1];	
	my @ret;
#	print "$querystring\n";

	my $query = $conn->prepare($querystring);
	$query->execute();
	my %ar;
	#mb_internal_encoding("UTF-8");
	while (my $row = $query->fetchrow_arrayref())
	{
		my @pusher;
		foreach(@$row)
		{
			my $utf8 = String::Multibyte->new('UTF8');
			#print "Raw = $_\n";
			#my $teststring = "ṭṭār";
			#print "testing $teststring\n";
			#Encode::_set_utf8_on($_);
			my $conv = decode_utf8($_);# Encode::decode("utf8",$_);#Encode::_set_utf8_on($_);# $utf8->substr($_,0,$utf8->length($_));#$_;#Encode::encode_utf8($_);#$utf8->substr($_,0,$utf8->length($_));#Encode::encode_utf8($_);
			#$conv = Encode::encode_utf8($decode);
			#print "Enc = $conv\n";
			#print "conv = $conv\n";
			
# ------------ This if statement doesn't execute
			if(0)
			{
			
				if(Encode::is_utf8($conv))	
				{
				
				}
				else
				{
					#print "$_\nIS NOT UTF8\n";
				}
				
				my @mchars = $utf8->strsplit('', $conv);
				foreach(@mchars)
				{
					
					my $ord = $_; #ord $_;
					#print "$_ = $ord\n";
					
					if(exists($ar{$ord}))
					{
						$ar{$ord}++;
					}
					else
					{
						$ar{$ord}=1;
					}
				}
				
				my $str = $conv;#Encode::encode_utf8($_);
				if(0)
				{
					# this code is borrowed from the evergreen git repository 
					# (I added a few more unicode characters to the regex)
					#$str = uc $str;
					$str =~ s/\x{0098}.*?\x{009C}//g;   
					$str = NFKD($str);
					$str =~ s/\x{00C6}/AE/g;
					$str =~ s/\x{00DE}/TH/g;
					$str =~ s/\x{0152}/OE/g;
					$str =~ tr/\xC3\x81\x84\xAD\xA1\xBB\x8A\x{0302}\x{0303}\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}\x{0117}][/DDOLl/d;
					$conv = $str;
				}
			}
# ------------ END OF DISABLED CODE			
			#print "Enc = $str\n";

			push(@pusher, $conv);
			#print "done testing $teststring\n";
		}
		#my @pusher;
		#foreach(@$row)
		#{
			#my $pushChars=Encode::encode("UTF-8","");
			#my @chars = split("",$_);
			#if(!Test::utf8->is_sane_utf8(Encode::encode("UTF-8",$_)))
			#{
				#print "not an utf8 character\n";
			#}
			#foreach(@chars)
			#{
				#my $test = Test::utf8->isnt_within_ascii();
				#print compose(reorder($_));
				#(my $str = $_) =~ s/(.|\n)/sprintf("%02lx", ord $1)/eg;
				#
				#my $encoded = $_;#Encode::encode("UTF-8",$_);#decode("UTF-8",$_);#
				#if(Encode::is_utf8($_))
				#{
				#	$encoded = Encode::encode("UTF-8",$_);
					#print "it's UTF-8";
				#}
				#my $ord = ord($encoded);
				#$pushChars.=$encoded;
				#my $temp = utf8::upgrade($_);
				#print $encoded." $ord ";
			#}
			#print "$pushChars\n";
		#}
		push(@ret,[@pusher]);  #@$row   @pusher
		@pusher=undef;
	}
	#print $querystring."\n";
	#while ((my $internal, my $value ) = each(%ar))
	#{
		#if($value<20)
		#{
			#my $in = ord $internal;
			#print "$internal = $in occured $value time(s)\n";
		#}
	#}

	undef($querystring);
	return \@ret;
	
 }
 
 sub copyinput
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $oquerystring =  @_[1];
	my $delimeter="\t";
	if(@_[2])
	{
		$delimeter=@_[2];
	}
	my $index = index(uc($oquerystring),"FROM");
	if($index==-1)
	{
		return "Invalid COPY query";
	}
	
	my $querystring = substr($oquerystring,0,$index);
	if(substr($querystring,0,1)=='\\')
	{
		$querystring=substr($querystring,1);
	}
	my $file = substr($oquerystring,$index+5);
	$file =~ s/^\s+//;
	$file =~ s/\s+$//;
	if(!(-e $file))
	{
		return "Could not find $file";
	}
	
	my $inputfile = new Loghandler($file);
	my @lines = @{$inputfile->readFile()};
	#print "Running $querystring FROM STDIN WITH DELIMITER '$delimeter'\n";
	$conn->do("$querystring FROM STDIN WITH DELIMITER '$delimeter'");
	foreach(@lines)
	{
		$conn->pg_putcopydata($_);
	}
	
	return $conn->pg_putcopyend();
 }
 
 sub getConnectionInfo
 {
	my ($self) = @_[0];
	my %info = (
		dbname => $self->{dbname},
		host =>  $self->{host},
		login => $self->{login},
		password => $self->{password},
		port => $self->{port}
	);
	return \%info;
 }
 sub DESTROY
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	$conn->disconnect();
	$conn = undef;
 }
 1;