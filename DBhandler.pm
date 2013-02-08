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
 use DBI;
 use Loghandler;
 use strict; 
 use utf8;
 
 sub new   #dbname,host,login,password
 {
	my $class = shift;
    my $self = 
	{
		dbname => shift,
		host => shift,
		login => shift,
		password => shift,
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
	$conn =  DBI->connect("DBI:Pg:dbname=$dbname;host=$host;port=1032", $login, $pass, {'RaiseError' => 1});
	$self->{conn} = $conn;
 }
 
 sub query
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	my $querystring =  @_[1];
	my @ret;
	
	#$conn->do("SET DateStyle = 'European'");

	my $query = $conn->prepare($querystring);
	$query->execute();
	
	while (my $row = $query->fetchrow_arrayref())
	{
		push(@ret,[@$row]);
	}

	undef($querystring);
	return \@ret;
	
 }
 
 sub DESTROY
 {
	my ($self) = @_[0];
	my $conn = $self->{conn};
	$conn->disconnect();
	$conn = undef;
 }
 1;