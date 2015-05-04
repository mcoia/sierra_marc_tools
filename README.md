sierra_marc_tools
=================

Created by MOBIUS

You will need these packages ahead of time:
yaz
perl

perl mods:
 MARC::Record;
 MARC::File;
 MARC::File::USMARC;
 MARC::Charset
 ZOOM; 
 Net::FTP;
 Data::Dumper;
 DateTime;
 Encode;
 utf8;
 File::Copy;
 DBD::Pg;
 Unicode::Normalize; 
 Data::Dumper;

Summon or Ebsco MARC extract:

You will need:
summon_or_ebsco.pl
sierraScraper.pm
Mobiusutil.pm
Loghandler.pm
DBhandler.pm
recordItem.pm
email.pm

You can put these in the same folder on your linux machine.

Create a config file. Use config_file_sample.txt as an example.
You will need to setup your queries. You can use queries_sample.txt
for examples.

You will launch the app like this:

./summon_or_ebsco.pl configfile.conf [adds/cancels/full]

"adds" will cause the script to use the "adds" query that you setup
"cancels" will cause the script to use the "cancels" query that you setup
"full" will cause the script to use the "full" query that you setup

The adds and cancels will send the day before's changes (midnight to midnight).
You can set your cron to run the adds and cancels every day
