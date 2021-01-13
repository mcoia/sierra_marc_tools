#!/usr/bin/perl
#
# DBhandler.pm
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
# 2014-4-03

package DBhandler;
 use DBD::Pg;
 #use DBD::Firebird;
 use Loghandler;
 use strict; 
 #use Unicode::Normalize;
 use Encode;
 use utf8;
 use Data::Dumper;
 
 our @columnNames;
 
 
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
		firebird => shift,
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
	my $firebird = $self->{firebird};
	if(!$firebird)
	{
		$conn =  DBI->connect("DBI:Pg:dbname=$dbname;host=$host;port=$port", $login, $pass, { AutoCommit => 1}); #'RaiseError' => 1,post_connect_sql => "SET CLIENT_ENCODING TO 'UTF8'", pg_utf8_strings => 1
	}
	else
	{
		$conn =  DBI->connect("DBI:Firebird:db=$dbname;host=$host/$port", $login, $pass, { AutoCommit => 1, LongReadLen => 10000000});
	}
	
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
 
 sub updateWithParameters
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $querystring =  @_[1];	
	my @values =  @{@_[2]};
	my $q = $conn->prepare($querystring);
	my $i=1;
	foreach(@values)
	{
		my $param = $_;
		if(lc($param eq 'null'))
		{
			$param = undef;
		}
		$q->bind_param($i, $param);
		$i++;
	}
	my $ret = $q->execute();
	return $ret;
 }
 
 sub query
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $querystring =  @_[1];	
	my @ret;

	my $query = $conn->prepare($querystring);
	$query->execute();
	@columnNames = @{$query->{NAME}};
	my %ar;

	while (my $row = $query->fetchrow_arrayref())
	{	
		push(@ret,[@$row]);
	}
	undef($querystring);
	return \@ret;
 }
 
 sub getColumnNames
 {
	return \@columnNames;
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
 
 sub getQuote
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $string =  @_[1];	
	return $conn->quote($string);
 }
 
 sub breakdown
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	$conn->disconnect();
	$conn = undef;
 }
 
 sub DESTROY
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	$conn->disconnect();
	$conn = undef;
 }
 
 
 1;