## Sierra Marc Tools

Created by MOBIUS

## Introduction

## Requirements

This repo requires the following packages, perl modules, and custom perl modules:

### Packages

* yaz
* perl

### Perl modules

* MARC::Record;
* MARC::File;
* MARC::File::USMARC;
* MARC::Charset
* Net::FTP;
* Data::Dumper;
* DateTime;
* Encode;
* utf8;
* File::Copy;
* Unicode::Normalize; 
* Data::Dumper;

* ZOOM; 
* DBD::Pg (requires postgresql)

### Summon or Ebsco MARC extract

* summon_or_ebsco.pl
* sierraScraper.pm
* Mobiusutil.pm
* Loghandler.pm
* DBhandler.pm
* recordItem.pm
* email.pm

## Installation

Place in the same folder on your linux machine.

### Configuration

Create a config file. Use config_file_sample.txt as an example.
Set up your queries. Use queries_sample.txt as an example.

### Usage

You will launch the app like this:

```
./summon_or_ebsco.pl configfile.conf [adds/cancels/full]
```

"adds" will cause the script to use the "adds" query that you setup
"cancels" will cause the script to use the "cancels" query that you setup
"full" will cause the script to use the "full" query that you setup

The adds and cancels will send the day before's changes (midnight to midnight).
You can set your cron to run the adds and cancels every day
