#!/usr/bin/perl

# use Text::CSV_XS (csv);
use Text::CSV (csv);
use Data::Dumper;
use open ":std", ":encoding(UTF-8)";

=pod

So a quick note about a few things. This script doesn't like " qutation marks in the csv file. 
I think the more complete version of Text::CSV handles quotes. 
There was only 8 files so I just loaded them and replaced all the quotes with nothing. 

The header title patron type & item type records a 0 as we're not giving it anything.
This is a 1 and done script so I just left it. 

=cut

my $filename = shift;

if ($filename eq '') {
    print "Error!!! No csv file found! \n";
    print "Please specify a csv file.\n";
    print "Example: ./sierra-lrd-breadown.pl data.csv\n";
    exit(1);
}
else {
    print "processing file [$filename] \n";
}

my @doc = csv(in => $filename,  encoding => "utf8");

my @newDoc;

my $row_count = 0;

sub main {

    foreach (@doc) {

        foreach my $docRow (@{$_}) {
            push(@newDoc, @{buildRows($docRow)});
            $row_count++;
        }

    }

    writeCSV();

}

sub buildRows() {

    my $rowRef = shift;
    my @row = @{$rowRef};

    my $rowNumber = $row[0];
    my $location = $row[1];
    my $ageRange = $row[4];
    my $ruleNumber = $row[5];
    my $active = $row[6];
    my $editableBy = $row[7];

    my @finalRows;

    my @itemTypeArray = @{parseCommasANDHyphens($row[3])};
    foreach my $itemType (@itemTypeArray) {
        
        my @patronTypeArray = @{parseCommasANDHyphens($row[2])};
        foreach my $patronType (@patronTypeArray) {

            # chain it all together
            my $row =
                $rowNumber . "," .
                    $location . "," .
                    $patronType . "," .
                    $itemType . "," .
                    $ageRange . "," .
                    $ruleNumber . "," .
                    $active . "," .
                    $editableBy;

            push(@finalRows, $row);

        }

    }

    return \@finalRows;

}

sub writeCSV() {

    my $newFilename = $filename;
    $newFilename =~ s/.csv/-expanded.csv/g;
    print "saving file [$newFilename] \n";

    # open file for writing 
    open(FH, '>', $newFilename);

    # loop over @newDoc and write each row to the file 
    foreach my $docRow (@newDoc) {
        print FH $docRow . "\n";
    }

    close(FH);

}

sub parseCommasANDHyphens {

    my $text = shift;
    
    my @finalNumbers;

    # group all comma numbers
    my @commaNumbers = split(/,/, $text);

    # loop thru the comma seperated numbers. They may have hyphens still
    foreach my $numbers (@commaNumbers) {

        # split on the hyphens 
        if ($numbers =~ /-/) {
            my @hyphenNumbers = split(/-/, $numbers);

            # now loop over the hyphenated numbers 
            foreach my $hyphenNumber ($hyphenNumbers[0] .. $hyphenNumbers[1]) {
                push(@finalNumbers, ($hyphenNumber + 0));
            }

        }

        # no hyphen? just push it into our final array 
        else {
            push(@finalNumbers, ($numbers + 0));
        }

    }

    return \@finalNumbers;

}

# kick it off! 
main();

