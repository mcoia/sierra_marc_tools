#!/usr/bin/perl
#
# Loghandler.pm
#
# Requires:
#
# DateTime
#
# This class handles file (log) file read and writes
#
# Usage:
# my $log = new Loghandler("path/to/log/file");
# $log->addLogLine("Something that you want to log");
#
#
# Blake Graham-Henderson
# MOBIUS
# blake@mobiusconsortium.org
# 2013-1-24

package Loghandler;

use DateTime;
use File::Copy;
use utf8;

sub new
{
    my $class = shift;
    my $self =
    {
        _file => shift,
        'leaveopen' => 0
    };

    bless $self, $class;
    #return $self;
}

sub deleteFile
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    if (-e $file)
    {
        $worked = unlink($file);
        if($worked)
        {
            return 1;
        }
    }
    else
    {
        return 1;
    }

    return 0;

}

sub copyFile
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $destination = @_[1];
    return copy($file,$destination);
}

sub fileExists
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    if (-e $file)
    {
        return 1;
    }
    return 0;
}

sub getFileName
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    return $file;
}

sub addLogLine
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $dt   = DateTime->now(time_zone => "local");   # Stores current date and time as datetime object
    my $date = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
    my $time = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format

    my $line = @_[1];
    my $datetime = "$date $time";   # creates 'yyyy-mm-dd hh:mm:ss' string
    $datetime = makeEvenWidth('',$datetime,20);
    undef $mobutil;
    my $ret = 1;
    open(OUTPUT, '>> '.$file) or $ret=0;
    binmode(OUTPUT, ":utf8");
    print OUTPUT $datetime,": $line\n";
    close(OUTPUT);
    return $ret;
}

sub addLine
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $line = @_[1];
    my $ret=1;
    open(OUTPUT, '>> '.$file) or $ret=0;
    binmode(OUTPUT, ":utf8");
    print OUTPUT "$line\n";
    close(OUTPUT);
    return $ret;
}

sub addLineRaw
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $line = @_[1];
    open(OUTPUT, '>> '.$file) or die $!;
    binmode(OUTPUT, ":raw");
    print OUTPUT "$line\n";
    close(OUTPUT);
}

sub appendLineRaw
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $line = @_[1];
    open(OUTPUT, '>> '.$file) or die $!;
    binmode(OUTPUT, ":raw");
    print OUTPUT "$line";
    close(OUTPUT);
}

sub appendLine
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $line = @_[1];
    my $ret=1;
    open(OUTPUT, '>> '.$file) or $ret=0;
    binmode(OUTPUT, ":utf8");
    print OUTPUT "$line";
    close(OUTPUT);
    return $ret;
}

sub truncFile
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $line = @_[1];
    my $ret=1;
    open(OUTPUT, '> '.$file) or $ret=0;
    binmode(OUTPUT, ":utf8");
    print OUTPUT "$line\n";
    close(OUTPUT);
    return $ret;
}

sub readFile
{
    my ($self) = @_[0];
    my $file = $self->{_file};
    my $trys=0;
    my $failed=0;
    my @lines;
    #print "Attempting open\n";
    if(fileExists($self))
    {
        my $worked = open (inputfile, '< '. $file);
        if(!$worked)
        {
            print "******************Failed to read file*************\n";
        }
        binmode(inputfile, ":utf8");
        while (!(open (inputfile, '< '. $file)) && $trys<100)
        {
            print "Trying again attempt $trys\n";
            $trys++;
            sleep(1);
        }
        if($trys<100)
        {
            #print "Finally worked... now reading\n";
            @lines = <inputfile>;
            close(inputfile);
        }
        else
        {
            print "Attempted $trys times. COULD NOT READ FILE: $file\n";
        }
        close(inputfile);
    }
    else
    {
        print "File does not exist: $file\n";
    }
    return \@lines;
}

sub makeEvenWidth  #line, width
{
    my $ret;

    if($#_+1 !=3)
    {
        return;
    }
    $line = @_[1];
    $width = @_[2];
    #print "I got \"$line\" and width $width\n";
    $ret=$line;
    if(length($line)>=$width)
    {
        $ret=substr($ret,0,$width);
    }
    else
    {
        while(length($ret)<$width)
        {
            $ret=$ret." ";
        }
    }
    #print "Returning \"$ret\"\nWidth: ".length($ret)."\n";
    return $ret;

}

sub DESTROY
 {
    my ($self) = @_[0];
    my $file = $self->{_file};
    undef $self->{_file};
    undef $self;
 }

1;
