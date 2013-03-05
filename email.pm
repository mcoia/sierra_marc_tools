#!/usr/bin/perl
#
# Mobiusutil.pm
# 
# Requires:
#
# recordItem.pm sierraScraper.pm DBhandler.pm Loghandler.pm Mobiusutil.pm MARC::Record (from CPAN) Net::FTP
# 
# This is a simple utility class that provides some common functions
#
# Usage: my $mobUtil = new Mobiusutil(); #No constructor my $conf = $mobUtil->readConfFile($configFile);
#
# Other Functions available:
#	makeEvenWidth sendftp getMarcFromZ3950 chooseNewFileName trim findSummonIDs makeCommaFromArray
#
# Blake Graham-Henderson MOBIUS blake@mobiusconsortium.org 2013-1-24
package Mobiusutil;
 use use Email::MIME;
 
sub new {
    my $class = @_[0];
    my $self = 
	{
		emailRecipientArray => @{ @_[1] },
		notifyAdmin => @_[2],  #true/false
		notifyInfo => @_[3],   #true/false
		confArray => @{@_[4]},
		log => @_[5]
	};
	
    bless $self, $class;
    return $self;
}


sub send{

my $self = @_[0];
my $body = @_[1];
my $log = $self->{'log'};

my $message = Email::MIME->create(
  header_str => [
    From    => 'you@example.com',
    To      => 'friend@example.com',
    Subject => 'Happy birthday!',
  ],
  attributes => {
    encoding => 'quoted-printable',
    charset  => 'ISO-8859-1',
  },
  body_str => "Happy birthday to you!\n",
);

# send the message
use Email::Sender::Simple qw(sendmail);
sendmail($message);
}

sub xemail{

}
