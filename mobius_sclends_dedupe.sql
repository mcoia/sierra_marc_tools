-- SCLENDS bibliographic dedupe routine
--
-- Copyright 2010-2011 Equinox Software, Inc.
-- Author: Galen Charlton <gmc@esilibrary.com>
-- 
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2, or (at your option)
-- any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--
-- This implements a bibliographic deduplication routine based
-- on criteria and an algorithm specified by the South Carolina
-- State Library on behalf of the SC LENDS consortium.  This work
-- was sponsored by SC LENDS, whose impetus is gratefully
-- acknowledged.  Portions of this script were subseqently expanded
-- based on the advice of the Indiana State Library on the behalf
-- of the Evergreen Indiana project.


-- This script has been expanded to merge the 856 fields of the duplicates
-- ADDED:
-- m_dedupe.updateboth()
-- m_dedupe.melt856s
-- m_dedupe.update_lead
-- m_dedupe.update_sub
-- Added 2 columns to merge_map
-- MOBIUS 04-08-2013


-- DROP SCHEMA m_dedupe CASCADE;
-- schema to store the dedupe routine and intermediate data
CREATE SCHEMA m_dedupe;

CREATE TYPE mig_isbn_match AS (norm_isbn TEXT, norm_title TEXT, qual TEXT, bibid BIGINT);


-- function to calculate the normalized ISBN and title match keys
-- and the bibliographic portion of the quality score.  The normalized
-- ISBN key consists of the set of 020$a and 020$z normalized as follows:
--  * numeric portion of the ISBN converted to ISBN-13 format
--
-- The normalized title key is taken FROM the 245$a with the nonfiling
-- characters and leading and trailing whitespace removed, ampersands
-- converted to ' and ', other punctuation removed, and the text converted
-- to lowercase.
--
-- The quality score is a 19-digit integer computed by concatenating
-- counts of various attributes in the MARC records; see the get_quality
-- routine for details.
--
CREATE OR REPLACE FUNCTION m_dedupe.get_isbn_match_key (bib_id BIGINT, marc TEXT) RETURNS SETOF mig_isbn_match AS $func$
		use strict;
		use warnings;

		use MARC::Record;
		use MARC::File::XML (BinaryEncoding => 'utf8');
		use Business::ISBN;
		use Loghandler;

		binmode(STDERR, ':bytes');
		binmode(STDOUT, ':utf8');
		binmode(STDERR, ':utf8');

		my $logf = new Loghandler("/tmp/log.log");

		$logf->addLine('Script running.....');

		my $get_quality = sub {
			my $marc = shift;

			my $has003 = (scalar($marc->field('003'))) ? '1' : '0';

			return join('', $has003,
							count_field($marc, '02.'),
							count_field($marc, '24.'),
							field_length($marc, '300'),               
							field_length($marc, '100'),               
							count_field($marc, '010'),
							count_field($marc, '50.', '51.', '52.', '53.', '54.', '55.', '56.', '57.', '58.'),
							count_field($marc, '6..'),
							count_field($marc, '440', '490', '830'),
							count_field($marc, '7..'),
						);
		};


		my ($bibid, $xml) = @_;


		$xml =~ s/(<leader>.........)./${1}a/;
		my $marc;
		eval {
			$marc = MARC::Record->new_from_xml($xml);
		};
		if ($@) {
		$logf->addLine("could not parse $bibid: $@");
			#elog("could not parse $bibid: $@\n");
			import MARC::File::XML (BinaryEncoding => 'utf8');
			return;
		}
		$logf->addLine("Success Parse $bibid: $@");
		my @f245 = $marc->field('245');
		return unless @f245; # must have 245
		my $norm_title = norm_title($f245[0]);
		return unless $norm_title ne '';

		my @isbns = $marc->field('020');
		return unless @isbns; # must have at least 020

		my $qual = $get_quality->($marc);

#		$logf->addLine("quality = $qual");

		my @norm_isbns = norm_isbns(\@isbns, $logf);
		#$logf->addLine("I recieved these isbns from subroutine: ".$#norm_isbns);
		foreach my $isbn (@norm_isbns) {
		$logf->addLine("$isbn, $norm_title, $qual, $bibid");
			return_next({ norm_isbn => $isbn, norm_title => $norm_title, qual => $qual, bibid => $bibid });
		}
		return undef;


		sub count_field {
			my ($marc) = shift;
			my @tags = @_;
			my $total = 0;
			foreach my $tag (@tags) {
				my @f = $marc->field($tag);
				$total += scalar(@f);
			}
			$total = 99 if $total > 99;
			return sprintf("%-02.2d", $total);
		}

		sub field_length {
			my $marc = shift;
			my $tag = shift;

			my @f = $marc->field($tag);
			return '00' unless @f;
			my $len = length($f[0]->as_string);
			$len = 99 if $len > 99;
			return sprintf("%-02.2d", $len);
		}

		sub norm_title {
			my $f245 = shift;
			my $sfa = $f245->subfield('a');
			return '' unless defined $sfa;
			my $nonf = $f245->indicator(2);
			$nonf = '0' unless $nonf =~ /^\d$/;
			if ($nonf == 0) {
				$sfa =~ s/^a //i;
				$sfa =~ s/^an //i;
				$sfa =~ s/^the //i;
			} else {
				$sfa = substr($sfa, $nonf);
			}
			$sfa =~ s/&/ and /g;
			$sfa = lc $sfa;
			$sfa =~ s/\[large print\]//;
			$sfa =~ s/[[:punct:]]//g;
			$sfa =~ s/^\s+//;
			$sfa =~ s/\s+$//;
			$sfa =~ s/\s+/ /g;
			return $sfa;
		}

		sub norm_isbns {
			my @isbns = @{@_[0]};
			my $logf = @_[1];
		#$logf->addLine("SUBROUTINE: I recieved these isbns: ".$#isbns);
			my %uniq_isbns = ();
			foreach my $field (@isbns) {
				my $sfa = $field->subfield('a');
		#$logf->addLine("I got this ISBN $sfa");
				my $norm = norm_isbn($sfa, $logf);
		#$logf->addLine("Normalize ISBN = $norm");
				$uniq_isbns{$norm}++ unless $norm eq '';

				my $sfz = $field->subfield('z');
				$norm = norm_isbn($sfz, $logf);
				$uniq_isbns{$norm}++ unless $norm eq '';
			}
			return sort(keys %uniq_isbns);
		}

		sub norm_isbn {
			my $str = @_[0];
			my $logf = @_[1];
			my $norm = '';
			return '' unless defined $str;
		#added because our test data only has 1 digit
			#return $str;
			

			$str =~ s/-//g;
			$str =~ s/^\s+//;
			$str =~ s/\s+$//;
			$str =~ s/\s+//g;
			$str = lc $str;
			my $isbn;
			if ($str =~ /^(\d{12}[0-9-x])/) {
				$isbn = $1;
				$norm = $isbn;
			} elsif ($str =~ /^(\d{9}[0-9x])/) {
				$isbn =  Business::ISBN->new($1);
				my $isbn13 = $isbn->as_isbn13;
				$norm = lc($isbn13->as_string);
				$norm =~ s/-//g;
			}
			return $norm;
		}
$func$ LANGUAGE PLPERLU;


-- Setup trigger to update marc xml cells on m_dedupe.merge_map when the xml on biblio.record_entry is updated
DROP FUNCTION m_dedupe.updateboth() CASCADE;
CREATE FUNCTION m_dedupe.updateboth() RETURNS trigger AS $updateboth$
    BEGIN
		UPDATE m_dedupe.merge_map SET lead_marc = NEW.marc WHERE lead_bibid = NEW.id;
		UPDATE m_dedupe.merge_map SET sub_marc = NEW.marc WHERE sub_bibid = NEW.id;
        RETURN NEW;
    END;
$updateboth$ LANGUAGE plpgsql;


-- Setup Custom 856 copy from duplicated record
DROP TYPE  eight56s_melt CASCADE; 
CREATE TYPE eight56s_melt AS (bibid BIGINT, marc TEXT);


CREATE OR REPLACE FUNCTION m_dedupe.melt856s(bib_id BIGINT,marc_primary TEXT, sub_bib_id BIGINT, marc_secondary TEXT) RETURNS SETOF eight56s_melt AS $functwo$
		use strict;
		use warnings;

		use MARC::Record;
		use MARC::File::XML (BinaryEncoding => 'utf8');
		use Business::ISBN;
		use Loghandler;
		use Data::Dumper;
		use utf8;

		binmode(STDERR, ':bytes');
		binmode(STDOUT, ':utf8');
		binmode(STDERR, ':utf8');

		my $logf = new Loghandler("/tmp/log.log");


		$logf->addLine("*********************Started new function*********************");


		my ($bibid, $xml, $bibid2, $xml2) = @_;
		$logf->addLine("$bibid, $bibid2");


		$xml =~ s/(<leader>.........)./${1}a/;
		$xml2 =~ s/(<leader>.........)./${1}a/;
		my $marc;
		my $marc2;
		eval {
			$marc = MARC::Record->new_from_xml($xml);
			$marc2 = MARC::Record->new_from_xml($xml2);
		};
		if ($@) {
		$logf->addLine("could not parse $bibid: $@");
		$logf->addLine("could not parse $bibid2: $@");
			import MARC::File::XML (BinaryEncoding => 'utf8');
			return;
		}

		my @eight56s = $marc->field("856");
		my @eight56s_2 = $marc2->field("856");
		my @eights;
		
#LOGGING
#	$logf->addLine("First 856's (DB ID: $bibid)\n{");
#		foreach(@eight56s)
#		{
#		$logf->addLine("\t{");
#			@eights = $_->subfield('u');
#				$logf->addLine("\tu fields:");
#				foreach(@eights)
#				{
#					$logf->addLine("\t\t$_");
#				}
#				@eights = $_->subfield('z');
#				$logf->addLine("\tz fields:");
#				foreach(@eights)
#				{
#					$logf->addLine("\t\t$_");
#				}
#				@eights = $_->subfield('9');
#				$logf->addLine("\t9 fields:");
#				foreach(@eights)
#				{
#					$logf->addLine("\t\t$_");
#				}
#		$logf->addLine("\t}");
#		}
#		$logf->addLine("}\nSecond 856's (DB ID: $bibid2)\n{");		
#		foreach(@eight56s_2)
#		{
#		$logf->addLine("\t{");
#			@eights = $_->subfield('u');
#				$logf->addLine("\tu fields:");
#				foreach(@eights)
#				{
#					$logf->addLine("\t\t$_");
#				}
#				@eights = $_->subfield('z');
#				$logf->addLine("\tz fields:");
#				foreach(@eights)
#				{
#					$logf->addLine("\t\t$_");
#				}
#				@eights = $_->subfield('9');
#				$logf->addLine("\t9 fields:");
#				foreach(@eights)
#				{
#					$logf->addLine("\t\t$_");
#				}
#		$logf->addLine("\t}");
#		}
#		$logf->addLine("}");	
# ENDING LOGGING
		@eight56s = (@eight56s,@eight56s_2);

		my %urls;  


		foreach(@eight56s)
		{
			my $thisField = $_;
			
			# Just read the first $u and $z
			my $u = $thisField->subfield("u");
			my $z = $thisField->subfield("z");
		#$logf->addLine("I got u = $u and z = $z");
			
			
			if(!exists $urls{$u})
			{
				$urls{$u} = $thisField;
			}
			else
			{
				my @nines = $thisField->subfield("9");
				my $otherField = $urls{$u};
				my @otherNines = $otherField->subfield("9");
				my $otherZ = $otherField->subfield("z");		
				if(!$otherZ)
				{
#				$logf->addLine("z didnt exist");
					if($z)
					{
						$otherField->add_subfields('z'=>$z);
#						$logf->addLine("it exists here, so im adding it to og");
					}
				}
				foreach(@nines)
				{
					my $looking = $_;
					my $found = 0;
					foreach(@otherNines)
					{
#					$logf->addLine("Searching for $looking");
						if($looking eq $_)
						{
							$found=1;
						}
					}
					if($found==0)
					{
#					$logf->addLine("Didnt find $looking so adding it to og");
						$otherField->add_subfields('9' => $looking);
					}
				}
				$urls{$u} = $otherField;
			}
		}
#my		$dump1=Dumper(\%urls);
		#$logf->addLine("$dump1");
#		$logf->addLine("Melted\n{");
		my @remove = $marc->field('856');
#		$logf->addLine("Removing ".$#remove." 856 records");
		$marc->delete_fields(@remove);


		while ((my $internal, my $mvalue ) = each(%urls))
			{
#LOGGING METHODS
#			$logf->addLine("\t{");
				@eights = $mvalue->subfield('u');
#				$logf->addLine("\tu fields:");
				foreach(@eights)
				{
#					$logf->addLine("\t\t$_");
				}
				@eights = $mvalue->subfield('z');
#				$logf->addLine("\tz fields:");
				foreach(@eights)
				{
#					$logf->addLine("\t\t$_");
				}
				@eights = $mvalue->subfield('9');
#				$logf->addLine("\t9 fields:");
				foreach(@eights)
				{
#					$logf->addLine("\t\t$_");
				}
#				$logf->addLine("\t}");
#LOGGING METHODS ENDING
				$marc->insert_grouped_field( $mvalue );
#				$logf->addLine("Inserted 856 back in");
			}
#		$logf->addLine("}");
		my $mobutil = new Mobiusutil();
		my @errors = @{$mobutil->compare2MARCObjects($marc,$marc2)};
						my $errors;
						foreach(@errors)
						{
							$errors.= $_."\r\n";
						}
		#$logf->addLine("$errors");
		my $returning = $marc->as_xml_record();
		$returning =~ s/\n//g;
		$returning =~ s/\<\?xml version="1.0" encoding="UTF-8"\?\>//g;
		#$logf->addLine("$returning");


		return_next({ bibid => $bibid, marc => $returning });
		
$logf->addLine("*********************Ended new function*********************");
		return undef;

$functwo$ LANGUAGE PLPERLU;


DROP FUNCTION update_lead(dedupeid BIGINT, thisbidid BIGINT);
CREATE OR REPLACE FUNCTION m_dedupe.update_lead(dedupeid BIGINT, thisbidid BIGINT) RETURNS text AS $functhree$	
BEGIN
	UPDATE biblio.record_entry bre SET marc=
		(
			SELECT marc FROM
			(
				SELECT (a.melt856s::eight56s_melt).marc AS marc,(a.melt856s::eight56s_melt).bibid as bibid
				FROM (		
				SELECT m_dedupe.melt856s(
				mm.lead_bibid, mm.lead_marc,
				mm.sub_bibid, mm.sub_marc )
				FROM 
				 m_dedupe.merge_map mm WHERE id=dedupeid
				) as a
			) as b WHERE b.bibid=bre.id
		)
		WHERE bre.id = thisbidid;
--Return nothing because the work has been done
RETURN '';
END;
$functhree$ LANGUAGE plpgsql;

DROP FUNCTION update_sub(dedupeid BIGINT, thisbidid BIGINT);
CREATE OR REPLACE FUNCTION m_dedupe.update_sub(dedupeid BIGINT, thisbidid BIGINT) RETURNS text AS $funcfour$	
BEGIN
	UPDATE biblio.record_entry bre SET marc=
		(
			SELECT marc FROM
			(
				SELECT (a.melt856s::eight56s_melt).marc AS marc,(a.melt856s::eight56s_melt).bibid as bibid
				FROM (		
				SELECT m_dedupe.melt856s(
				mm.sub_bibid, mm.sub_marc,
				mm.lead_bibid, mm.lead_marc )
				FROM 
				 m_dedupe.merge_map mm WHERE id=dedupeid
				) as a
			) as b WHERE b.bibid=bre.id
		)
		WHERE bre.id = thisbidid;
--Return nothing because the work has been done
RETURN '';
END;
$funcfour$ LANGUAGE plpgsql;



-- Specify set of bibs to dedupe.  This version
-- simply collects the IDs of all non-deleted bibs,
-- but the query could be expanded to exclude bibliographic
-- records that should not participate in the deduplication.
CREATE TABLE m_dedupe.bibs_to_check AS
SELECT id AS bib_id 
FROM biblio.record_entry bre
WHERE NOT deleted;

-- staging table for the match keys
CREATE TABLE m_dedupe.match_keys (
  norm_isbn TEXT,
  norm_title TEXT,
  qual TEXT,
  bibid BIGINT
);

-- calculate match keys
INSERT INTO m_dedupe.match_keys 
SELECT  (a.get_isbn_match_key::mig_isbn_match).norm_isbn,
        (a.get_isbn_match_key::mig_isbn_match).norm_title,
        (a.get_isbn_match_key::mig_isbn_match).qual,
        (a.get_isbn_match_key::mig_isbn_match).bibid                                                                                 
FROM (
    SELECT m_dedupe.get_isbn_match_key(bre.id, bre.marc)
    FROM biblio.record_entry bre
    JOIN m_dedupe.bibs_to_check c ON (c.bib_id = bre.id)
) a;

CREATE INDEX norm_idx on m_dedupe.match_keys(norm_isbn, norm_title);
CREATE INDEX qual_idx on m_dedupe.match_keys(qual);

-- and remove duplicates
CREATE TEMPORARY TABLE uniq_match_keys AS 
SELECT DISTINCT norm_isbn, norm_title, qual, bibid
FROM m_dedupe.match_keys;

DELETE FROM m_dedupe.match_keys;
INSERT INTO m_dedupe.match_keys SELECT * FROM uniq_match_keys;

-- find highest-quality match keys
CREATE TABLE m_dedupe.lead_quals AS
SELECT max(qual) as max_qual, norm_isbn, norm_title
FROM m_dedupe.match_keys
GROUP BY norm_isbn, norm_title
HAVING COUNT(*) > 1;

CREATE INDEX norm_idx2 ON m_dedupe.lead_quals(norm_isbn, norm_title);
CREATE INDEX norm_qual_idx2 ON m_dedupe.lead_quals(norm_isbn, norm_title, max_qual);

-- identify prospective lead bibs

--start a table with a count of 0 in order to include bibs that have 
--no copies but still need to have something in the asset.call_number table (hopefully 856 lines ##URI##)
CREATE TABLE m_dedupe.prospective_leads AS
SELECT bibid, a.norm_isbn, a.norm_title, b.max_qual, 0 as copy_count
FROM m_dedupe.match_keys a
JOIN m_dedupe.lead_quals b on (a.qual = b.max_qual and a.norm_isbn = b.norm_isbn and a.norm_title = b.norm_title)
JOIN asset.call_number acn on (acn.record = bibid)
--JOIN asset.copy ac on (ac.call_number = acn.id)
WHERE not acn.deleted
--and not ac.deleted
GROUP BY bibid, a.norm_isbn, a.norm_title, b.max_qual;

-- now populate the counts and 0 for no items (instead of null which is why so my subqueries)

update m_dedupe.prospective_leads mdpl set copy_count = (case when 
		(select (case when count is null then 0 else count end) as count from(
			select bib as bibid, count from
			(
				select (select record from asset.call_number where id = a.id) as "bib",count from 
				(
					select ac.call_number as "id",count(*) as "count" from asset.copy ac
					WHERE ac.call_number in (select call_number from asset.call_number acn where record in (
					select bibid from m_dedupe.prospective_leads))
					group by ac.id
				) as a
			) as b
		) as d
	where bibid=mdpl.bibid) is null then 0 else (select (case when count is null then 0 else count end) as count from(
			select bib as bibid, count from
			(
				select (select record from asset.call_number where id = a.id) as "bib",count from 
				(
					select ac.call_number as "id",count(*) as "count" from asset.copy ac
					WHERE ac.call_number in (select call_number from asset.call_number acn where record in (
					select bibid from m_dedupe.prospective_leads))
					group by ac.id
				) as a
			) as b
		) as d
	where bibid=mdpl.bibid) end);

-- and use number of copies to break ties
CREATE TABLE m_dedupe.best_lead_keys AS
SELECT norm_isbn, norm_title, max_qual, max(copy_count) AS copy_count
FROM m_dedupe.prospective_leads
GROUP BY norm_isbn, norm_title, max_qual;

CREATE TABLE m_dedupe.best_leads AS
SELECT bibid, a.norm_isbn, a.norm_title, a.max_qual, copy_count
FROM m_dedupe.best_lead_keys a
JOIN m_dedupe.prospective_leads b USING (norm_isbn, norm_title, max_qual, copy_count);

-- and break any remaining ties using the lowest bib ID as the winner
CREATE TABLE m_dedupe.unique_leads AS
SELECT MIN(bibid) AS lead_bibid, norm_isbn, norm_title, max_qual
FROM m_dedupe.best_leads
GROUP BY norm_isbn, norm_title, max_qual;

-- start computing the merge map
CREATE TABLE m_dedupe.merge_map_pre
AS SELECT distinct lead_bibid, bibid as sub_bibid 
FROM m_dedupe.unique_leads
JOIN m_dedupe.match_keys using (norm_isbn, norm_title)
WHERE lead_bibid <> bibid;

-- and resolve transitive maps
UPDATE m_dedupe.merge_map_pre a
SET lead_bibid = b.lead_bibid
FROM m_dedupe.merge_map_pre b
WHERE a.lead_bibid = b.sub_bibid;

UPDATE m_dedupe.merge_map_pre a
SET lead_bibid = b.lead_bibid
FROM m_dedupe.merge_map_pre b
WHERE a.lead_bibid = b.sub_bibid;

UPDATE m_dedupe.merge_map_pre a
SET lead_bibid = b.lead_bibid
FROM m_dedupe.merge_map_pre b
WHERE a.lead_bibid = b.sub_bibid;

-- and produce the final merge map
CREATE TABLE m_dedupe.merge_map
AS SELECT min(lead_bibid) as lead_bibid, sub_bibid
FROM m_dedupe.merge_map_pre
GROUP BY sub_bibid;

-- Add some columns making for easy queries to pass the corrisponding xml to the melt856s
ALTER TABLE m_dedupe.merge_map ADD COLUMN lead_marc TEXT, ADD COLUMN sub_marc TEXT;
-- Fill the new columns with the marc xml from record_entry
UPDATE m_dedupe.merge_map SET lead_marc = (SELECT marc FROM biblio.record_entry where id=lead_bibid);
UPDATE m_dedupe.merge_map SET sub_marc = (SELECT marc FROM biblio.record_entry where id=sub_bibid);


-- Wipe out all of the 856 data because we are about to replace it all with merged $u $z $9 info
DELETE FROM asset.uri_call_number_map WHERE call_number in 
(
	SELECT id from asset.call_number WHERE record in
	(SELECT lead_bibid from m_dedupe.merge_map) AND label = '##URI##'
);

DELETE FROM asset.uri_call_number_map WHERE call_number in 
(
	SELECT id from asset.call_number WHERE record in
	(SELECT sub_bibid from m_dedupe.merge_map) AND label = '##URI##'
);

DELETE FROM asset.uri WHERE id not in
(
	SELECT uri FROM asset.uri_call_number_map
);

DELETE FROM asset.call_number WHERE record in
	(SELECT lead_bibid from m_dedupe.merge_map) AND label = '##URI##';
	
DELETE FROM asset.call_number WHERE record in
	(SELECT sub_bibid from m_dedupe.merge_map) AND label = '##URI##';


-- Create a trigger to fire when the marc xml is updated
-- This will update the m_dedupe.merge_map.lead_xml and m_dedupe.merge_map.sub_xml
-- which will be nice when there are many to one merges	
CREATE TRIGGER updateboth AFTER UPDATE ON biblio.record_entry
    FOR EACH ROW EXECUTE PROCEDURE updateboth();
	

-- add a unique ID to the merge map so that
-- we can do the actual record merging in chunks
ALTER TABLE m_dedupe.merge_map ADD COLUMN id serial, ADD COLUMN done BOOLEAN DEFAULT FALSE;


-- Activate the 2 marc update functions
-- This will update the marc xml on both soon-to-be-deleted records and the winning record

SELECT * FROM 
(SELECT m_dedupe.update_lead(
mm.id,mm.lead_bibid)
from m_dedupe.merge_map mm) as a;


-- Perhaps this is not required because this is supposedly the soon-to-be-deleted record
-- But just for assurance! But at a cost of time!
SELECT * FROM 
(SELECT m_dedupe.update_sub(
mm.id,mm.sub_bibid)
from m_dedupe.merge_map mm) as a;
-- Get rid of the trigger because we only needed it for the updating marc xml
DROP FUNCTION m_dedupe.updateboth() CASCADE;

	

-- and here's an example of processing a chunk of a 1000
-- merges
SELECT asset.merge_record_assets(lead_bibid, sub_bibid)
FROM m_dedupe.merge_map WHERE id in (
  SELECT id FROM m_dedupe.merge_map
  WHERE done = false
  ORDER BY id
  LIMIT 1000
);

UPDATE m_dedupe.merge_map set done = true
WHERE id in (
  SELECT id FROM m_dedupe.merge_map
  WHERE done = false
  ORDER BY id
  LIMIT 1000
);

