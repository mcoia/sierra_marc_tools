#!/usr/bin/perl

use lib qw(.);
use Loghandler;
use Mobiusutil;
use Data::Dumper;
use XML::Simple;
use XML::TreeBuilder;
use Getopt::Long;
use DBhandler;
use File::Path qw(make_path);

my $xmlconf = "/openils/conf/opensrf.xml";
our $schema;
our $doDB;
our $mobUtil = new Mobiusutil();
our $log;
our $dbHandler;
our $configFile;
our $loginvestigationoutput;
our $sierradbHandler;
our $sample;
our @columns;
our @allRows;
our @previousLocs = ('');
our %fileHandles = ();
our %conf;


my $xmlconf = "/openils/conf/opensrf.xml";
GetOptions (
"config=s" => \$configFile,
"sample=s" => \$sample,
"xmlconfig=s" => \$xmlconf,
"schema=s" => \$schema,
"doDB" => \$doDB,
)
or die("Error in command line arguments\nYou can specify
--config configfilename (required)
--sample (number of rows to fetch eg --sample 100)
\n");

my $conf = $mobUtil->readConfFile($configFile);

if($conf)
{
	%conf = %{$conf};
	$logFile = $conf{"logfile"}
}
else
{
    print "Please specify a config file\n";
	exit;
}
if(!$logFile)
{
	print "Please specify a log file\n";
	exit;
}

$log = new Loghandler($logFile);
# $log->truncFile("");
$log->addLogLine(" ---------------- Script Starting ---------------- ");

my @dbUsers = @{$mobUtil->makeArrayFromComma($conf{"dbuser"})};
my @dbPasses = @{$mobUtil->makeArrayFromComma($conf{"dbpass"})};
if(scalar @dbUsers != scalar @dbPasses)
{
    print "Sorry, you need to provide DB usernames equal to the number of DB passwords\n";
    exit;
}

$sierradbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},@dbUsers[0],@dbPasses[0],$conf{"port"});

my %dbconf = %{getDBconnects($xmlconf)};
$dbHandler = new DBhandler($dbconf{"db"},$dbconf{"dbhost"},$dbconf{"dbuser"},$dbconf{"dbpass"},$dbconf{"port"});

$dbHandler->query("drop schema $schema cascade") if $doDB;
$dbHandler->query("create schema $schema") if $doDB;
make_path($conf->{"marcoutdir"},
{
    chmod => 0777,
}) if(!(-e $conf->{"marcoutdir"}));


  #get itype meanings
	my $query = "select * from sierra_view.itype_property_myuser";
	setupEGTable($query,"itype_property_myuser", 1);

	#get patron types
	my $query = "select * from sierra_view.ptype_property_myuser";
	setupEGTable($query,"ptype_property_myuser", 1);

	#get patron types
	my $query = "select * from sierra_view.user_defined_pcode1_myuser";
	setupEGTable($query,"user_defined_pcode1_myuser", 1);

	#get patron types
	my $query = "select * from sierra_view.user_defined_pcode2_myuser";
	setupEGTable($query,"user_defined_pcode2_myuser", 1);

	#get patron types
	my $query = "select * from sierra_view.user_defined_pcode3_myuser";
	setupEGTable($query,"user_defined_pcode3_myuser", 1);

    #get Item Status codes
	my $query = "select * from sierra_view.item_status_property_myuser";
	setupEGTable($query,"item_status_property_myuser", 1);

    #get Item material types
	my $query = "select * from sierra_view.material_property_myuser";
	setupEGTable($query,"material_property_myuser", 1);

    #get Item material types
	my $query = "select * from sierra_view.material_property_name";
	setupEGTable($query,"material_property_name", 1);

    #get user_defined_bcode1_myuser
	my $query = "select * from sierra_view.user_defined_bcode1_myuser";
	setupEGTable($query,"user_defined_bcode1_myuser", 1);

    #get user_defined_bcode2_myuser
	my $query = "select * from sierra_view.user_defined_bcode2_myuser";
	setupEGTable($query,"user_defined_bcode2_myuser", 1);

    #get user_defined_bcode3_myuser
	my $query = "select * from sierra_view.user_defined_bcode3_myuser";
	setupEGTable($query,"user_defined_bcode3_myuser", 1);

my $ctagportion = getCtagQueryPortion();
my $callnumPortion = getCallNumberPortion();
my $FOLIOMapSQL = getLocationSQLMap();
my @sp = @{getLocationCodes()};
my $firstrun = 1;

foreach(@sp)
{
    my $thisLoc = $_;
    my $institutionName = getFOLIOInstitution($thisLoc);

    my $sierralocationcodes="brbl.LOCATION_CODE=\$\$$thisLoc\$\$";
    my $sierrapreviouslocationcodes = "";
    $sierrapreviouslocationcodes .= "\$\$$_\$\$," foreach(@previousLocs);
    $sierrapreviouslocationcodes = substr($sierrapreviouslocationcodes,0,-1);


    my $patronlocationcodes = $sierralocationcodes;
    $patronlocationcodes =~ s/brbl\.LOCATION_CODE/home_library_code/g;

    shift @previousLocs if $firstrun; # remove the 0-byte string from the beginning of the array
    push @previousLocs, $thisLoc;

    print $conf{"libraryname"} . " - $thisLoc: $institutionName\n";


  #get location/branches
	my $query = "
		select * from
(
select svl.code as location_code,svl.is_public,svl.is_requestable,svln.name as location_name,svb.address,svb.code_num,svbm.name as branch_name from
sierra_view.location svl,
sierra_view.location_name svln,
sierra_view.branch svb,
sierra_view.branch_myuser svbm
where
svbm.code=svb.code_num and
svb.code_num=svl.branch_code_num and
svln.location_id=svl.id
)
as brbl
where
($sierralocationcodes)
	";
	setupEGTable($query,"location_branch_info", $firstrun);

    # FOLIO Item File unsuppressed
    my $query = getFOLIOItemQuery('false');

    my $t = $sierralocationcodes;
    $t =~ s/^brbl/item2/g;
    $query =~ s/!!!sierralocationcodes!!!/$t/g;
    # $query =~ s/!!ctag_portion!!/$ctagportion/g;
    $query =~ s/!!ctag_portion!!//g;
    $query =~ s/!!callnum_portion!!/$callnumPortion/g;

    setupEGTable($query, $institutionName . ".unsuppressed_folio_items", $firstrun);

    # FOLIO Item File suppressed
    my $query = getFOLIOItemQuery('true');

    $query =~ s/!!!sierralocationcodes!!!/$t/g;
    # $query =~ s/!!ctag_portion!!/$ctagportion/g;
    $query =~ s/!!ctag_portion!!//g;
    $query =~ s/!!callnum_portion!!/$callnumPortion/g;

    setupEGTable($query, $institutionName . ".suppressed_folio_items", $firstrun);

    #FOLIO Patron File
    my $query =<<'splitter';

 select
concat('p', patron.record_num) "patron_num",

-- Names
regexp_replace(
regexp_replace(regexp_replace(string_agg(pname.last_name,'!delim!' ORDER BY pname.display_order),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"last_name",


regexp_replace(
regexp_replace(regexp_replace(string_agg(pname.first_name,'!delim!' ORDER BY pname.id),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"first_name",

regexp_replace(
regexp_replace(regexp_replace(string_agg(pname.middle_name,'!delim!' ORDER BY pname.id),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"middle_name",

patron.barcode,

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pvisibleid.field_content,'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"visible_patron_id",

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pphone.phone_number,'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"phone_number",

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pemail.field_content,'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"email",
patron.ptype_code,
patron.home_library_code,
patron.expiration_date_gmt,
patron.pcode1,
patron.pcode2,
patron.pcode3,
patron.pcode4,
patron.birth_date_gmt,
patron.mblock_code,
patron.block_until_date_gmt,
patron.checkout_total,
patron.renewal_total,
patron.checkout_count,
patron.patron_message_code,
patron.highest_level_overdue_num,
patron.claims_returned_total,
patron.owed_amt,
patron.itema_count,
patron.itemb_count,
patron.overdue_penalty_count,
patron.ill_checkout_total,
patron.debit_amt,
patron.itemc_count,
patron.itemd_count,
patron.activity_gmt,
patron.notification_medium_code,
patron.registration_count,
patron.registration_total,
patron.attendance_total,
patron.waitlist_count,
patron.is_reading_history_opt_in,

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pnote.field_content,'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"notes",

pmetarecord.creation_date_gmt,
pmetarecord.deletion_date_gmt,
pmetarecord.campus_code,
pmetarecord.record_last_updated_gmt,
pmetarecord.previous_last_updated_gmt,

-- Address
paddress.patron_record_address_type_id,
paddress.addr1,
paddress.addr2,
paddress.addr3,
paddress.village,
paddress.city,
paddress.region,
paddress.postal_code,
paddress.country,

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pexternalid.field_content,'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"external_id"


from
sierra_view.patron_view patron
join sierra_view.record_metadata pmetarecord on(pmetarecord.id=patron.id and pmetarecord.record_type_code='p')
left join sierra_view.patron_record_fullname pname on(pname.patron_record_id=patron.id)
left join sierra_view.varfield_view pemail on(pemail.record_type_code='p' and pemail.field_content~'[^@]+@[^\.]+\.\D{2,}' and pemail.record_id=patron.id)
left join sierra_view.patron_record_phone pphone on(pphone.patron_record_id=patron.id)
left join sierra_view.varfield_view pnote on(pnote.varfield_type_code='x' and pnote.record_id=patron.id)
left join sierra_view.varfield_view pvisibleid on(pvisibleid.varfield_type_code='u' and pvisibleid.record_id=patron.id)
left join sierra_view.varfield_view pexternalid on(pexternalid.varfield_type_code='e' and pexternalid.record_id=patron.id)
left join (select

-- Address section
patron_record_id,
regexp_replace(
regexp_replace(string_agg(patron_record_address_type_id::text,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"patron_record_address_type_id",

regexp_replace(
regexp_replace(string_agg(addr1,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"addr1",
regexp_replace(
regexp_replace(string_agg(addr2,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"addr2",

regexp_replace(
regexp_replace(string_agg(addr3,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"addr3",

regexp_replace(
regexp_replace(string_agg(village,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"village",

regexp_replace(
regexp_replace(string_agg(city,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"city",

regexp_replace(
regexp_replace(string_agg(region,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"region",

regexp_replace(
regexp_replace(string_agg(postal_code,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"postal_code",

regexp_replace(
regexp_replace(string_agg(country,'!delim!' order by display_order),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"country"
from
sierra_view.patron_record_address paddress_internal
group by patron_record_id
) as paddress on (paddress.patron_record_id=patron.id)

where
!!!patronlocationcodes!!!
group by 1,5,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,41,42,43,44,45,46,47,48,49,50,51,52,53,54

splitter

    my $t = "patron.$patronlocationcodes";
    $query =~ s/!!!patronlocationcodes!!!/$t/g;
    setupEGTable($query, $institutionName . ".folio_patrons", $firstrun);

	#get patron checkouts between patron/item matching
	my $query =<<'splitter';

select
svc.id "checkout_id",
patron.barcode "patron_barcode",
concat('p', patron.record_num) "patron_num",
patron.ptype_code,
(case when map_folio_patron.newname is null then '!!!institutionName!!!' else map_folio_patron.newname end) "patron_home_library",
item.barcode "item_barcode",
item.location_code "item_location_code",
svc.checkout_gmt,
svc.due_gmt,
svc.renewal_count,
item.item_status_code,
(case when map_folio_item_service_loc.newname is null then 'MCO' else map_folio_item_service_loc.newname end) "checkout_service_point"
from
sierra_view.checkout svc
join sierra_view.patron_view patron on(patron.id=svc.patron_record_id)
join sierra_view.item_view item on(item.id=svc.item_record_id)
left join sierra_view.statistic_group svsg on(svsg.code_num=item.checkout_statistic_group_code_num)
left join (!!!sierra_folio_location_map!!!) as map_folio_patron on(map_folio_patron.oldname=patron.home_library_code)
left join (!!!sierra_folio_location_map!!!) as map_folio_item on(map_folio_item.oldname=item.location_code)
left join (!!!sierra_folio_location_map!!!) as map_folio_item_service_loc on(map_folio_item_service_loc.oldname=svsg.location_code)
where
svc.patron_record_id in
(
select id from sierra_view.patron_view where (!!!patronlocationcodes!!!)
) AND
(case when map_folio_patron.newname is null then 'MCO' else map_folio_patron.newname end)
=
(case when map_folio_item.newname is null then 'MCO' else map_folio_item.newname end)

splitter

    $query =~ s/!!!patronlocationcodes!!!/$patronlocationcodes/g;
    $query =~ s/!!!institutionName!!!/$institutionName/g;
	$query =~ s/!!!sierra_folio_location_map!!!/$FOLIOMapSQL/g;
    setupEGTable($query, $institutionName . ".matching_circ.folio_checkouts", $firstrun);

	#get patron checkouts between patron/item matching
	my $query =<<'splitter';

select
svc.id "checkout_id",
concat('i', item.record_num) "legacy_item_id",
item.barcode "item_barcode",
(case when map_folio_patron.newname is null then '!!!institutionName!!!' else map_folio_patron.newname end) "patron_home_library",
(case when map_folio_item.newname is null then '!!!institutionName!!!' else map_folio_item.newname end) "item_checkout_library",
concat('p', patron.record_num) "patron_num",
patron.barcode "patron_barcode",
svc.checkout_gmt,
svc.due_gmt,
(case when map_folio_item_service_loc.newname is null then 'MCO' else map_folio_item_service_loc.newname end) "checkout_service_point"
from
sierra_view.checkout svc
join sierra_view.patron_view patron on(patron.id=svc.patron_record_id)
join sierra_view.item_view item on(item.id=svc.item_record_id)
left join sierra_view.statistic_group svsg on(svsg.code_num=item.checkout_statistic_group_code_num)
left join (!!!sierra_folio_location_map!!!) as map_folio_patron on(map_folio_patron.oldname=patron.home_library_code)
left join (!!!sierra_folio_location_map!!!) as map_folio_item on(map_folio_item.oldname=item.location_code)
left join (!!!sierra_folio_location_map!!!) as map_folio_item_service_loc on(map_folio_item_service_loc.oldname=svsg.location_code)
where
svc.patron_record_id in
(
select id from sierra_view.patron_view where (!!!patronlocationcodes!!!)
) AND
(case when map_folio_patron.newname is null then 'MCO' else map_folio_patron.newname end)
!=
(case when map_folio_item.newname is null then 'MCO' else map_folio_item.newname end)

splitter

    $query =~ s/!!!patronlocationcodes!!!/$patronlocationcodes/g;
    $query =~ s/!!!institutionName!!!/$institutionName/g;
	$query =~ s/!!!sierra_folio_location_map!!!/$FOLIOMapSQL/g;
    setupEGTable($query, $institutionName . ".nonmatching_circ.folio_checkouts", $firstrun);

	#get holds
	my $query =<<'splitter';

select
holds.id,
holds.placed_gmt,
holds.is_frozen,
holds.expires_gmt,
holds.is_ir,
holds.is_ill,
holds.note,
svrv.record_type_code "held_record_type",
svrv.record_num "generic_record_num",
(case when map_folio_pickup_loc.newname is null then '' else map_folio_pickup_loc.newname end) "pickup_loc",
(case when map_folio_ir_pickup_loc.newname is null then '' else map_folio_ir_pickup_loc.newname end) "innreach_pickup_loc",
(case when item.record_num is null then '' else concat('i', item.record_num) end) "legacy_item_id",
item.barcode "item_barcode",
(case when bib.record_num is null then '' else concat('b', bib.record_num) end) "bib_record",
concat('p', patron.record_num) "patron_num",
patron.barcode "patron_barcode",
holds.on_holdshelf_gmt,
holds.expire_holdshelf_gmt
from
sierra_view.hold holds
join sierra_view.patron_view patron on(patron.id=holds.patron_record_id)
join sierra_view.record_metadata svrv on(svrv.id=holds.record_id)
left join sierra_view.item_view item on(item.id=holds.record_id)
left join sierra_view.bib_view bib on(bib.id=holds.record_id)
left join (!!!sierra_folio_location_map!!!) as map_folio_pickup_loc on(map_folio_pickup_loc.oldname=holds.pickup_location_code)
left join (!!!sierra_folio_location_map!!!) as map_folio_ir_pickup_loc on(map_folio_ir_pickup_loc.oldname=holds.ir_pickup_location_code)
where
holds.patron_record_id in
(
select id from sierra_view.patron_view where (!!!patronlocationcodes!!!)
)

splitter

    $query =~ s/!!!patronlocationcodes!!!/$patronlocationcodes/g;
    $query =~ s/!!!institutionName!!!/$institutionName/g;
	$query =~ s/!!!sierra_folio_location_map!!!/$FOLIOMapSQL/g;
    setupEGTable($query, $institutionName . ".folio_holds", $firstrun);

	# get fines
	my $query =<<'splitter';
select
fines.id "fine_id",
fines.invoice_num "invoice_id",
fines.item_charge_amt,
fines.processing_fee_amt,
fines.billing_fee_amt,
item.barcode "item_barcode",
(case when item.record_num is null then '' else concat('i', item.record_num) end) "legacy_item_id",
charge_code_mapping.charge_code_word "charge_code",
(case when map_folio_charge_loc.newname is null then 'MCO' else map_folio_charge_loc.newname end) "charge_location",
fines.assessed_gmt
from
sierra_view.fine fines
join sierra_view.patron_view patron on(patron.id=fines.patron_record_id)
left join
(
select '1' "charge_code", 'manual charge' "charge_code_word" union all
select '2' "charge_code", 'overdue' "charge_code_word" union all
select '3' "charge_code", 'replacement' "charge_code_word" union all
select '4' "charge_code", 'adjustment (OVERDUEX)' "charge_code_word" union all
select '5' "charge_code", 'lost book' "charge_code_word" union all
select '6' "charge_code", 'overdue renewed' "charge_code_word" union all
select '7' "charge_code", 'rental' "charge_code_word" union all
select '8' "charge_code", 'rental adjustment (RENTALX)' "charge_code_word" union all
select '9' "charge_code", 'notice' "charge_code_word" union all
select 'a' "charge_code", 'manual charge' "charge_code_word" union all
select 'b' "charge_code", 'credit card' "charge_code_word" union all
select 'p' "charge_code", 'program (i.e., Program Registration)' "charge_code_word"
) charge_code_mapping on (charge_code_mapping.charge_code_word = fines.charge_code)
left join (!!!sierra_folio_location_map!!!) as map_folio_charge_loc on(map_folio_charge_loc.oldname=fines.charge_location_code)
left join sierra_view.item_view item on(item.id=fines.item_record_metadata_id)
where
fines.patron_record_id in
(
select id from sierra_view.patron_view where (!!!patronlocationcodes!!!)
)

splitter

    $query =~ s/!!!patronlocationcodes!!!/$patronlocationcodes/g;
    $query =~ s/!!!institutionName!!!/$institutionName/g;
	$query =~ s/!!!sierra_folio_location_map!!!/$FOLIOMapSQL/g;
    setupEGTable($query, $institutionName . ".folio_fines", $firstrun);

	$firstrun = 0;
    while ( (my $filename, my $fhandle) = each(%fileHandles) )
    {
        # print "closing $filename\n";
        close($fhandle);
        open($fhandle, '>> '.$filename);
        binmode($fhandle, ":utf8");
    }
}

# make the final closure of the file handles
while ( (my $filename, my $fhandle) = each(%fileHandles) )
{
    print "closing $filename\n";
    close($fhandle);
}
	$log->addLogLine(" ---------------- Script End ---------------- ");

sub getFOLIOItemQuery
{
    my $suppressed = shift || 'false';
    my $query =<<'splitter';
select
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct 'b'||bib.record_num,'!delim!' order by 'b'||bib.record_num),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"bib_ids",
concat('i', item.record_num) "record_num", --RECORD #(Item)
-- item_prop.call_number "item_call_no", --CALL #(Item)
-- regexp_replace(
-- regexp_replace(regexp_replace(string_agg(distinct btrim(regexp_replace(item_prop.call_number,'\|.',' ','g')),'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
-- '!delim!!delim!','!delim!','g') "call_number",

-- bib_call_k.subk as "bib_call_sub_k", --CALL #(Bibliographic)
coalesce(item.barcode, (CASE WHEN svv_item_barcode.field_content IS NULL THEN NULL ELSE btrim(svv_item_barcode.field_content) END)) "barcode",
item.icode1,
item.icode2,
item.itype_code_num,
item.location_code,
item.item_status_code,
item.price,
item.last_checkin_gmt,
item.inventory_gmt,
item.checkout_total,
item.renewal_total,
item.last_year_to_date_checkout_total,
item.year_to_date_checkout_total,
item.copy_num,
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct item_volume.field_content,'!delim!' ),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"volume",
item.use3_count,
item.last_checkout_gmt,
item.internal_use_count,
item.copy_use_count,
item.item_message_code,
item.opac_message_code,
item.holdings_code,
item.is_suppressed,
item.last_year_to_date_checkout_total,
item.record_creation_date_gmt,
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct item_message.field_content,'!delim!' ),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"message",
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct internal_item_note.note,'!delim!' ),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g') "internal_note",
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct public_item_note.note,'!delim!' ),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g') "public_note",

string_agg(item_ctag.marc_tag,' ') "call_num_index",

!!callnum_portion!!

-- !!ctag_portion!!
-- string_agg(distinct item_ctag.field_content,';')

from

(select * from sierra_view.item_view item2 where is_suppressed is !!!suppressed!!! and !!!sierralocationcodes!!! !!orderlimit!! ) item
join sierra_view.bib_record_item_record_link bib_item_link on ( bib_item_link.item_record_id = item.id)
join sierra_view.bib_view bib on ( bib.id = bib_item_link.bib_record_id )
join sierra_view.record_metadata metarecord on(metarecord.id=item.id)
left join sierra_view.varfield svv_item_barcode on ( svv_item_barcode.varfield_type_code='b' and svv_item_barcode.marc_tag is null and btrim(svv_item_barcode.field_content) !='' and item.id=svv_item_barcode.record_id )
left join sierra_view.varfield svv on
    (
        svv.record_id = bib_item_link.bib_record_id and
        svv.marc_tag='001' and
        (
        svv.field_content~*'ebc' or
        svv.field_content~*'emoe' or
        svv.field_content~*'ewlebc' or
        svv.field_content~*'fod' or
        svv.field_content~*'jstor' or
        svv.field_content~*'jstoreba' or
        svv.field_content~*'kan' or
        svv.field_content~*'lccsd' or
        svv.field_content~*'lusafari' or
        svv.field_content~*'park' or
        svv.field_content~*'ruacls' or
        svv.field_content~*'safari' or
        svv.field_content~*'sage' or
        svv.field_content~*'xrc' or
        svv.field_content~*'odn' or
        svv.field_content~*'emoeir' or
        svv.field_content~*'ebr' or
        svv.field_content~*'ruacls' or
        svv.field_content~*'asp'
        )
    )
-- left join (
-- select
-- regexp_replace(
-- regexp_replace(regexp_replace(string_agg(distinct btrim(regexp_replace(call_number,'\|.',' ','g')),'!delim!'),'\|.','!delim!','g'),'^!delim!','','g'),
-- '!delim!!delim!','!delim!','g') "call_number",item_record_id
--  from sierra_view.item_record_property group by 2
-- ) as "item_prop" on(item_prop.item_record_id=item.id)

left join sierra_view.item_record_property item_prop on(item_prop.item_record_id=item.id)

left join sierra_view.varfield_view item_message on(item_message.record_id = item.id and item_message.varfield_type_code='m' and item_message.marc_tag is null)

left join sierra_view.varfield_view item_ctag on(item_ctag.record_id = item.id and item_ctag.marc_tag!='999' and item_ctag.varfield_type_code='c')

left join (
select
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct item_note.field_content,'!delim!' ),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"note", record_id from sierra_view.varfield_view item_note where item_note.varfield_type_code in ('x') and item_note.marc_tag is null group by 2) internal_item_note on(internal_item_note.record_id = item.id )

left join (
select
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct item_note.field_content,'!delim!' ),'\|.','!delim!','g'),'^!delim!','','g'),
'!delim!!delim!','!delim!','g')
"note", record_id from sierra_view.varfield_view item_note where item_note.varfield_type_code in ('n') and item_note.marc_tag is null group by 2) public_item_note on(public_item_note.record_id = item.id )

left join sierra_view.varfield_view item_volume on(item_volume.record_id = item.id and item_volume.varfield_type_code = 'v' and item_volume.marc_tag is null)

-- left join (select item2.id, ('{'||string_agg(distinct bib_item_link2.bib_record_id::text,','::text)||'}')::bigint[] "bibarray" from sierra_view.item_view item2 join sierra_view.bib_record_item_record_link bib_item_link2 on ( bib_item_link2.item_record_id = item2.id) group by 1) bib_id_array on (bib_id_array.id=item.id)
-- left join (
-- 	select
-- 	btrim(
-- regexp_replace(
-- regexp_replace(regexp_replace(string_agg(distinct btrim(field_content),'!delim!' order by occ_num)
-- ,'\|k([^\|]*).*?','\1','g'),'^!delim!','','g'),
-- '!delim!!delim!','!delim!','g')
-- ) "subk",
-- 	record_id
-- 	from sierra_view.varfield_view bib_call where record_type_code='b' and marc_tag in( '050', '082', '086', '090', '092', '099' ) and field_content ~'\|k'  group by 2
-- ) as bib_call_k on(bib_call_k.record_id = any (bib_id_array.bibarray) )

-- when bib_call_sub_k is included
-- group by 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,20,21,22,23,24,25,26,27,28,29,31
-- when bib_call_sub_k is NOT included
-- group by 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,19,20,21,22,23,24,25,26,27,28,30
where
svv.record_id is null
group by 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,19,20,21,22,23,24,25,26,27
ORDER BY 1
splitter

    $query =~ s/!!!suppressed!!!/$suppressed/g;
    return $query;
}

sub getCtagQueryPortion
{
    # short circiut, this was for Vivian to debug the output
    return 0;
    my $template = <<'splitter';
(case when string_agg(regexp_replace(item_ctag.field_content,'.*?\|valplaceholder([^\|]*)\|?.*$','\1','g'),' - ') ~ '\|' then null else string_agg(distinct regexp_replace(item_ctag.field_content,'.*?\|valplaceholder([^\|]*)\|?.*$','\1','g'),' - ') end) "ctag_valplaceholder",
splitter

    my $query = <<'splitter';
select regexp_replace(val,'^(.).*','\1','g'),count(*)
from
(
select unnest(string_to_array(field_content,'|')) "val"
from
sierra_view.varfield_view item_ctag
where
item_ctag.marc_tag!='999' and
item_ctag.varfield_type_code='c' and
item_ctag.record_type_code='i'
) as a
where
a.val!=''
group by 1
splitter

    my $ret = '';
    my @results = @{$sierradbHandler->query($query)};
    foreach(@results)
    {
        my $row = $_;
        my @row = @{$row};
        my $thisVal = @row[0];
        $thisVal =~ s/[\t\s\\]*//g;
        if( length($thisVal) == 1)
        {
            $ret .= $template;
            $ret =~ s/valplaceholder/$thisVal/g;
        }
    }
    return $ret;
}

sub getCallNumberPortion
{
    my $template = <<'splitter';
(case when string_agg(distinct regexp_replace(item_ctag.field_content,'.*?\|valplaceholder([^\|]*)\|?.*$','\1','g'),' - ') ~ '\|' then null else btrim(string_agg(distinct regexp_replace(item_ctag.field_content,'.*?\|valplaceholder([^\|]*)\|?.*$','\1','g'),' - ')) end) "nameplaceholder"
splitter

    my @prefixLetters = ();
    my @suffixLetters = ();
    my %libraryCallnumMap =
    (
        'archway' =>
            {
                'prefix' => ['f']
            },
        'arthur' =>
            {
                'prefix' => ['f'],
                'suffix' => ['3']
            },
        'avalon' =>
            {
                'prefix' => ['f','k'],
                'suffix' => ['g']
            },
        'bridges' =>
            {
                'prefix' => ['k']
            },
        'explore' => {},
        'kctowers' =>
            {
                'prefix' => ['f','k']
            },
        'swan' =>
            {
                'prefix' => ['f']
            },
        'swbts' => {},
    );


    my @prefixes = ();
    my @suffixes = ();
    if($libraryCallnumMap{$conf{"libraryname"}})
    {
        @prefixes = @{$libraryCallnumMap{$conf{"libraryname"}}->{'prefix'}}
            if(ref $libraryCallnumMap{$conf{"libraryname"}}->{'prefix'} eq 'ARRAY');

        @suffixes = @{$libraryCallnumMap{$conf{"libraryname"}}->{'suffix'}}
            if(ref $libraryCallnumMap{$conf{"libraryname"}}->{'suffix'} eq 'ARRAY');
    }

    my $prefix = $template;
    if($#prefixes > -1)
    {
        my $prefixReg = '[';
        $prefixReg .= $_ foreach(@prefixes);
        $prefixReg .= ']';
        $prefix =~ s/valplaceholder/$prefixReg/g;
    }
    else
    {
        $prefix = 'null "call_num_prefix"';
    }
    $prefix =~ s/nameplaceholder/call_num_prefix/g;

    my $suffix = $template;
    if($#suffixes > -1)
    {
        my $suffixReg = '[';
        $suffixReg .= $_ foreach(@suffixes);
        $suffixReg .= ']';
        $suffix =~ s/valplaceholder/$suffixReg/g;
    }
    else
    {
        $suffix = 'null "call_num_suffix"';
    }
    $suffix =~ s/nameplaceholder/call_num_suffix/g;

    my @all = (@prefixes, @suffixes);
    # callnumber is composed of "the rest" of the fields, not defined by prefix and suffix
    my $callnum = "item_ctag.field_content";
    if($#all > -1)
    {
        my $thisval = pop @all;
        $callnum = <<'splitter';
            regexp_replace(item_ctag.field_content,'(.*?)\|placeholder[^\|]*(\|?.*)$','\1\2','g')
splitter
        $callnum =~ s/placeholder/$thisval/g;
        foreach(@all)
        {
            my $temp = <<'splitter';
            regexp_replace(previous, '(.*?)\|placeholder[^\|]*(\|?.*)$','\1\2','g')
splitter
            $temp =~ s/previous/$callnum/g;
            $callnum = $temp;
            $callnum =~ s/placeholder/$_/g;
        }
    }
    $callnum = "string_agg(distinct regexp_replace($callnum,'\\|.',' ','g'), ' ')";
    $callnum = "(case when $callnum ~ '^\\s*\$' then null else btrim($callnum)  end) \"call_number\"";


# in case I screwed up the logic above, this is what works
    # my $callnum = <<'splitter';
    # (case when string_agg( distinct
    # regexp_replace(
    # -- remove f
    # regexp_replace(item_ctag.field_content,'.*?\|f[^\|]*\|?.*$','','g'),
    # '\|.',' ','g'),' ') ~ '^\s*$' then null else string_agg(
    # regexp_replace(
    # -- return all other subfields, space delimited
    # regexp_replace(item_ctag.field_content,'.*?\|f[^\|]*\|?.*$','','g'),
    # '\|.',' ','g'),' ') end) "call_number",
# splitter

    return $prefix.",\n".$callnum.",\n".$suffix."\n";

}

sub institutionCodesToNames
{
    my %ret = ();
    my $query = <<'splitter';
select code,lower(name)
from
sierra_view.location svl
join sierra_view.location_name svln on(svln.location_id=svl.id)
order by 2
splitter

    my @results = @{$sierradbHandler->query($query)};
    foreach(@results)
    {
        my $row = $_;
        my @row = @{$row};
        my $code = @row[0];
        my $name = @row[1];
        $name =~ s/[\t\s\\',\.]*//g;
        $name = 'folio_items' if(length($name) == 0);
        $ret{$code} = $name;
    }
    return \%ret;
}

sub setupEGTable
{
	my $query = shift;
	my $tablename = shift;
    my $resetTable = shift;
    my $tabFile = $conf{'marcoutdir'} . "/$tablename.tsv";
    my $tabOutput = '';
    my $thisFhandle;
    $thisFhandle = $fileHandles{$tabFile} if ($fileHandles{$tabFile});
    # scrub non-postgres friendly characters
    $tablename =~ s/[\.\s\t\-]//g;

    my $insertChunkSize = 500;

    my @ret = @{getRemoteSierraData($query)};

	my @allRows = @{@ret[0]};
	my @cols = @{@ret[1]};

    my $fileExists = -e $tabFile;
    if(!$fileExists)
    {
        open($thisFhandle, '>> '.$tabFile);
        binmode($thisFhandle, ":utf8");
        $tabOutput .= $_."\t" for @cols;
        $tabOutput=substr($tabOutput,0,-1) . "\n";
        print $thisFhandle "$tabOutput";
        $tabOutput='';
    }

	#drop the table
	my $query = ""; "DROP TABLE IF EXISTS $schema.$tablename";

    if( $resetTable )
    {
        $query = "DROP TABLE IF EXISTS $schema.$tablename";
        $log->addLine($query);
        $dbHandler->update($query) if $doDB;

        #create the table
        $query = "CREATE TABLE $schema.$tablename (";
        $query.=$_." TEXT," for @cols;
        $query=substr($query,0,-1).")";
        $log->addLine($query);
        $dbHandler->update($query) if $doDB;
    }
    my @vals = ();
    my $valpos = 1;
    my $totalInserted = 0;

	if($#allRows > -1)
	{
        print "$tablename\texpecting $#allRows total row(s)\n";
		#insert the data
        my $rowcount = 0;
		$query = "INSERT INTO $schema.$tablename (";
		$query.=$_."," for @cols;
		$query=substr($query,0,-1).")\nVALUES\n";
        my $queryTemplate = $query;
		foreach(@allRows)
		{
			$query.="(";
			my @thisrow = @{$_};
			$query.= "\$" . $valpos++ . "," for(@thisrow);
            for(@thisrow)
            {
                $_ =~ s/\t/ /g;
                $tabOutput .= $_."\t";
            }
            push @vals, @thisrow;
			$query=substr($query,0,-1)."),\n";
            $tabOutput=substr($tabOutput,0,-1)."\n";
            $rowcount++;
            if($rowcount % $insertChunkSize == 0)
            {
                $totalInserted+=$insertChunkSize;
                $query=substr($query,0,-2)."\n";
                $loginvestigationoutput.="select count(*),$_ from $schema.$tablename group by $_ order by $_\n" for @cols;
                print "\t".$totalInserted." / $#allRows $schema.$tablename\n";
                # $log->addLine("Inserted ".$totalInserted." Rows into $schema.$tablename");
                $dbHandler->updateWithParameters($query, \@vals) if $doDB;
                $query = $queryTemplate;
                $rowcount=0;
                print $thisFhandle "$tabOutput";
                $tabOutput='';
                @vals = ();
                $valpos = 1;
            }
		}

        if($valpos > 1)
        {
            $query=substr($query,0,-2)."\n";
            $loginvestigationoutput.="select count(*),$_ from $schema.$tablename group by $_ order by $_\n" for @cols;
            print "\t".$#allRows." / $#allRows $schema.$tablename\n";
            $log->addLine("Inserted ".$#allRows." Rows into $schema.$tablename");
            $dbHandler->updateWithParameters($query, \@vals) if $doDB;
            print $thisFhandle "$tabOutput";
        }

	}

    $fileHandles{$tabFile} = $thisFhandle;
}

sub getRemoteSierraData
{
    my $queryTemplate = @_[0];
    my $offset = 0;
    my @ret = ();
    my $limit = 10000;
    $limit = $sample if $sample;
    if ($queryTemplate =~ /!!orderlimit!!/)
    {
        $queryTemplate =~ s/!!orderlimit!!/ORDER BY 1 LIMIT $limit OFFSET !OFFSET!/g ;
    }
    else
    {
        $queryTemplate.="\nORDER BY 1\n LIMIT $limit OFFSET !OFFSET!";
    }
    my $loops = 0;
    my @cols;
    my $data = 1;
    my @allRows = ();

    while($data)
    {
        my $query = $queryTemplate;
        $query =~ s/!OFFSET!/$offset/g;
        $log->addLine($query);
        my @theseRows = @{$sierradbHandler->query($query)};
        $data = 0 if($#theseRows < 0 );
        push @allRows, @theseRows if ($#theseRows > -1 );
        $loops++;
        $offset = ($loops * $limit);
        $data = 0 if $sample;
        undef @theseRows;
    }
    @cols = @{$sierradbHandler->getColumnNames()} if !(@cols);

    push @ret, [@allRows];
    push @ret, [@cols];
    return \@ret;
}

sub getLocationCodes
{
    my $query = <<'splitter';
select * from
(
	select code from sierra_view.location
	group by 1
	union all
	select location_code
	from
	sierra_view.bib_record_location
	group by 1
	union all
	select location_code
	from
	sierra_view.item_view
	group by 1
    union all
	select home_library_code
	from
	sierra_view.patron_view
	group by 1
) as a
group by 1
order by 1

splitter

    my @ret = ();
    my @results = @{$sierradbHandler->query($query)};
    foreach(@results)
    {
        my $row = $_;
        my @row = @{$row};
        push @ret, @row[0];
    }
    return \@ret;
}

sub calcCheckDigit
{
	my $seed =@_[1];
	$seed = reverse($seed);
	my @chars = split("", $seed);
	my $checkDigit = 0;
	for my $i (0.. $#chars)
	{
		$checkDigit += @chars[$i] * ($i+2);
	}
	$checkDigit =$checkDigit%11;
	if($checkDigit>9)
	{
		$checkDigit='x';
	}
	return $checkDigit;
}

sub getDBconnects
{
	my $openilsfile = @_[0];
	my $xml = new XML::Simple;
	my $data = $xml->XMLin($openilsfile);
	my %conf;
	$conf{"dbhost"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{host};
	$conf{"db"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{db};
	$conf{"dbuser"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{user};
	$conf{"dbpass"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{pw};
	$conf{"port"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{port};
	##print Dumper(\%conf);
	return \%conf;

}

sub locationNormalize_swbts
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
's4b' => 'SWBTS',
'sab' => 'SWBTS',
'sar' => 'SWBTS',
'sbaii' => 'SWBTS',
'sbb' => 'SWBTS',
'sbcii' => 'SWBTS',
'sbdii' => 'SWBTS',
'sbfii' => 'SWBTS',
'sbiii' => 'SWBTS',
'sbjii' => 'SWBTS',
'sbmii' => 'SWBTS',
'sbo1i' => 'SWBTS',
'sbo2i' => 'SWBTS',
'sbrii' => 'SWBTS',
'sbrri' => 'SWBTS',
'sbsii' => 'SWBTS',
'sbsoi' => 'SWBTS',
'sbtii' => 'SWBTS',
'sbvii' => 'SWBTS',
'sbxii' => 'SWBTS',
'sbxpi' => 'SWBTS',
'sbzii' => 'SWBTS',
'scb' => 'SWBTS',
'seb' => 'SWBTS',
'see' => 'SWBTS',
'seidi' => 'SWBTS',
'seiii' => 'SWBTS',
'semo0' => 'SWBTS',
'sgb' => 'SWBTS',
'shb' => 'SWBTS',
'shiii' => 'SWBTS',
'slb' => 'SWBTS',
'slbii' => 'SWBTS',
'smb' => 'SWBTS',
'sor' => 'SWBTS',
'spb' => 'SWBTS',
'sqb' => 'SWBTS',
'sraat' => 'SWBTS',
'srabi' => 'SWBTS',
'srabo' => 'SWBTS',
'sradg' => 'SWBTS',
'sradi' => 'SWBTS',
'sradm' => 'SWBTS',
'sradt' => 'SWBTS',
'sraee' => 'SWBTS',
'sraer' => 'SWBTS',
'sraes' => 'SWBTS',
'srafi' => 'SWBTS',
'sragi' => 'SWBTS',
'sragr' => 'SWBTS',
'srahi' => 'SWBTS',
'srali' => 'SWBTS',
'sraoi' => 'SWBTS',
'srapc' => 'SWBTS',
'srapi' => 'SWBTS',
'sraqi' => 'SWBTS',
'sraro' => 'SWBTS',
'srasi' => 'SWBTS',
'srasr' => 'SWBTS',
'srati' => 'SWBTS',
'srato' => 'SWBTS',
'sratr' => 'SWBTS',
'srawi' => 'SWBTS',
'srb' => 'SWBTS',
'srdii' => 'SWBTS',
'srfii' => 'SWBTS',
'sri2i' => 'SWBTS',
'sri3i' => 'SWBTS',
'sriji' => 'SWBTS',
'sriki' => 'SWBTS',
'sripd' => 'SWBTS',
'srixp' => 'SWBTS',
'srjbi' => 'SWBTS',
'srjci' => 'SWBTS',
'srjmi' => 'SWBTS',
'srmai' => 'SWBTS',
'srmii' => 'SWBTS',
'srmsi' => 'SWBTS',
'sroci' => 'SWBTS',
'srrii' => 'SWBTS',
'srs3i' => 'SWBTS',
'srxii' => 'SWBTS',
'ssb' => 'SWBTS',
'ssiii' => 'SWBTS',
'stb' => 'SWBTS',
'sub' => 'SWBTS',
'suiii' => 'SWBTS',
'swb' => 'SWBTS',
'swiii' => 'SWBTS',
  );
  return \%mapping;
  
}

sub locationNormalize_swan
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'tra' => 'COTT',
'traei' => 'COTT',
'traii' => 'COTT',
'trami' => 'COTT',
'travi' => 'COTT',
'trb' => 'COTT',
'trbec' => 'COTT',
'trbfi' => 'COTT',
'trbgi' => 'COTT',
'trbii' => 'COTT',
'trbji' => 'COTT',
'trbni' => 'COTT',
'trboi' => 'COTT',
'trbwi' => 'COTT',
'trbyi' => 'COTT',
'trc' => 'COTT',
'tre' => 'COTT',
'treki' => 'COTT',
'tri' => 'COTT',
'trj' => 'COTT',
'trjii' => 'COTT',
'trjyi' => 'COTT',
'trk' => 'COTT',
'trl' => 'COTT',
'trlci' => 'COTT',
'trm' => 'COTT',
'tro' => 'COTT',
'troki' => 'COTT',
'trp' => 'COTT',
'trpii' => 'COTT',
'trr' => 'COTT',
'trrbi' => 'COTT',
'trrhm' => 'COTT',
'trrii' => 'COTT',
'trryi' => 'COTT',
'trs' => 'COTT',
'tru' => 'COTT',
'truii' => 'COTT',
'trv' => 'COTT',
'trw' => 'COTT',
'trxd1' => 'COTT',
'trxd3' => 'COTT',
'trxd7' => 'COTT',
'trxh1' => 'COTT',
'trxh2' => 'COTT',
'trxh3' => 'COTT',
'trz' => 'COTT',
'cna' => 'CROW',
'cnaii' => 'CROW',
'cnb' => 'CROW',
'cnbfi' => 'CROW',
'cnbfm' => 'CROW',
'cnbii' => 'CROW',
'cnbmi' => 'CROW',
'cnbmo' => 'CROW',
'cnbni' => 'CROW',
'cnboi' => 'CROW',
'cnc' => 'CROW',
'cncii' => 'CROW',
'cne' => 'CROW',
'cneii' => 'CROW',
'cneri' => 'CROW',
'cnfii' => 'CROW',
'cnkii' => 'CROW',
'cnlap' => 'CROW',
'cnm' => 'CROW',
'cnmii' => 'CROW',
'cnnii' => 'CROW',
'cnp' => 'CROW',
'cnpvi' => 'CROW',
'cnr' => 'CROW',
'cnrci' => 'CROW',
'cnrii' => 'CROW',
'cnrmi' => 'CROW',
'cnrni' => 'CROW',
'cnrwi' => 'CROW',
'cns' => 'CROW',
'cnsii' => 'CROW',
'cnt' => 'CROW',
'cntji' => 'CROW',
'cnu' => 'CROW',
'cnuii' => 'CROW',
'cnuwi' => 'CROW',
'cnv' => 'CROW',
'cnvii' => 'CROW',
'cnvmi' => 'CROW',
'cnxii' => 'CROW',
'cnxvi' => 'CROW',
'cnzii' => 'CROW',
'dliii' => 'DU',
'doatl' => 'DU',
'dob' => 'DU',
'docdr' => 'DU',
'doedc' => 'DU',
'doeii' => 'DU',
'dofea' => 'DU',
'dofed' => 'DU',
'doflm' => 'DU',
'dogib' => 'DU',
'doill' => 'DU',
'doind' => 'DU',
'dojuv' => 'DU',
'dolaw' => 'DU',
'dolie' => 'DU',
'dom' => 'DU',
'domac' => 'DU',
'domic' => 'DU',
'domif' => 'DU',
'domus' => 'DU',
'donew' => 'DU',
'doove' => 'DU',
'doovo' => 'DU',
'doper' => 'DU',
'dopvl' => 'DU',
'dorar' => 'DU',
'dorea' => 'DU',
'doref' => 'DU',
'dospe' => 'DU',
'dospo' => 'DU',
'dospx' => 'DU',
'doxfa' => 'DU',
'doxpm' => 'DU',
'doxrf' => 'DU',
'dub' => 'DU',
'duiii' => 'DU',
'duwii' => 'DU',
'aga' => 'EU',
'agaac' => 'EU',
'agaat' => 'EU',
'agavd' => 'EU',
'agavv' => 'EU',
'agg' => 'EU',
'aggci' => 'EU',
'aggfi' => 'EU',
'aggfm' => 'EU',
'agmcg' => 'EU',
'agp' => 'EU',
'agpai' => 'EU',
'agpbi' => 'EU',
'agr' => 'EU',
'agref' => 'EU',
'ags' => 'EU',
'agsgi' => 'EU',
'agshy' => 'EU',
'agsmc' => 'EU',
'agsou' => 'EU',
'agu' => 'EU',
'agudi' => 'EU',
'aguii' => 'EU',
'aguwi' => 'EU',
'agxcr' => 'EU',
'agxst' => 'EU',
'ecg' => 'EU',
'ejr' => 'EU',
'ejrci' => 'EU',
'ejref' => 'EU',
'eua' => 'EU',
'euaar' => 'EU',
'eug' => 'EU',
'eugci' => 'EU',
'eugcm' => 'EU',
'eugeb' => 'EU',
'eugem' => 'EU',
'eui' => 'EU',
'euicl' => 'EU',
'euicu' => 'EU',
'euirc' => 'EU',
'eum' => 'EU',
'eumed' => 'EU',
'euo' => 'EU',
'euoer' => 'EU',
'eup' => 'EU',
'eupai' => 'EU',
'eur' => 'EU',
'eurcr' => 'EU',
'euref' => 'EU',
'eut' => 'EU',
'eutts' => 'EU',
'euu' => 'EU',
'euupr' => 'EU',
'euuwi' => 'EU',
'euw' => 'EU',
'msa' => 'MSSU',
'msabg' => 'MSSU',
'msacd' => 'MSSU',
'msack' => 'MSSU',
'msacr' => 'MSSU',
'msadv' => 'MSSU',
'msaeq' => 'MSSU',
'msajv' => 'MSSU',
'msaya' => 'MSSU',
'msb' => 'MSSU',
'mse' => 'MSSU',
'msebk' => 'MSSU',
'msg' => 'MSSU',
'msgbk' => 'MSSU',
'msgcd' => 'MSSU',
'msgdv' => 'MSSU',
'msgin' => 'MSSU',
'msgmf' => 'MSSU',
'msgmp' => 'MSSU',
'msgnc' => 'MSSU',
'msgps' => 'MSSU',
'msint' => 'MSSU',
'mslnc' => 'MSSU',
'mslot' => 'MSSU',
'msm' => 'MSSU',
'msmbk' => 'MSSU',
'msmbr' => 'MSSU',
'msmdv' => 'MSSU',
'msmie' => 'MSSU',
'msmis' => 'MSSU',
'msmna' => 'MSSU',
'msp' => 'MSSU',
'mspbd' => 'MSSU',
'mspbh' => 'MSSU',
'mspbm' => 'MSSU',
'mspej' => 'MSSU',
'msper' => 'MSSU',
'mspfh' => 'MSSU',
'mspfm' => 'MSSU',
'mspin' => 'MSSU',
'mspnp' => 'MSSU',
'msr' => 'MSSU',
'msrat' => 'MSSU',
'msrdo' => 'MSSU',
'msref' => 'MSSU',
'mss' => 'MSSU',
'mssar' => 'MSSU',
'msspe' => 'MSSU',
'mst' => 'MSSU',
'mstgn' => 'MSSU',
'mstnb' => 'MSSU',
'mstst' => 'MSSU',
'mstts' => 'MSSU',
'msu' => 'MSSU',
'msuwi' => 'MSSU',
'msx' => 'MSSU',
'msxcr' => 'MSSU',
'msxfr' => 'MSSU',
'msxmr' => 'MSSU',
'msxpc' => 'MSSU',
'msxpr' => 'MSSU',
'mszii' => 'MSSU',
'77ar2' => 'OCC',
'77av2' => 'OCC',
'77b' => 'OCC',
'77cp2' => 'OCC',
'77eq2' => 'OCC',
'77er0' => 'OCC',
'77jb2' => 'OCC',
'77jf2' => 'OCC',
'77jn2' => 'OCC',
'77mf1' => 'OCC',
'77new' => 'OCC',
'77pro' => 'OCC',
'77rb2' => 'OCC',
'77res' => 'OCC',
'77rf2' => 'OCC',
'77u' => 'OCC',
'77uwi' => 'OCC',
'7bio2' => 'OCC',
'7fic2' => 'OCC',
'7gen1' => 'OCC',
'7gen2' => 'OCC',
'7per1' => 'OCC',
'7swb2' => 'OCC',
'orb' => 'OTC',
'orbii' => 'OTC',
'orbni' => 'OTC',
'orboi' => 'OTC',
'orjii' => 'OTC',
'orpii' => 'OTC',
'orrii' => 'OTC',
'orrri' => 'OTC',
'orsii' => 'OTC',
'orvii' => 'OTC',
'orxii' => 'OTC',
'osb' => 'OTC',
'osbgn' => 'OTC',
'osbii' => 'OTC',
'osbnf' => 'OTC',
'osbni' => 'OTC',
'osboi' => 'OTC',
'oseei' => 'OTC',
'osfic' => 'OTC',
'oshot' => 'OTC',
'osjii' => 'OTC',
'osjni' => 'OTC',
'oslap' => 'OTC',
'ospdv' => 'OTC',
'ospii' => 'OTC',
'osrii' => 'OTC',
'ossii' => 'OTC',
'osu' => 'OTC',
'osuii' => 'OTC',
'osuwi' => 'OTC',
'osvii' => 'OTC',
'osxii' => 'OTC',
'osygn' => 'OTC',
'otb' => 'OTC',
'otbhs' => 'OTC',
'otblp' => 'OTC',
'otcbi' => 'OTC',
'otcli' => 'OTC',
'otcoi' => 'OTC',
'otcwi' => 'OTC',
'bbaii' => 'SBU',
'bbali' => 'SBU',
'bbb' => 'SBU',
'bbbii' => 'SBU',
'bbboi' => 'SBU',
'bbc' => 'SBU',
'bbcbi' => 'SBU',
'bbcii' => 'SBU',
'bbcki' => 'SBU',
'bbcmi' => 'SBU',
'bbcpo' => 'SBU',
'bbcri' => 'SBU',
'bbcsi' => 'SBU',
'bbcti' => 'SBU',
'bbeei' => 'SBU',
'bbemi' => 'SBU',
'bbf' => 'SBU',
'bbfci' => 'SBU',
'bbfii' => 'SBU',
'bbher' => 'SBU',
'bbj' => 'SBU',
'bbjii' => 'SBU',
'bbjoi' => 'SBU',
'bblac' => 'SBU',
'bbm' => 'SBU',
'bbmau' => 'SBU',
'bbmbd' => 'SBU',
'bbmci' => 'SBU',
'bbmcp' => 'SBU',
'bbmdd' => 'SBU',
'bbmdv' => 'SBU',
'bbmec' => 'SBU',
'bbmed' => 'SBU',
'bbmeh' => 'SBU',
'bbmei' => 'SBU',
'bbmel' => 'SBU',
'bbmeo' => 'SBU',
'bbmep' => 'SBU',
'bbmer' => 'SBU',
'bbmes' => 'SBU',
'bbmet' => 'SBU',
'bbmga' => 'SBU',
'bbmki' => 'SBU',
'bbmre' => 'SBU',
'bbmvc' => 'SBU',
'bbmvd' => 'SBU',
'bbnii' => 'SBU',
'bbnmi' => 'SBU',
'bbp' => 'SBU',
'bbpbi' => 'SBU',
'bbpfc' => 'SBU',
'bbpfi' => 'SBU',
'bbpli' => 'SBU',
'bbpnl' => 'SBU',
'bbpsi' => 'SBU',
'bbpst' => 'SBU',
'bbqui' => 'SBU',
'bbr' => 'SBU',
'bbrii' => 'SBU',
'bbroi' => 'SBU',
'bbs' => 'SBU',
'bbsbu' => 'SBU',
'bbsdc' => 'SBU',
'bbsii' => 'SBU',
'bbsmi' => 'SBU',
'bbspi' => 'SBU',
'bbu' => 'SBU',
'bbuii' => 'SBU',
'bbuwi' => 'SBU',
'bbxfi' => 'SBU',
'bbxii' => 'SBU',
'bbxmi' => 'SBU',
'bbxpe' => 'SBU',
'blb' => 'SBU',
'blbii' => 'SBU',
'blboi' => 'SBU',
'blcbi' => 'SBU',
'blcii' => 'SBU',
'blcki' => 'SBU',
'blcri' => 'SBU',
'bljii' => 'SBU',
'bljoi' => 'SBU',
'blmau' => 'SBU',
'blmci' => 'SBU',
'blmdd' => 'SBU',
'blmki' => 'SBU',
'blmvc' => 'SBU',
'blnii' => 'SBU',
'bmb' => 'SBU',
'bmbii' => 'SBU',
'bmboi' => 'SBU',
'bmcbi' => 'SBU',
'bmcii' => 'SBU',
'bmcri' => 'SBU',
'bmjii' => 'SBU',
'bmjoi' => 'SBU',
'bmmau' => 'SBU',
'bmmdd' => 'SBU',
'bmxpe' => 'SBU',
'bsb' => 'SBU',
'bsbii' => 'SBU',
'bsboi' => 'SBU',
'bse' => 'SBU',
'bsm' => 'SBU',
'bsmau' => 'SBU',
'bsmbd' => 'SBU',
'bsmcp' => 'SBU',
'bsmdd' => 'SBU',
'bsmdv' => 'SBU',
'bsmel' => 'SBU',
'bsmem' => 'SBU',
'bsmer' => 'SBU',
'bsmki' => 'SBU',
'bspbi' => 'SBU',
'bspli' => 'SBU',
'bspnl' => 'SBU',
'bsr' => 'SBU',
'bssmc' => 'SBU',
'bsxfi' => 'SBU',
'bsxii' => 'SBU',
'bsxmi' => 'SBU',
'bsxpe' => 'SBU',
  );
  return \%mapping;
  
}

sub locationNormalize_kctowers
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'avarr' => 'AU',
'avb' => 'AU',
'avcar' => 'AU',
'avcir' => 'AU',
'avcur' => 'AU',
'avelr' => 'AU',
'avequ' => 'AU',
'avgrl' => 'AU',
'avilc' => 'AU',
'avjuv' => 'AU',
'avnew' => 'AU',
'avpbd' => 'AU',
'avper' => 'AU',
'avpf1' => 'AU',
'avpf2' => 'AU',
'avpla' => 'AU',
'avpop' => 'AU',
'avpsr' => 'AU',
'avpst' => 'AU',
'avred' => 'AU',
'avref' => 'AU',
'avres' => 'AU',
'avrfi' => 'AU',
'avsdv' => 'AU',
'avspc' => 'AU',
'avspf' => 'AU',
'avspo' => 'AU',
'avspr' => 'AU',
'avu' => 'AU',
'avuii' => 'AU',
'avuwi' => 'AU',
'avvid' => 'AU',
'avwrc' => 'AU',
'tbb' => 'BC',
'tbibc' => 'BC',
'tbicl' => 'BC',
'tbict' => 'BC',
'tbids' => 'BC',
'tbifl' => 'BC',
'tbigv' => 'BC',
'tbiii' => 'BC',
'tbinc' => 'BC',
'tbiov' => 'BC',
'tbirp' => 'BC',
'tbirr' => 'BC',
'tblai' => 'BC',
'tblbi' => 'BC',
'tblfi' => 'BC',
'tblfo' => 'BC',
'tblni' => 'BC',
'tblpb' => 'BC',
'tblpi' => 'BC',
'tblrg' => 'BC',
'tblri' => 'BC',
'tblro' => 'BC',
'tblrr' => 'BC',
'tblrs' => 'BC',
'tblti' => 'BC',
'tblxi' => 'BC',
'tbmci' => 'BC',
'tbmfi' => 'BC',
'tbmmi' => 'BC',
'tbmui' => 'BC',
'tbneg' => 'BC',
'tbnei' => 'BC',
'tbnli' => 'BC',
'tbnsi' => 'BC',
'tbu' => 'BC',
'tbuwi' => 'BC',
'c1abi' => 'CNCPT',
'c1afi' => 'CNCPT',
'c1aii' => 'CNCPT',
'c1aoi' => 'CNCPT',
'c1api' => 'CNCPT',
'c1ayi' => 'CNCPT',
'c1b' => 'CNCPT',
'c1e' => 'CNCPT',
'c1eii' => 'CNCPT',
'c1emi' => 'CNCPT',
'c1ill' => 'CNCPT',
'c1k' => 'CNCPT',
'c1kii' => 'CNCPT',
'c1m' => 'CNCPT',
'c1mci' => 'CNCPT',
'c1mii' => 'CNCPT',
'c1p' => 'CNCPT',
'c1pmi' => 'CNCPT',
'c1r' => 'CNCPT',
'c1rii' => 'CNCPT',
'c1rsi' => 'CNCPT',
'c1s' => 'CNCPT',
'c1sai' => 'CNCPT',
'c1sii' => 'CNCPT',
'c1u' => 'CNCPT',
'c1udi' => 'CNCPT',
'c1uii' => 'CNCPT',
'c1uwi' => 'CNCPT',
'c1v' => 'CNCPT',
'c1vci' => 'CNCPT',
'c1vdi' => 'CNCPT',
'c1vli' => 'CNCPT',
'c1vni' => 'CNCPT',
'c1vvi' => 'CNCPT',
'c1vwi' => 'CNCPT',
'c1xii' => 'CNCPT',
'lbb' => 'CU',
'lbici' => 'CU',
'lbict' => 'CU',
'lbifi' => 'CU',
'lbiii' => 'CU',
'lbimc' => 'CU',
'lboii' => 'CU',
'lbpii' => 'CU',
'lbrgm' => 'CU',
'lbrii' => 'CU',
'lbrpi' => 'CU',
'lbsii' => 'CU',
'lbvii' => 'CU',
'lbxii' => 'CU',
'7ac' => 'KCAI',
'7acrr' => 'KCAI',
'7cs' => 'KCAI',
'7ja' => 'KCAI',
'7jarb' => 'KCAI',
'7jc' => 'KCAI',
'7jccs' => 'KCAI',
'7jcgn' => 'KCAI',
'7jcld' => 'KCAI',
'7jcnr' => 'KCAI',
'7jcow' => 'KCAI',
'7je' => 'KCAI',
'7jeej' => 'KCAI',
'7jefr' => 'KCAI',
'7jeii' => 'KCAI',
'7jj' => 'KCAI',
'7jjub' => 'KCAI',
'7jjus' => 'KCAI',
'7jm' => 'KCAI',
'7jm3h' => 'KCAI',
'7jm7d' => 'KCAI',
'7jmav' => 'KCAI',
'7jmci' => 'KCAI',
'7jmmo' => 'KCAI',
'7jmsv' => 'KCAI',
'7jmv2' => 'KCAI',
'7jq' => 'KCAI',
'7jr' => 'KCAI',
'7jrap' => 'KCAI',
'7jrbr' => 'KCAI',
'7jrcd' => 'KCAI',
'7jrdb' => 'KCAI',
'7jrds' => 'KCAI',
'7jrld' => 'KCAI',
'7jrow' => 'KCAI',
'7jrrd' => 'KCAI',
'7jrsi' => 'KCAI',
'7js' => 'KCAI',
'7jstb' => 'KCAI',
'7jt' => 'KCAI',
'7ju' => 'KCAI',
'7juwi' => 'KCAI',
'7jv' => 'KCAI',
'7jvaf' => 'KCAI',
'7jx12' => 'KCAI',
'7jx2d' => 'KCAI',
'7jxnd' => 'KCAI',
'8marc' => 'KCKCC',
'8mb' => 'KCKCC',
'8mcad' => 'KCKCC',
'8mcte' => 'KCKCC',
'8mdis' => 'KCKCC',
'8mgov' => 'KCKCC',
'8mill' => 'KCKCC',
'8mlii' => 'KCKCC',
'8mres' => 'KCKCC',
'8mu' => 'KCKCC',
'8muwi' => 'KCKCC',
'8mwri' => 'KCKCC',
'8tb' => 'KCKCC',
'8ttec' => 'KCKCC',
'kcada' => 'KCU',
'kcadb' => 'KCU',
'kcadc' => 'KCU',
'kcadd' => 'KCU',
'kcaip' => 'KCU',
'kcall' => 'KCU',
'kcb' => 'KCU',
'kccfi' => 'KCU',
'kccip' => 'KCU',
'kcdsi' => 'KCU',
'kceii' => 'KCU',
'kcfci' => 'KCU',
'kcill' => 'KCU',
'kcj' => 'KCU',
'kcjii' => 'KCU',
'kcjxi' => 'KCU',
'kcmed' => 'KCU',
'kcmod' => 'KCU',
'kcpbl' => 'KCU',
'kcpub' => 'KCU',
'kcs2i' => 'KCU',
'kcsci' => 'KCU',
'kcsli' => 'KCU',
'kcu' => 'KCU',
'kcuwi' => 'KCU',
'kcxii' => 'KCU',
'bta' => 'MBTS',
'btaba' => 'MBTS',
'btabm' => 'MBTS',
'btabw' => 'MBTS',
'btara' => 'MBTS',
'btarb' => 'MBTS',
'btc' => 'MBTS',
'bte' => 'MBTS',
'bteeb' => 'MBTS',
'btf' => 'MBTS',
'btg' => 'MBTS',
'btgcc' => 'MBTS',
'bti' => 'MBTS',
'btioc' => 'MBTS',
'btj' => 'MBTS',
'btjei' => 'MBTS',
'btk' => 'MBTS',
'bto' => 'MBTS',
'btoad' => 'MBTS',
'btoca' => 'MBTS',
'btodi' => 'MBTS',
'btr' => 'MBTS',
'btrco' => 'MBTS',
'btrpd' => 'MBTS',
'btrre' => 'MBTS',
'bts' => 'MBTS',
'btsav' => 'MBTS',
'btsrs' => 'MBTS',
'btt' => 'MBTS',
'btu' => 'MBTS',
'btuii' => 'MBTS',
'btx' => 'MBTS',
'btz' => 'MBTS',
'btzsp' => 'MBTS',
'mbaii' => 'MCC',
'mbb' => 'MCC',
'mbbii' => 'MCC',
'mbcgi' => 'MCC',
'mbcii' => 'MCC',
'mbfii' => 'MCC',
'mbjii' => 'MCC',
'mbpii' => 'MCC',
'mbrai' => 'MCC',
'mbrdi' => 'MCC',
'mbrii' => 'MCC',
'mbsii' => 'MCC',
'mbu' => 'MCC',
'mbuii' => 'MCC',
'mbuwi' => 'MCC',
'mbxii' => 'MCC',
'mco' => 'MCC',
'mebks' => 'MCC',
'mlaii' => 'MCC',
'mlb' => 'MCC',
'mlcbi' => 'MCC',
'mlcgi' => 'MCC',
'mlcii' => 'MCC',
'mlcli' => 'MCC',
'mlcoi' => 'MCC',
'mljii' => 'MCC',
'mlpac' => 'MCC',
'mlpii' => 'MCC',
'mlrai' => 'MCC',
'mlrew' => 'MCC',
'mlrii' => 'MCC',
'mlsii' => 'MCC',
'mlu' => 'MCC',
'mluwi' => 'MCC',
'mlxii' => 'MCC',
'mob' => 'MCC',
'mocii' => 'MCC',
'mpaii' => 'MCC',
'mpb' => 'MCC',
'mpbii' => 'MCC',
'mpcii' => 'MCC',
'mpfii' => 'MCC',
'mpnii' => 'MCC',
'mppii' => 'MCC',
'mprai' => 'MCC',
'mprdi' => 'MCC',
'mprii' => 'MCC',
'mproi' => 'MCC',
'mprxi' => 'MCC',
'mpsii' => 'MCC',
'mptii' => 'MCC',
'mpu' => 'MCC',
'mpuii' => 'MCC',
'mpuwi' => 'MCC',
'mpxii' => 'MCC',
'mtcii' => 'MCC',
'multi' => 'MCC',
'mwaii' => 'MCC',
'mwb' => 'MCC',
'mwcfi' => 'MCC',
'mwcii' => 'MCC',
'mwfii' => 'MCC',
'mwpii' => 'MCC',
'mwrai' => 'MCC',
'mwrdi' => 'MCC',
'mwrii' => 'MCC',
'mwrxi' => 'MCC',
'mwsii' => 'MCC',
'mwtii' => 'MCC',
'mwxii' => 'MCC',
'm2a' => 'MWSU',
'm2acx' => 'MWSU',
'm2adx' => 'MWSU',
'm2avd' => 'MWSU',
'm2avi' => 'MWSU',
'm2avx' => 'MWSU',
'm2b' => 'MWSU',
'm2cai' => 'MWSU',
'm2cbr' => 'MWSU',
'm2cii' => 'MWSU',
'm2cni' => 'MWSU',
'm2coi' => 'MWSU',
'm2crb' => 'MWSU',
'm2csi' => 'MWSU',
'm2d' => 'MWSU',
'm2e' => 'MWSU',
'm2ill' => 'MWSU',
'm2imc' => 'MWSU',
'm2j' => 'MWSU',
'm2jii' => 'MWSU',
'm2mri' => 'MWSU',
'm2o' => 'MWSU',
'm2oii' => 'MWSU',
'm2oti' => 'MWSU',
'm2p' => 'MWSU',
'm2pbi' => 'MWSU',
'm2pei' => 'MWSU',
'm2pmi' => 'MWSU',
'm2pni' => 'MWSU',
'm2psi' => 'MWSU',
'm2r' => 'MWSU',
'm2rai' => 'MWSU',
'm2rii' => 'MWSU',
'm2rmi' => 'MWSU',
'm2s' => 'MWSU',
'm2sii' => 'MWSU',
'm2sri' => 'MWSU',
'm2swi' => 'MWSU',
'm2syb' => 'MWSU',
'm2t' => 'MWSU',
'm2u' => 'MWSU',
'm2udi' => 'MWSU',
'm2uii' => 'MWSU',
'm2uwi' => 'MWSU',
'm2v' => 'MWSU',
'm2wii' => 'MWSU',
'm2x' => 'MWSU',
'm2x14' => 'MWSU',
'm2x3d' => 'MWSU',
'm2x3h' => 'MWSU',
'm2x6h' => 'MWSU',
'm2x7d' => 'MWSU',
'm2xii' => 'MWSU',
'n39ii' => 'NCMC',
'n3b' => 'NCMC',
'n3dii' => 'NCMC',
'n3eii' => 'NCMC',
'n3fii' => 'NCMC',
'n3fpi' => 'NCMC',
'n3g' => 'NCMC',
'n3gii' => 'NCMC',
'n3gri' => 'NCMC',
'n3h' => 'NCMC',
'n3hii' => 'NCMC',
'n3int' => 'NCMC',
'n3jii' => 'NCMC',
'n3m' => 'NCMC',
'n3mai' => 'NCMC',
'n3mci' => 'NCMC',
'n3mli' => 'NCMC',
'n3mni' => 'NCMC',
'n3mvf' => 'NCMC',
'n3mvp' => 'NCMC',
'n3nii' => 'NCMC',
'n3pii' => 'NCMC',
'n3r' => 'NCMC',
'n3rii' => 'NCMC',
'n3s' => 'NCMC',
'n3sii' => 'NCMC',
'n3svi' => 'NCMC',
'n3tii' => 'NCMC',
'n3u' => 'NCMC',
'n3udi' => 'NCMC',
'n3uii' => 'NCMC',
'n3uwi' => 'NCMC',
'n3xii' => 'NCMC',
'ntb' => 'NTS',
'ntcii' => 'NTS',
'ntcoi' => 'NTS',
'ntcti' => 'NTS',
'ntczi' => 'NTS',
'nteii' => 'NTS',
'ntfii' => 'NTS',
'ntjbi' => 'NTS',
'ntjci' => 'NTS',
'ntmii' => 'NTS',
'ntrii' => 'NTS',
'ntroi' => 'NTS',
'ntsii' => 'NTS',
'ntu' => 'NTS',
'ntxii' => 'NTS',
'w4a' => 'NWMSU',
'w4aei' => 'NWMSU',
'w4b' => 'NWMSU',
'w4c' => 'NWMSU',
'w4cii' => 'NWMSU',
'w4ill' => 'NWMSU',
'w4j' => 'NWMSU',
'w4jbi' => 'NWMSU',
'w4jii' => 'NWMSU',
'w4jki' => 'NWMSU',
'w4kc' => 'NWMSU',
'w4m' => 'NWMSU',
'w4mei' => 'NWMSU',
'w4mfi' => 'NWMSU',
'w4mii' => 'NWMSU',
'w4mqi' => 'NWMSU',
'w4n' => 'NWMSU',
'w4nii' => 'NWMSU',
'w4o' => 'NWMSU',
'w4opa' => 'NWMSU',
'w4opb' => 'NWMSU',
'w4opc' => 'NWMSU',
'w4opf' => 'NWMSU',
'w4p' => 'NWMSU',
'w4pun' => 'NWMSU',
'w4pva' => 'NWMSU',
'w4pzn' => 'NWMSU',
'w4r' => 'NWMSU',
'w4red' => 'NWMSU',
'w4rsi' => 'NWMSU',
'w4sii' => 'NWMSU',
'w4u' => 'NWMSU',
'w4udi' => 'NWMSU',
'w4v' => 'NWMSU',
'w4vii' => 'NWMSU',
'w4xii' => 'NWMSU',
'w5aei' => 'NWMSU',
'w5b' => 'NWMSU',
'w5big' => 'NWMSU',
'w5fei' => 'NWMSU',
'w5fii' => 'NWMSU',
'w5nei' => 'NWMSU',
'w5nii' => 'NWMSU',
'w5pop' => 'NWMSU',
'w5u' => 'NWMSU',
'w5udi' => 'NWMSU',
'panex' => 'PARK',
'pargr' => 'PARK',
'parst' => 'PARK',
'parwk' => 'PARK',
'pdisp' => 'PARK',
'pgbka' => 'PARK',
'pkart' => 'PARK',
'pkb' => 'PARK',
'pkdvd' => 'PARK',
'pkebk' => 'PARK',
'pkloc' => 'PARK',
'pkpcj' => 'PARK',
'pkres' => 'PARK',
'pkthe' => 'PARK',
'pkw' => 'PARK',
'pkwar' => 'PARK',
'pllma' => 'PARK',
'pllmn' => 'PARK',
'pmuss' => 'PARK',
'povsz' => 'PARK',
'ppopf' => 'PARK',
'ppopn' => 'PARK',
'prefw' => 'PARK',
'prref' => 'PARK',
'pshlf' => 'PARK',
'pwltc' => 'PARK',
'pwpc' => 'PARK',
'rga' => 'ROCK',
'rgarc' => 'ROCK',
'rgb' => 'ROCK',
'rgcdi' => 'ROCK',
'rgcei' => 'ROCK',
'rgcii' => 'ROCK',
'rgcnr' => 'ROCK',
'rgcoi' => 'ROCK',
'rgcpi' => 'ROCK',
'rgd' => 'ROCK',
'rgder' => 'ROCK',
'rgj' => 'ROCK',
'rgjii' => 'ROCK',
'rglll' => 'ROCK',
'rgr' => 'ROCK',
'rgrii' => 'ROCK',
'rgrni' => 'ROCK',
'rgrsi' => 'ROCK',
'rgs' => 'ROCK',
'rgu' => 'ROCK',
'rguwi' => 'ROCK',
'rgv' => 'ROCK',
'rgvii' => 'ROCK',
'rgxii' => 'ROCK',
'sdaii' => 'SPST',
'sdb' => 'SPST',
'sdcii' => 'SPST',
'sdcoi' => 'SPST',
'sddth' => 'SPST',
'sdebi' => 'SPST',
'sdebk' => 'SPST',
'sdeii' => 'SPST',
'sdgai' => 'SPST',
'sdgci' => 'SPST',
'sdgco' => 'SPST',
'sdgri' => 'SPST',
'sdrii' => 'SPST',
'sdshi' => 'SPST',
'sdsri' => 'SPST',
'sdsvi' => 'SPST',
'sdu' => 'SPST',
'sduii' => 'SPST',
'sdxii' => 'SPST',
'wjb' => 'WJC',
'wjc' => 'WJC',
'wjcai' => 'WJC',
'wjccc' => 'WJC',
'wjcii' => 'WJC',
'wjcsv' => 'WJC',
'wjd' => 'WJC',
'wjdii' => 'WJC',
'wjdwi' => 'WJC',
'wje' => 'WJC',
'wjedp' => 'WJC',
'wjeeb' => 'WJC',
'wjeej' => 'WJC',
'wjesv' => 'WJC',
'wjg' => 'WJC',
'wjgci' => 'WJC',
'wjgii' => 'WJC',
'wjgoi' => 'WJC',
'wji' => 'WJC',
'wjili' => 'WJC',
'wjp' => 'WJC',
'wjpii' => 'WJC',
'wjs' => 'WJC',
'wjsbi' => 'WJC',
'wjsci' => 'WJC',
'wjsei' => 'WJC',
'wjsfi' => 'WJC',
'wjshi' => 'WJC',
'wjsji' => 'WJC',
'wjsli' => 'WJC',
'wjsmi' => 'WJC',
'wjsoi' => 'WJC',
'wjsri' => 'WJC',
'wjsti' => 'WJC',
'wjsvi' => 'WJC',
'wju' => 'WJC',
'wjude' => 'WJC',
'wjuii' => 'WJC',
'wjuwi' => 'WJC',
'wjx' => 'WJC',
'wjxdv' => 'WJC',
'wjxii' => 'WJC',
'wjxpd' => 'WJC',
'wjxxi' => 'WJC',
'wjy' => 'WJC',
'wjyjc' => 'WJC',
'wjyji' => 'WJC',
'wjyjn' => 'WJC',
  );
  return \%mapping;
  
}

sub locationNormalize_explore
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'g' => 'GSN',
'garch' => 'GSN',
'gav' => 'GSN',
'gelec' => 'GSN',
'gmbmc' => 'GSN',
'gper' => 'GSN',
'gref' => 'GSN',
'gres' => 'GSN',
'gstk' => 'GSN',
'gths' => 'GSN',
'gu' => 'GSN',
'guwi' => 'GSN',
'b' => 'MBG',
'bcewa' => 'MBG',
'bo' => 'MBG',
'boatl' => 'MBG',
'bobry' => 'MBG',
'bocom' => 'MBG',
'bogen' => 'MBG',
'bomap' => 'MBG',
'bomic' => 'MBG',
'boper' => 'MBG',
'boref' => 'MBG',
'boslh' => 'MBG',
'bovid' => 'MBG',
'boxls' => 'MBG',
'br' => 'MBG',
'brfol' => 'MBG',
'brlfo' => 'MBG',
'brlin' => 'MBG',
'brprl' => 'MBG',
'brprm' => 'MBG',
'brprs' => 'MBG',
'brprx' => 'MBG',
'brrar' => 'MBG',
'bs' => 'MBG',
'bsarc' => 'MBG',
'bscat' => 'MBG',
'bscon' => 'MBG',
'bu' => 'MBG',
'buwi' => 'MBG',
'c' => 'MHS',
'cp' => 'MHS',
'ct' => 'MHS',
'cv' => 'MHS',
'h' => 'MHS',
'ha' => 'MHS',
'har1' => 'MHS',
'hd' => 'MHS',
'he' => 'MHS',
'hf' => 'MHS',
'hfg1' => 'MHS',
'hm' => 'MHS',
'hmg2' => 'MHS',
'hmgeo' => 'MHS',
'hn' => 'MHS',
'hng1' => 'MHS',
'hng2' => 'MHS',
'hng4' => 'MHS',
'hnmf' => 'MHS',
'hp' => 'MHS',
'hpd' => 'MHS',
'hpgef' => 'MHS',
'hpgeg' => 'MHS',
'hpgem' => 'MHS',
'hpgeo' => 'MHS',
'hpmc' => 'MHS',
'hpmf' => 'MHS',
'hppp' => 'MHS',
'hpr1' => 'MHS',
'hpr2' => 'MHS',
'hpr3' => 'MHS',
'hpr6' => 'MHS',
'hpsc' => 'MHS',
'hpscf' => 'MHS',
'hs' => 'MHS',
'ht' => 'MHS',
'htgef' => 'MHS',
'hu' => 'MHS',
'huwi' => 'MHS',
'hv' => 'MHS',
'hx' => 'MHS',
'hy' => 'MHS',
'hygeo' => 'MHS',
'hz' => 'MHS',
'a' => 'SLAM',
'aauc' => 'SLAM',
'agar' => 'SLAM',
'agcl' => 'SLAM',
'agen' => 'SLAM',
'agfo' => 'SLAM',
'agpa' => 'SLAM',
'agpr' => 'SLAM',
'agrf' => 'SLAM',
'agrs' => 'SLAM',
'agsc' => 'SLAM',
'agst' => 'SLAM',
'aper' => 'SLAM',
'apmu' => 'SLAM',
'au' => 'SLAM',
'auwi' => 'SLAM',
  );
  return \%mapping;
  
}

sub locationNormalize_bridges
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'ng100' => 'CONC',
'ng2ci' => 'CONC',
'ngaca' => 'CONC',
'ngb' => 'CONC',
'ngcia' => 'CONC',
'ngdis' => 'CONC',
'ngdvd' => 'CONC',
'ngfch' => 'CONC',
'ngflm' => 'CONC',
'ngfof' => 'CONC',
'ngfol' => 'CONC',
'ngoic' => 'CONC',
'ngpar' => 'CONC',
'ngpbd' => 'CONC',
'ngpcu' => 'CONC',
'ngpfe' => 'CONC',
'ngpfm' => 'CONC',
'ngpre' => 'CONC',
'ngref' => 'CONC',
'ngrfb' => 'CONC',
'ngrin' => 'CONC',
'ngu' => 'CONC',
'nguii' => 'CONC',
'ni400' => 'CONC',
'niarc' => 'CONC',
'nib' => 'CONC',
'nicia' => 'CONC',
'nidis' => 'CONC',
'nidvd' => 'CONC',
'nifch' => 'CONC',
'niflm' => 'CONC',
'nifo2' => 'CONC',
'nifol' => 'CONC',
'nifor' => 'CONC',
'nirar' => 'CONC',
'niref' => 'CONC',
'nistk' => 'CONC',
'nrb' => 'CONC',
'ns101' => 'CONC',
'nsb' => 'CONC',
'nsc' => 'CONC',
'nsdis' => 'CONC',
'nsdvd' => 'CONC',
'nsref' => 'CONC',
'nz999' => 'CONC',
'nzarc' => 'CONC',
'nzcrr' => 'CONC',
'nzfof' => 'CONC',
'nzfol' => 'CONC',
'nzg10' => 'CONC',
'nzg12' => 'CONC',
'nzh10' => 'CONC',
'nzi10' => 'CONC',
'nzl10' => 'CONC',
'nzm10' => 'CONC',
'c0000' => 'COV',
'cba' => 'COV',
'cbadi' => 'COV',
'cbaoi' => 'COV',
'cbavi' => 'COV',
'cbb' => 'COV',
'cbc' => 'COV',
'cbcii' => 'COV',
'cbe' => 'COV',
'cbebi' => 'COV',
'cbeia' => 'COV',
'cbeii' => 'COV',
'cbepi' => 'COV',
'cbh' => 'COV',
'cbhvi' => 'COV',
'cbl' => 'COV',
'cblci' => 'COV',
'cbldi' => 'COV',
'cbm' => 'COV',
'cbmhi' => 'COV',
'cbmli' => 'COV',
'cbp' => 'COV',
'cbpii' => 'COV',
'cbpzi' => 'COV',
'cbq' => 'COV',
'cbqii' => 'COV',
'cbr' => 'COV',
'cbrai' => 'COV',
'cbrfi' => 'COV',
'cbrii' => 'COV',
'cbrri' => 'COV',
'cbs' => 'COV',
'cbsii' => 'COV',
'cbski' => 'COV',
'cbsmi' => 'COV',
'cbsni' => 'COV',
'cbsoi' => 'COV',
'cbt' => 'COV',
'cbtfi' => 'COV',
'cbtii' => 'COV',
'cbtoi' => 'COV',
'cbx2i' => 'COV',
'cbx3i' => 'COV',
'cbxii' => 'COV',
'cbxni' => 'COV',
'cbxwi' => 'COV',
'cbxzi' => 'COV',
'cby' => 'COV',
'cbyii' => 'COV',
'cnn' => 'COV',
'cnr' => 'COV',
'cnrii' => 'COV',
'cns' => 'COV',
'cnsii' => 'COV',
'cub' => 'COV',
'cudii' => 'COV',
'cuiii' => 'COV',
'cuwii' => 'COV',
'we2' => 'EWL',
'we25i' => 'EWL',
'we2fi' => 'EWL',
'we2hi' => 'EWL',
'we2ii' => 'EWL',
'we2ji' => 'EWL',
'we2oi' => 'EWL',
'we3ii' => 'EWL',
'weaai' => 'EWL',
'weali' => 'EWL',
'weati' => 'EWL',
'weato' => 'EWL',
'web' => 'EWL',
'webe' => 'EWL',
'wecii' => 'EWL',
'weiit' => 'EWL',
'wej' => 'EWL',
'wejii' => 'EWL',
'wejoi' => 'EWL',
'wemii' => 'EWL',
'wemit' => 'EWL',
'wemmi' => 'EWL',
'wemoi' => 'EWL',
'wep' => 'EWL',
'wepci' => 'EWL',
'wepmi' => 'EWL',
'weppw' => 'EWL',
'wepsi' => 'EWL',
'wer' => 'EWL',
'werii' => 'EWL',
'weroi' => 'EWL',
'wersi' => 'EWL',
'wes' => 'EWL',
'wesii' => 'EWL',
'wesoi' => 'EWL',
'wet' => 'EWL',
'weu' => 'EWL',
'weudi' => 'EWL',
'weuii' => 'EWL',
'weuwi' => 'EWL',
'wex' => 'EWL',
'wexii' => 'EWL',
'wsabi' => 'EWL',
'wsai' => 'EWL',
'wsaia' => 'EWL',
'wsaib' => 'EWL',
'wsaii' => 'EWL',
'wsaim' => 'EWL',
'wsaip' => 'EWL',
'wsair' => 'EWL',
'wsais' => 'EWL',
'wsait' => 'EWL',
'wsaix' => 'EWL',
'wsb' => 'EWL',
'wsge' => 'EWL',
'wsgh' => 'EWL',
'wsgha' => 'EWL',
'wsghb' => 'EWL',
'wsghl' => 'EWL',
'wsghr' => 'EWL',
'wsgvi' => 'EWL',
'wsldi' => 'EWL',
'wsle' => 'EWL',
'wst' => 'EWL',
'wsta' => 'EWL',
'wstb' => 'EWL',
'wstp' => 'EWL',
'wstr' => 'EWL',
'wstx' => 'EWL',
'wsu' => 'EWL',
'wsudi' => 'EWL',
'wsuii' => 'EWL',
'wsuwi' => 'EWL',
'wsvi' => 'EWL',
'wsvia' => 'EWL',
'wsvib' => 'EWL',
'wsvii' => 'EWL',
'wsvim' => 'EWL',
'wsvip' => 'EWL',
'wsvir' => 'EWL',
'wsvis' => 'EWL',
'wsvit' => 'EWL',
'wsvix' => 'EWL',
'wsz' => 'EWL',
'wszdi' => 'EWL',
'wszii' => 'EWL',
'wszri' => 'EWL',
'wszx' => 'EWL',
'ww&ci' => 'EWL',
'ww2' => 'EWL',
'ww25h' => 'EWL',
'ww2fh' => 'EWL',
'ww2fi' => 'EWL',
'ww2hi' => 'EWL',
'ww2ih' => 'EWL',
'ww2ii' => 'EWL',
'ww2is' => 'EWL',
'ww2jh' => 'EWL',
'ww2oi' => 'EWL',
'ww3' => 'EWL',
'ww3ii' => 'EWL',
'ww4' => 'EWL',
'wwaai' => 'EWL',
'wwabi' => 'EWL',
'wwaci' => 'EWL',
'wwadi' => 'EWL',
'wwaei' => 'EWL',
'wwaii' => 'EWL',
'wwali' => 'EWL',
'wwaqi' => 'EWL',
'wwari' => 'EWL',
'wwasi' => 'EWL',
'wwati' => 'EWL',
'wwato' => 'EWL',
'wwavi' => 'EWL',
'wwavo' => 'EWL',
'wwb' => 'EWL',
'wwbcl' => 'EWL',
'wwcci' => 'EWL',
'wwcdi' => 'EWL',
'wwcii' => 'EWL',
'wweii' => 'EWL',
'wwiim' => 'EWL',
'wwiit' => 'EWL',
'wwj' => 'EWL',
'wwjai' => 'EWL',
'wwjii' => 'EWL',
'wwjoi' => 'EWL',
'wwjpi' => 'EWL',
'wwjxi' => 'EWL',
'wwlii' => 'EWL',
'wwm3i' => 'EWL',
'wwm4i' => 'EWL',
'wwmib' => 'EWL',
'wwmii' => 'EWL',
'wwmil' => 'EWL',
'wwmir' => 'EWL',
'wwmit' => 'EWL',
'wwmmi' => 'EWL',
'wwmoh' => 'EWL',
'wwmoi' => 'EWL',
'wwo' => 'EWL',
'wwp' => 'EWL',
'wwpci' => 'EWL',
'wwpii' => 'EWL',
'wwpmi' => 'EWL',
'wwppw' => 'EWL',
'wwr' => 'EWL',
'wwrgi' => 'EWL',
'wwrii' => 'EWL',
'wwril' => 'EWL',
'wwrji' => 'EWL',
'wwrni' => 'EWL',
'wwroi' => 'EWL',
'wwt' => 'EWL',
'wwu' => 'EWL',
'wwudi' => 'EWL',
'wwuii' => 'EWL',
'wwuwi' => 'EWL',
'wwwic' => 'EWL',
'wwwif' => 'EWL',
'wwx' => 'EWL',
'wwxii' => 'EWL',
'fca' => 'FONT',
'fcabs' => 'FONT',
'fcard' => 'FONT',
'fcari' => 'FONT',
'fcaro' => 'FONT',
'fcart' => 'FONT',
'fcarv' => 'FONT',
'fcavi' => 'FONT',
'fcavs' => 'FONT',
'fcb' => 'FONT',
'fcbmp' => 'FONT',
'fccbs' => 'FONT',
'fccdi' => 'FONT',
'fcdds' => 'FONT',
'fce' => 'FONT',
'fcedu' => 'FONT',
'fcf' => 'FONT',
'fcgen' => 'FONT',
'fcgoi' => 'FONT',
'fci' => 'FONT',
'fcint' => 'FONT',
'fcj' => 'FONT',
'fcjub' => 'FONT',
'fcjuf' => 'FONT',
'fcjun' => 'FONT',
'fcjuv' => 'FONT',
'fcmti' => 'FONT',
'fcp' => 'FONT',
'fcpbi' => 'FONT',
'fcr' => 'FONT',
'fcrii' => 'FONT',
'fcs' => 'FONT',
'fcspc' => 'FONT',
'fcsto' => 'FONT',
'fctsi' => 'FONT',
'fcu' => 'FONT',
'fcxii' => 'FONT',
'fub' => 'FONT',
'fudii' => 'FONT',
'hsa' => 'HSSU',
'hsaci' => 'HSSU',
'hsaii' => 'HSSU',
'hsb' => 'HSSU',
'hsbii' => 'HSSU',
'hsbri' => 'HSSU',
'hsc' => 'HSSU',
'hscii' => 'HSSU',
'hscir' => 'HSSU',
'hsd' => 'HSSU',
'hsdwi' => 'HSSU',
'hsdwr' => 'HSSU',
'hsfii' => 'HSSU',
'hsgii' => 'HSSU',
'hsj' => 'HSSU',
'hsjci' => 'HSSU',
'hsjii' => 'HSSU',
'hsjir' => 'HSSU',
'hsjki' => 'HSSU',
'hsjni' => 'HSSU',
'hsjpi' => 'HSSU',
'hsjpr' => 'HSSU',
'hso' => 'HSSU',
'hsoii' => 'HSSU',
'hsp' => 'HSSU',
'hsr' => 'HSSU',
'hsrii' => 'HSSU',
'hss' => 'HSSU',
'hssjp' => 'HSSU',
'hsu' => 'HSSU',
'hsuii' => 'HSSU',
'hsv' => 'HSSU',
'hsw' => 'HSSU',
'hsxii' => 'HSSU',
'hub' => 'HSSU',
'hudii' => 'HSSU',
'huiii' => 'HSSU',
'huwii' => 'HSSU',
'kgaco' => 'KGS',
'kgahi' => 'KGS',
'kgahs' => 'KGS',
'kgaii' => 'KGS',
'kgarb' => 'KGS',
'kgath' => 'KGS',
'kgb' => 'KGS',
'kggii' => 'KGS',
'kggov' => 'KGS',
'kgmer' => 'KGS',
'kgmfe' => 'KGS',
'kgmfm' => 'KGS',
'kgmso' => 'KGS',
'kgrai' => 'KGS',
'kgrhs' => 'KGS',
'kgrii' => 'KGS',
'kgrli' => 'KGS',
'kgrvf' => 'KGS',
'kgsej' => 'KGS',
'kgser' => 'KGS',
'kgtac' => 'KGS',
'kgtbi' => 'KGS',
'kgtca' => 'KGS',
'kgtii' => 'KGS',
'kgtld' => 'KGS',
'kgxii' => 'KGS',
'kgzp1' => 'KGS',
'kub' => 'KGS',
'kuiii' => 'KGS',
'lb0wi' => 'LIND',
'lbaii' => 'LIND',
'lbb' => 'LIND',
'lbbhi' => 'LIND',
'lbc' => 'LIND',
'lbgri' => 'LIND',
'lbiii' => 'LIND',
'lbint' => 'LIND',
'lbjii' => 'LIND',
'lbjyi' => 'LIND',
'lbkii' => 'LIND',
'lblii' => 'LIND',
'lbnbs' => 'LIND',
'lboii' => 'LIND',
'lbovr' => 'LIND',
'lbpii' => 'LIND',
'lbpxd' => 'LIND',
'lbrii' => 'LIND',
'lbrui' => 'LIND',
'lbsdc' => 'LIND',
'lbsdf' => 'LIND',
'lbtii' => 'LIND',
'lbvii' => 'LIND',
'lbxdi' => 'LIND',
'lbyui' => 'LIND',
'lbzii' => 'LIND',
'lbzzz' => 'LIND',
'lub' => 'LIND',
'luc' => 'LIND',
'lud' => 'LIND',
'ludii' => 'LIND',
'lue' => 'LIND',
'lug' => 'LIND',
'luiii' => 'LIND',
'lulr' => 'LIND',
'lum' => 'LIND',
'lur' => 'LIND',
'lursc' => 'LIND',
'lus' => 'LIND',
'luwii' => 'LIND',
'ojb' => 'LOGAN',
'ojbmi' => 'LOGAN',
'ojbmx' => 'LOGAN',
'ojcii' => 'LOGAN',
'ojebi' => 'LOGAN',
'ojfli' => 'LOGAN',
'ojh' => 'LOGAN',
'ojhii' => 'LOGAN',
'ojiii' => 'LOGAN',
'ojjbi' => 'LOGAN',
'ojjdm' => 'LOGAN',
'ojjmn' => 'LOGAN',
'ojjsr' => 'LOGAN',
'ojjui' => 'LOGAN',
'ojlti' => 'LOGAN',
'ojmii' => 'LOGAN',
'ojmxi' => 'LOGAN',
'ojnew' => 'LOGAN',
'ojrii' => 'LOGAN',
'ojt' => 'LOGAN',
'ojtii' => 'LOGAN',
'ojvii' => 'LOGAN',
'ojxii' => 'LOGAN',
'oub' => 'LOGAN',
'oudii' => 'LOGAN',
'ouiii' => 'LOGAN',
'ouwii' => 'LOGAN',
'beiii' => 'MBU',
'bja' => 'MBU',
'bjadi' => 'MBU',
'bjb' => 'MBU',
'bjc' => 'MBU',
'bjcfo' => 'MBU',
'bjcii' => 'MBU',
'bjcoi' => 'MBU',
'bje' => 'MBU',
'bjeii' => 'MBU',
'bjj' => 'MBU',
'bjjli' => 'MBU',
'bjjri' => 'MBU',
'bjpdi' => 'MBU',
'bjpii' => 'MBU',
'bjr' => 'MBU',
'bjrii' => 'MBU',
'bjs' => 'MBU',
'bjsrb' => 'MBU',
'bju' => 'MBU',
'bjudi' => 'MBU',
'bjuii' => 'MBU',
'bjuwi' => 'MBU',
'bjvdi' => 'MBU',
'bjxd1' => 'MBU',
'bjxd2' => 'MBU',
'bjxd3' => 'MBU',
'bjxd4' => 'MBU',
'bjxd5' => 'MBU',
'bjxh1' => 'MBU',
'bjxii' => 'MBU',
'bjxoi' => 'MBU',
'bjxw1' => 'MBU',
'bjxw2' => 'MBU',
'bjxw3' => 'MBU',
'bjyii' => 'MBU',
'bjzii' => 'MBU',
'bsb' => 'MBU',
'bsu' => 'MBU',
'mu1' => 'MRYV',
'mu2' => 'MRYV',
'mu3' => 'MRYV',
'mu4' => 'MRYV',
'mu5' => 'MRYV',
'mu6' => 'MRYV',
'mu7' => 'MRYV',
'mu8' => 'MRYV',
'mu9' => 'MRYV',
'muasp' => 'MRYV',
'mub' => 'MRYV',
'muh' => 'MRYV',
'muint' => 'MRYV',
'multi' => 'MRYV',
'mumbc' => 'MRYV',
'mumch' => 'MRYV',
'mumcm' => 'MRYV',
'mumco' => 'MRYV',
'mumjm' => 'MRYV',
'mumpr' => 'MRYV',
'mundv' => 'MRYV',
'munlv' => 'MRYV',
'mur1d' => 'MRYV',
'mur1n' => 'MRYV',
'mur1w' => 'MRYV',
'mur2h' => 'MRYV',
'mur3d' => 'MRYV',
'mursm' => 'MRYV',
'mzb' => 'MRYV',
'mzdii' => 'MRYV',
);
  return \%mapping;
  
}

sub locationNormalize_arthur
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'csb' => 'CCIS',
'cscdo' => 'CCIS',
'cscqi' => 'CCIS',
'csdci' => 'CCIS',
'csdvd' => 'CCIS',
'csebi' => 'CCIS',
'csek2' => 'CCIS',
'cseki' => 'CCIS',
'cseri' => 'CCIS',
'csevi' => 'CCIS',
'csiii' => 'CCIS',
'csjfi' => 'CCIS',
'csjni' => 'CCIS',
'cslii' => 'CCIS',
'csnbs' => 'CCIS',
'csncc' => 'CCIS',
'cspci' => 'CCIS',
'cspoi' => 'CCIS',
'cspop' => 'CCIS',
'cspti' => 'CCIS',
'csqii' => 'CCIS',
'csrai' => 'CCIS',
'csrcc' => 'CCIS',
'csrmi' => 'CCIS',
'csrri' => 'CCIS',
'cssbi' => 'CCIS',
'cssii' => 'CCIS',
'csu' => 'CCIS',
'csw' => 'CCIS',
'cswdi' => 'CCIS',
'cswii' => 'CCIS',
'csxii' => 'CCIS',
'csyii' => 'CCIS',
'lmb' => 'LINC',
'lparc' => 'LINC',
'lpb' => 'LINC',
'lpcov' => 'LINC',
'lpdsp' => 'LINC',
'lpelb' => 'LINC',
'lpflm' => 'LINC',
'lpgov' => 'LINC',
'lpgve' => 'LINC',
'lpjuv' => 'LINC',
'lpkii' => 'LINC',
'lplin' => 'LINC',
'lpmed' => 'LINC',
'lpmkt' => 'LINC',
'lpper' => 'LINC',
'lpref' => 'LINC',
'lpsch' => 'LINC',
'lptac' => 'LINC',
'lpu' => 'LINC',
'lpuii' => 'LINC',
'lpw' => 'LINC',
'lpwdi' => 'LINC',
'lpwii' => 'LINC',
'lpxii' => 'LINC',
'lpyii' => 'LINC',
'mob' => 'MOSL',
'moc' => 'MOSL',
'mocri' => 'MOSL',
'mog' => 'MOSL',
'mogri' => 'MOSL',
'moi' => 'MOSL',
'moiri' => 'MOSL',
'mom' => 'MOSL',
'morci' => 'MOSL',
'morfe' => 'MOSL',
'morfk' => 'MOSL',
'morfm' => 'MOSL',
'morhl' => 'MOSL',
'morkd' => 'MOSL',
'morke' => 'MOSL',
'morki' => 'MOSL',
'morkl' => 'MOSL',
'morkm' => 'MOSL',
'morko' => 'MOSL',
'morkp' => 'MOSL',
'morme' => 'MOSL',
'mormk' => 'MOSL',
'mormm' => 'MOSL',
'morrd' => 'MOSL',
'morre' => 'MOSL',
'morri' => 'MOSL',
'morsi' => 'MOSL',
'morsm' => 'MOSL',
'morsn' => 'MOSL',
'mot' => 'MOSL',
'motkd' => 'MOSL',
'motke' => 'MOSL',
'motkh' => 'MOSL',
'motki' => 'MOSL',
'motkp' => 'MOSL',
'motkt' => 'MOSL',
'motri' => 'MOSL',
'motsi' => 'MOSL',
'moy' => 'MOSL',
'moywi' => 'MOSL',
'sce' => 'SC',
'sceci' => 'SC',
'sceki' => 'SC',
'scepi' => 'SC',
'semo0' => 'SC',
'shar2' => 'SC',
'sharc' => 'SC',
'share' => 'SC',
'shb' => 'SC',
'shbrc' => 'SC',
'shcci' => 'SC',
'shdri' => 'SC',
'sheii' => 'SC',
'shfii' => 'SC',
'shgii' => 'SC',
'shiii' => 'SC',
'shjii' => 'SC',
'shjri' => 'SC',
'shlgi' => 'SC',
'shper' => 'SC',
'shpop' => 'SC',
'shqii' => 'SC',
'shrii' => 'SC',
'shrri' => 'SC',
'shsii' => 'SC',
'shtob' => 'SC',
'shu' => 'SC',
'shuii' => 'SC',
'shvdi' => 'SC',
'shvii' => 'SC',
'shw' => 'SC',
'shwdi' => 'SC',
'shwii' => 'SC',
'shxii' => 'SC',
'2mb' => 'WC',
'2mcii' => 'WC',
'2mihi' => 'WC',
'2miii' => 'WC',
'2mkii' => 'WC',
'2mpii' => 'WC',
'2mrii' => 'WC',
'2raii' => 'WC',
'2raud' => 'WC',
'2rb' => 'WC',
'2rbii' => 'WC',
'2rcon' => 'WC',
'2rd' => 'WC',
'2rdii' => 'WC',
'2re' => 'WC',
'2rebg' => 'WC',
'2rebk' => 'WC',
'2recb' => 'WC',
'2recs' => 'WC',
'2reii' => 'WC',
'2rgfi' => 'WC',
'2rgii' => 'WC',
'2rgmi' => 'WC',
'2rhii' => 'WC',
'2riii' => 'WC',
'2rioi' => 'WC',
'2rjii' => 'WC',
'2rk' => 'WC',
'2rkbi' => 'WC',
'2rkca' => 'WC',
'2rker' => 'WC',
'2rkga' => 'WC',
'2rkgn' => 'WC',
'2rkii' => 'WC',
'2rkka' => 'WC',
'2rkma' => 'WC',
'2rkmf' => 'WC',
'2rkna' => 'WC',
'2rknf' => 'WC',
'2rkpb' => 'WC',
'2rkpo' => 'WC',
'2rksa' => 'WC',
'2rkta' => 'WC',
'2rkyf' => 'WC',
'2rmii' => 'WC',
'2rnii' => 'WC',
'2rpbi' => 'WC',
'2rpci' => 'WC',
'2rpoi' => 'WC',
'2rqii' => 'WC',
'2rr3i' => 'WC',
'2rrai' => 'WC',
'2rrci' => 'WC',
'2rrii' => 'WC',
'2rrni' => 'WC',
'2rrxi' => 'WC',
'2rsii' => 'WC',
'2ru' => 'WC',
'2ruii' => 'WC',
'2rvdi' => 'WC',
'2rvhs' => 'WC',
'2rvii' => 'WC',
'2rw' => 'WC',
'2rwdi' => 'WC',
'2rwii' => 'WC',
'2rxii' => 'WC',
'2rxri' => 'WC',
'2ryii' => 'WC',
'2tb' => 'WC',
'2tebk' => 'WC',
'wdaii' => 'WWU',
'wdb' => 'WWU',
'wdbii' => 'WWU',
'wdcii' => 'WWU',
'wdcli' => 'WWU',
'wddii' => 'WWU',
'wddsi' => 'WWU',
'wdeai' => 'WWU',
'wdeki' => 'WWU',
'wdett' => 'WWU',
'wdevi' => 'WWU',
'wdeyi' => 'WWU',
'wdfii' => 'WWU',
'wdgii' => 'WWU',
'wdgsi' => 'WWU',
'wdhii' => 'WWU',
'wdiii' => 'WWU',
'wdjii' => 'WWU',
'wdkii' => 'WWU',
'wdlri' => 'WWU',
'wdmii' => 'WWU',
'wdnii' => 'WWU',
'wdoii' => 'WWU',
'wdpii' => 'WWU',
'wdqii' => 'WWU',
'wdrii' => 'WWU',
'wdtii' => 'WWU',
'wdu' => 'WWU',
'wduii' => 'WWU',
'wdvii' => 'WWU',
'wdvsi' => 'WWU',
'wdw' => 'WWU',
'wdwdi' => 'WWU',
'wdxii' => 'WWU',
'wdyii' => 'WWU',
'wwawd' => 'WWU',
  );
  return \%mapping;
  
}

sub locationNormalize_avalon
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'kcb' => 'ATSU',
'kciii' => 'ATSU',
'kcmii' => 'ATSU',
'kcsii' => 'ATSU',
'kcxii' => 'ATSU',
'keb' => 'ATSU',
'keiii' => 'ATSU',
'kelii' => 'ATSU',
'khiii' => 'ATSU',
'klaii' => 'ATSU',
'klb' => 'ATSU',
'kldii' => 'ATSU',
'kleii' => 'ATSU',
'kleov' => 'ATSU',
'klepi' => 'ATSU',
'kliii' => 'ATSU',
'kljii' => 'ATSU',
'kllii' => 'ATSU',
'klmdv' => 'ATSU',
'klmei' => 'ATSU',
'klmii' => 'ATSU',
'klmki' => 'ATSU',
'klmmi' => 'ATSU',
'klmoi' => 'ATSU',
'klmso' => 'ATSU',
'klnii' => 'ATSU',
'kloji' => 'ATSU',
'klosi' => 'ATSU',
'klpii' => 'ATSU',
'klrii' => 'ATSU',
'klrsi' => 'ATSU',
'klsii' => 'ATSU',
'klsvi' => 'ATSU',
'kltii' => 'ATSU',
'kltsi' => 'ATSU',
'klxii' => 'ATSU',
'koiii' => 'ATSU',
'ksiii' => 'ATSU',
'kub' => 'ATSU',
'kudii' => 'ATSU',
'kuiii' => 'ATSU',
'kuwii' => 'ATSU',
'kzaii' => 'ATSU',
'kzb' => 'ATSU',
'kziii' => 'ATSU',
'kzmii' => 'ATSU',
'kzrii' => 'ATSU',
'kzsii' => 'ATSU',
'kzxii' => 'ATSU',
'mfaci' => 'CMU',
'mfami' => 'CMU',
'mfari' => 'CMU',
'mfarm' => 'CMU',
'mfaya' => 'CMU',
'mfb' => 'CMU',
'mfbci' => 'CMU',
'mfbii' => 'CMU',
'mfbio' => 'CMU',
'mfdii' => 'CMU',
'mfdvd' => 'CMU',
'mfeii' => 'CMU',
'mferi' => 'CMU',
'mfgii' => 'CMU',
'mfgnc' => 'CMU',
'mfjii' => 'CMU',
'mfmri' => 'CMU',
'mfmsi' => 'CMU',
'mfpii' => 'CMU',
'mfq3i' => 'CMU',
'mfr2i' => 'CMU',
'mfrdi' => 'CMU',
'mfrii' => 'CMU',
'mfrmi' => 'CMU',
'mfrri' => 'CMU',
'mfsii' => 'CMU',
'mfu' => 'CMU',
'mfuii' => 'CMU',
'mfxii' => 'CMU',
'mob' => 'CMU',
'moiii' => 'CMU',
'mpb' => 'CMU',
'mpcii' => 'CMU',
'mpe' => 'CMU',
'mpecc' => 'CMU',
'mpeji' => 'CMU',
'mpepi' => 'CMU',
'mpeqi' => 'CMU',
'mperi' => 'CMU',
'mpjii' => 'CMU',
'mppii' => 'CMU',
'mpqii' => 'CMU',
'mprii' => 'CMU',
'cjarb' => 'CSC',
'cjarc' => 'CSC',
'cjb' => 'CSC',
'cjcur' => 'CSC',
'cjdau' => 'CSC',
'cjdii' => 'CSC',
'cjdil' => 'CSC',
'cjdnr' => 'CSC',
'cjdvd' => 'CSC',
'cjeki' => 'CSC',
'cjiii' => 'CSC',
'cjint' => 'CSC',
'cjmus' => 'CSC',
'cjofd' => 'CSC',
'cjref' => 'CSC',
'cjsbi' => 'CSC',
'cjscd' => 'CSC',
'cjsfc' => 'CSC',
'cjsjf' => 'CSC',
'cjsjn' => 'CSC',
'cjsnf' => 'CSC',
'cjspe' => 'CSC',
'cjub' => 'CSC',
'cjwii' => 'CSC',
'hlaii' => 'HLGU',
'hlb' => 'HLGU',
'hlead' => 'HLGU',
'hleai' => 'HLGU',
'hlecm' => 'HLGU',
'hlefa' => 'HLGU',
'hlefs' => 'HLGU',
'hlepa' => 'HLGU',
'hlers' => 'HLGU',
'hlesc' => 'HLGU',
'hlesp' => 'HLGU',
'hlewi' => 'HLGU',
'hlgai' => 'HLGU',
'hlgcr' => 'HLGU',
'hlgii' => 'HLGU',
'hlgje' => 'HLGU',
'hlgjf' => 'HLGU',
'hlgjg' => 'HLGU',
'hlgjj' => 'HLGU',
'hlgjv' => 'HLGU',
'hlgjx' => 'HLGU',
'hlgjy' => 'HLGU',
'hlgmn' => 'HLGU',
'hlgqb' => 'HLGU',
'hlgqi' => 'HLGU',
'hlgrs' => 'HLGU',
'hlgsi' => 'HLGU',
'hlgsp' => 'HLGU',
'hlgwi' => 'HLGU',
'hlint' => 'HLGU',
'hlkca' => 'HLGU',
'hlkcd' => 'HLGU',
'hlkcr' => 'HLGU',
'hlkii' => 'HLGU',
'hlkip' => 'HLGU',
'hlkir' => 'HLGU',
'hlkis' => 'HLGU',
'hlksl' => 'HLGU',
'hlktr' => 'HLGU',
'hlkvd' => 'HLGU',
'hlkvi' => 'HLGU',
'hlkzz' => 'HLGU',
'hllci' => 'HLGU',
'hllii' => 'HLGU',
'hloii' => 'HLGU',
'hlpcn' => 'HLGU',
'hlpii' => 'HLGU',
'hlpnc' => 'HLGU',
'hlppf' => 'HLGU',
'hlpsb' => 'HLGU',
'hlrdi' => 'HLGU',
'hlrii' => 'HLGU',
'hlrmi' => 'HLGU',
'hlrsi' => 'HLGU',
'hlrti' => 'HLGU',
'hlrwi' => 'HLGU',
'hlspi' => 'HLGU',
'hlspm' => 'HLGU',
'hlssi' => 'HLGU',
'hlssm' => 'HLGU',
'hlxgi' => 'HLGU',
'hlxpi' => 'HLGU',
'hlxri' => 'HLGU',
'hpgii' => 'HLGU',
'hpkav' => 'HLGU',
'hprii' => 'HLGU',
'hpsii' => 'HLGU',
'hub' => 'HLGU',
'hudii' => 'HLGU',
'huiii' => 'HLGU',
'mbaii' => 'MACC',
'mbb' => 'MACC',
'mbcii' => 'MACC',
'mbeii' => 'MACC',
'mbfii' => 'MACC',
'mbgii' => 'MACC',
'mblii' => 'MACC',
'mbqii' => 'MACC',
'mbrii' => 'MACC',
'mbsii' => 'MACC',
'mbtii' => 'MACC',
'mbxii' => 'MACC',
'mcaii' => 'MACC',
'mcb' => 'MACC',
'mceci' => 'MACC',
'mcgii' => 'MACC',
'mcrii' => 'MACC',
'mcxii' => 'MACC',
'mhaii' => 'MACC',
'mhb' => 'MACC',
'mhgii' => 'MACC',
'mhrii' => 'MACC',
'mhxii' => 'MACC',
'mkaii' => 'MACC',
'mkb' => 'MACC',
'mkgii' => 'MACC',
'mkrii' => 'MACC',
'mkxii' => 'MACC',
'mub' => 'MACC',
'multi' => 'MACC',
'muwii' => 'MACC',
'mxaii' => 'MACC',
'mxb' => 'MACC',
'mxgii' => 'MACC',
'mxrii' => 'MACC',
'mxsii' => 'MACC',
'mxxii' => 'MACC',
'vaaii' => 'MVC',
'vab' => 'MVC',
'vacii' => 'MVC',
'vaeii' => 'MVC',
'vaiii' => 'MVC',
'vajii' => 'MVC',
'vavii' => 'MVC',
'veaub' => 'MVC',
'veb' => 'MVC',
'veebk' => 'MVC',
'vestv' => 'MVC',
'vevda' => 'MVC',
'vmabk' => 'MVC',
'vmaii' => 'MVC',
'vmb' => 'MVC',
'vmcii' => 'MVC',
'vmeii' => 'MVC',
'vmfii' => 'MVC',
'vmiii' => 'MVC',
'vmjii' => 'MVC',
'vmlii' => 'MVC',
'vmmii' => 'MVC',
'vmpii' => 'MVC',
'vmroi' => 'MVC',
'vmrrm' => 'MVC',
'vmsii' => 'MVC',
'vmu' => 'MVC',
'vmuii' => 'MVC',
'vmw' => 'MVC',
'vmxii' => 'MVC',
'sfaii' => 'SFCC',
'sfb' => 'SFCC',
'sfbl' => 'SFCC',
'sfcb' => 'SFCC',
'sfcc' => 'SFCC',
'sfcui' => 'SFCC',
'sfdii' => 'SFCC',
'sfdpi' => 'SFCC',
'sfeii' => 'SFCC',
'sfgii' => 'SFCC',
'sfjii' => 'SFCC',
'sfjki' => 'SFCC',
'sfjpi' => 'SFCC',
'sfmii' => 'SFCC',
'sfmri' => 'SFCC',
'sfovr' => 'SFCC',
'sfpii' => 'SFCC',
'sfrii' => 'SFCC',
'sfspi' => 'SFCC',
'sftii' => 'SFCC',
'sfu' => 'SFCC',
'sfuii' => 'SFCC',
'sfw' => 'SFCC',
'sfwii' => 'SFCC',
'sfxii' => 'SFCC',
'sfyai' => 'SFCC',
'lmatc' => 'STC',
'lmb' => 'STC',
'lpbii' => 'STC',
'lsaai' => 'STC',
'lsaii' => 'STC',
'lsb' => 'STC',
'lscdi' => 'STC',
'lsdvi' => 'STC',
'lseji' => 'STC',
'lseqi' => 'STC',
'lsfic' => 'STC',
'lsfni' => 'STC',
'lsgci' => 'STC',
'lsili' => 'STC',
'lsini' => 'STC',
'lsmai' => 'STC',
'lsnsi' => 'STC',
'lsoii' => 'STC',
'lspei' => 'STC',
'lspoi' => 'STC',
'lsrfi' => 'STC',
'lsrpi' => 'STC',
'lsxii' => 'STC',
'lub' => 'STC',
'ludii' => 'STC',
'luiii' => 'STC',
'luwii' => 'STC',
'tp7ii' => 'TRUMAN',
'tp8ii' => 'TRUMAN',
'tp9ii' => 'TRUMAN',
'tpaii' => 'TRUMAN',
'tpaji' => 'TRUMAN',
'tpati' => 'TRUMAN',
'tpb' => 'TRUMAN',
'tpcii' => 'TRUMAN',
'tpdhi' => 'TRUMAN',
'tpdii' => 'TRUMAN',
'tpeei' => 'TRUMAN',
'tpeni' => 'TRUMAN',
'tpfci' => 'TRUMAN',
'tpffi' => 'TRUMAN',
'tpfhi' => 'TRUMAN',
'tpfni' => 'TRUMAN',
'tpfri' => 'TRUMAN',
'tpgbi' => 'TRUMAN',
'tpgii' => 'TRUMAN',
'tpgni' => 'TRUMAN',
'tpgoi' => 'TRUMAN',
'tpjii' => 'TRUMAN',
'tplst' => 'TRUMAN',
'tpmai' => 'TRUMAN',
'tpmbi' => 'TRUMAN',
'tpmci' => 'TRUMAN',
'tpmdi' => 'TRUMAN',
'tpmgi' => 'TRUMAN',
'tpmii' => 'TRUMAN',
'tpmki' => 'TRUMAN',
'tpmli' => 'TRUMAN',
'tpmmi' => 'TRUMAN',
'tpmri' => 'TRUMAN',
'tpmsi' => 'TRUMAN',
'tpmti' => 'TRUMAN',
'tpmvi' => 'TRUMAN',
'tpobi' => 'TRUMAN',
'tpohi' => 'TRUMAN',
'tpoii' => 'TRUMAN',
'tponi' => 'TRUMAN',
'tpopi' => 'TRUMAN',
'tppbi' => 'TRUMAN',
'tppci' => 'TRUMAN',
'tppii' => 'TRUMAN',
'tppni' => 'TRUMAN',
'tprdi' => 'TRUMAN',
'tprii' => 'TRUMAN',
'tproi' => 'TRUMAN',
'tpsai' => 'TRUMAN',
'tpsbi' => 'TRUMAN',
'tpsfi' => 'TRUMAN',
'tpsfp' => 'TRUMAN',
'tpsgi' => 'TRUMAN',
'tpshi' => 'TRUMAN',
'tpshp' => 'TRUMAN',
'tpsii' => 'TRUMAN',
'tpski' => 'TRUMAN',
'tpsli' => 'TRUMAN',
'tpslp' => 'TRUMAN',
'tpsni' => 'TRUMAN',
'tpsoi' => 'TRUMAN',
'tpssi' => 'TRUMAN',
'tpssp' => 'TRUMAN',
'tpsvi' => 'TRUMAN',
'tpswi' => 'TRUMAN',
'tptii' => 'TRUMAN',
'tpvii' => 'TRUMAN',
'tpxii' => 'TRUMAN',
'tpyii' => 'TRUMAN',
'tpzci' => 'TRUMAN',
'tpzii' => 'TRUMAN',
'tpzpi' => 'TRUMAN',
'tub' => 'TRUMAN',
'tudii' => 'TRUMAN',
'tupii' => 'TRUMAN',
'tuwii' => 'TRUMAN',
  );
  return \%mapping;
  
}

sub locationNormalize_archway
{
  my $code = shift;
  my $ret = "MCO";
  my %mapping =
  (
'eaiii' => 'ECC',
'ecb' => 'ECC',
'eccai' => 'ECC',
'eccii' => 'ECC',
'eccri' => 'ECC',
'eccvi' => 'ECC',
'eccxi' => 'ECC',
'ece' => 'ECC',
'eceii' => 'ECC',
'echii' => 'ECC',
'eci' => 'ECC',
'eciii' => 'ECC',
'ecj' => 'ECC',
'ecjii' => 'ECC',
'ecjyi' => 'ECC',
'ecoii' => 'ECC',
'ecpii' => 'ECC',
'ecr' => 'ECC',
'ecrai' => 'ECC',
'ecrii' => 'ECC',
'ecsbi' => 'ECC',
'ecsli' => 'ECC',
'ecsmi' => 'ECC',
'ecssi' => 'ECC',
'ecu' => 'ECC',
'ecuii' => 'ECC',
'ecv' => 'ECC',
'ecw' => 'ECC',
'erb' => 'ECC',
'errrr' => 'ECC',
'jab' => 'JC',
'jh02i' => 'JC',
'jh11i' => 'JC',
'jh92i' => 'JC',
'jha2g' => 'JC',
'jhb' => 'JC',
'jhc2i' => 'JC',
'jhd2i' => 'JC',
'jhe' => 'JC',
'jheii' => 'JC',
'jheri' => 'JC',
'jhf1i' => 'JC',
'jhfc2' => 'JC',
'jhfcp' => 'JC',
'jhg' => 'JC',
'jhg2c' => 'JC',
'jhg2f' => 'JC',
'jhg2g' => 'JC',
'jhg2i' => 'JC',
'jhh2i' => 'JC',
'jhj' => 'JC',
'jhj2f' => 'JC',
'jhj2n' => 'JC',
'jhk2p' => 'JC',
'jhm' => 'JC',
'jhm2i' => 'JC',
'jho1c' => 'JC',
'jho1n' => 'JC',
'jho1p' => 'JC',
'jhp' => 'JC',
'jhp1m' => 'JC',
'jhp1n' => 'JC',
'jhp1p' => 'JC',
'jhq2i' => 'JC',
'jhr' => 'JC',
'jhr1i' => 'JC',
'jht1t' => 'JC',
'jhts2' => 'JC',
'jhu' => 'JC',
'jhuii' => 'JC',
'jhuwi' => 'JC',
'jhv2i' => 'JC',
'jhx' => 'JC',
'jhxii' => 'JC',
'jhz2i' => 'JC',
'jixii' => 'JC',
'jnxii' => 'JC',
'mcacd' => 'MAC',
'mcact' => 'MAC',
'mcadv' => 'MAC',
'mcaf6' => 'MAC',
'mcaf8' => 'MAC',
'mcafs' => 'MAC',
'mcaki' => 'MAC',
'mcb' => 'MAC',
'mccma' => 'MAC',
'mcecp' => 'MAC',
'mcf' => 'MAC',
'mcgen' => 'MAC',
'mcjuv' => 'MAC',
'mcmic' => 'MAC',
'mcmun' => 'MAC',
'mcp' => 'MAC',
'mcpam' => 'MAC',
'mcser' => 'MAC',
'mcsmo' => 'MAC',
'mcv2d' => 'MAC',
'mcyea' => 'MAC',
'mub' => 'MAC',
'mudii' => 'MAC',
'muiii' => 'MAC',
'multi' => 'MAC',
'muwii' => 'MAC',
'chlpi' => 'SCC',
'chlri' => 'SCC',
'claii' => 'SCC',
'claxi' => 'SCC',
'clb' => 'SCC',
'cle' => 'SCC',
'cleii' => 'SCC',
'cleni' => 'SCC',
'clgai' => 'SCC',
'clgii' => 'SCC',
'clgni' => 'SCC',
'clj' => 'SCC',
'cljii' => 'SCC',
'cllii' => 'SCC',
'cloii' => 'SCC',
'clp' => 'SCC',
'clpii' => 'SCC',
'clr' => 'SCC',
'clrdi' => 'SCC',
'clrii' => 'SCC',
'clu' => 'SCC',
'cluui' => 'SCC',
'clw' => 'SCC',
'clxii' => 'SCC',
'laele' => 'STLCC',
'laldr' => 'STLCC',
'lmacc' => 'STLCC',
'lmarc' => 'STLCC',
'lmatl' => 'STLCC',
'lmb' => 'STLCC',
'lmbes' => 'STLCC',
'lmchi' => 'STLCC',
'lmcix' => 'STLCC',
'lmcla' => 'STLCC',
'lmctl' => 'STLCC',
'lmdic' => 'STLCC',
'lmfic' => 'STLCC',
'lmind' => 'STLCC',
'lmlea' => 'STLCC',
'lmlex' => 'STLCC',
'lmmed' => 'STLCC',
'lmove' => 'STLCC',
'lmper' => 'STLCC',
'lmref' => 'STLCC',
'lmsce' => 'STLCC',
'lmscr' => 'STLCC',
'lmscx' => 'STLCC',
'lmsta' => 'STLCC',
'lmtal' => 'STLCC',
'lmu' => 'STLCC',
'lmuns' => 'STLCC',
'lmver' => 'STLCC',
'lmw' => 'STLCC',
'lpach' => 'STLCC',
'lpacq' => 'STLCC',
'lpafr' => 'STLCC',
'lparc' => 'STLCC',
'lpatl' => 'STLCC',
'lpb' => 'STLCC',
'lpbes' => 'STLCC',
'lpchi' => 'STLCC',
'lpcix' => 'STLCC',
'lpctl' => 'STLCC',
'lpfic' => 'STLCC',
'lphec' => 'STLCC',
'lpher' => 'STLCC',
'lpind' => 'STLCC',
'lplea' => 'STLCC',
'lplex' => 'STLCC',
'lpmed' => 'STLCC',
'lpmic' => 'STLCC',
'lpnew' => 'STLCC',
'lpove' => 'STLCC',
'lpper' => 'STLCC',
'lpref' => 'STLCC',
'lpsta' => 'STLCC',
'lptlc' => 'STLCC',
'lpu' => 'STLCC',
'lpuns' => 'STLCC',
'lpw' => 'STLCC',
'lvacq' => 'STLCC',
'lvarc' => 'STLCC',
'lvatl' => 'STLCC',
'lvb' => 'STLCC',
'lvbes' => 'STLCC',
'lvchi' => 'STLCC',
'lvcir' => 'STLCC',
'lvcix' => 'STLCC',
'lvcxx' => 'STLCC',
'lvfic' => 'STLCC',
'lvind' => 'STLCC',
'lvmex' => 'STLCC',
'lvmxx' => 'STLCC',
'lvper' => 'STLCC',
'lvref' => 'STLCC',
'lvsta' => 'STLCC',
'lvu' => 'STLCC',
'lvuns' => 'STLCC',
'lvvis' => 'STLCC',
'lvw' => 'STLCC',
'lwb' => 'STLCC',
'lwbes' => 'STLCC',
'lwcar' => 'STLCC',
'lwchi' => 'STLCC',
'lwcix' => 'STLCC',
'lwfic' => 'STLCC',
'lwlea' => 'STLCC',
'lwove' => 'STLCC',
'lwper' => 'STLCC',
'lwref' => 'STLCC',
'lwsta' => 'STLCC',
'lwu' => 'STLCC',
'lwuns' => 'STLCC',
'lww' => 'STLCC',
'lwwit' => 'STLCC',
'lyarc' => 'STLCC',
'lyb' => 'STLCC',
'lymic' => 'STLCC',
'lzb' => 'STLCC',
'lzmic' => 'STLCC',
'lzsta' => 'STLCC',
'lzu' => 'STLCC',
'lzuns' => 'STLCC',
'lzvid' => 'STLCC',
'lzw' => 'STLCC',
'traai' => 'TRC',
'trasi' => 'TRC',
'travi' => 'TRC',
'trb' => 'TRC',
'trbii' => 'TRC',
'trc' => 'TRC',
'trers' => 'TRC',
'trgii' => 'TRC',
'trjii' => 'TRC',
'trk' => 'TRC',
'trm' => 'TRC',
'trmii' => 'TRC',
'trp' => 'TRC',
'trrai' => 'TRC',
'trrgi' => 'TRC',
'trrii' => 'TRC',
'trrni' => 'TRC',
'trs' => 'TRC',
'trsii' => 'TRC',
'trspi' => 'TRC',
'trx2w' => 'TRC',
'trxhi' => 'TRC',
'trxti' => 'TRC',
'trxwi' => 'TRC',
'tub' => 'TRC',
'tudii' => 'TRC',
'tuiii' => 'TRC',
'tuwii' => 'TRC',
'pca' => 'UHSP',
'pcabi' => 'UHSP',
'pcaji' => 'UHSP',
'pcati' => 'UHSP',
'pce' => 'UHSP',
'pcerc' => 'UHSP',
'pcj' => 'UHSP',
'pcjii' => 'UHSP',
'pcjmi' => 'UHSP',
'pcl' => 'UHSP',
'pclbc' => 'UHSP',
'pclbn' => 'UHSP',
'pclbo' => 'UHSP',
'pclct' => 'UHSP',
'pcleb' => 'UHSP',
'pcllr' => 'UHSP',
'pclsb' => 'UHSP',
'pcltr' => 'UHSP',
'pclvs' => 'UHSP',
'pclvt' => 'UHSP',
'pclwc' => 'UHSP',
'pco' => 'UHSP',
'pcoar' => 'UHSP',
'pcoci' => 'UHSP',
'pcodi' => 'UHSP',
'pcori' => 'UHSP',
'pcr' => 'UHSP',
'pcrbi' => 'UHSP',
'pcs' => 'UHSP',
'pcsve' => 'UHSP',
'pcsxi' => 'UHSP',
'pcu' => 'UHSP',
'pcudi' => 'UHSP',
'pcuii' => 'UHSP',
'pcuwi' => 'UHSP',
'pcv' => 'UHSP',
'pcvci' => 'UHSP',
'pcvdt' => 'UHSP',
'pcz' => 'UHSP',
  );
  return \%mapping;
  
}

sub getLocationSQLMap
{
    my $ret = '';
    my %mapping;
    my $functionCall = '%mapping = %{locationNormalize_' . $conf{"libraryname"} . '()};';
    eval($functionCall);
    while ( (my $key, my $value) = each(%mapping) )
    {
        $ret .= "SELECT '$key' \"oldname\", '$value' \"newname\" union all\n";
    }
    $ret = substr($ret,0,-10);
    return $ret;
}

sub getFOLIOInstitution
{
    my $thisLoc = shift;
    my %mapping;
    my $functionCall = '%mapping = %{locationNormalize_' . $conf{"libraryname"} . '()};';
    eval($functionCall);
    my $institutionName = $mapping{$thisLoc};
    $institutionName = "MCO" if !$institutionName;
    $institutionName =~ s/[\t\s\\',\.]*//g;
    return $institutionName;
}

    
exit;







############### Disabled non-used queries

	# # get patron fines
	# my $query = "
		# select * from sierra_view.fine where
		# patron_record_id in
		# (
		# select id from sierra_view.patron_view where ($patronlocationcodes)
		# )
	# ";
	# setupEGTable($query, $institutionName . ".fine", $firstrun);

	# #get patron fines paid
	# my $query = "
		# select * from sierra_view.fines_paid where
		# patron_record_metadata_id in
		# (
		# select id from sierra_view.patron_view where ($patronlocationcodes)
		# )
	# ";
	# setupEGTable($query, $institutionName . ".fines_paid", $firstrun);

	# #get bibs - minus title column
	# my $query = "select id,
    # record_type_code,
    # record_num,
    # language_code,
    # bcode1,
    # bcode2,
    # bcode3,
    # country_code,
    # is_available_at_library,
    # index_change_count,
    # allocation_rule_code,
    # is_on_course_reserve,
    # is_right_result_exact,
    # skip_num,
    # cataloging_date_gmt,
    # marc_type_code,
    # record_creation_date_gmt
    # from sierra_view.bib_view where id in
	# (
		# SELECT brbl.BIB_RECORD_ID FROM
        # SIERRA_VIEW.BIB_RECORD_LOCATION brbl
        # left join SIERRA_VIEW.BIB_RECORD_LOCATION svbrl on(brbl.bib_record_id=svbrl.bib_record_id and svbrl.LOCATION_CODE in ($sierrapreviouslocationcodes))
        # WHERE
		# ($sierralocationcodes) and
        # svbrl.bib_record_id is null
        # !!orderlimit!!
	# )
	# ";
	# setupEGTable($query,"bib_view", $firstrun);

	# #get items
	# my $query = "select * from sierra_view.item_view brbl where ($sierralocationcodes)";
	# setupEGTable($query,"item_view", $firstrun);

	# #get items bib links
	# my $query = "
		# select * from sierra_view.bib_record_item_record_link where bib_record_id
		# in
		# (
			# select id from sierra_view.bib_view where id in
			# (
				# SELECT brbl.BIB_RECORD_ID FROM
                # SIERRA_VIEW.BIB_RECORD_LOCATION brbl
                # left join SIERRA_VIEW.BIB_RECORD_LOCATION svbrl on(brbl.bib_record_id=svbrl.bib_record_id and svbrl.LOCATION_CODE in ($sierrapreviouslocationcodes))
                # WHERE
                # ($sierralocationcodes) and
                # svbrl.bib_record_id is null
                # !!orderlimit!!
			# )
		# )
	# ";
	# setupEGTable($query,"bib_record_item_record_link", $firstrun);

	# #get patron messages
	# my $query = "
		# select * from sierra_view.varfield_view where record_type_code='p' and
		# record_id in
		# (
			# select id from sierra_view.patron_view where ($patronlocationcodes)
		# )
	# ";
	# setupEGTable($query,"patron_varfield_view", $firstrun);

	# #get item extra
	# my $query = "
		# select * from sierra_view.varfield_view where record_type_code='i' and varfield_type_code='y' and
		# record_id in
		# (
			# select item_record_id from sierra_view.bib_record_item_record_link where bib_record_id
			# in
			# (
				# select id from sierra_view.bib_view where id in
				# (
					# SELECT brbl.BIB_RECORD_ID FROM
                    # SIERRA_VIEW.BIB_RECORD_LOCATION brbl
                    # left join SIERRA_VIEW.BIB_RECORD_LOCATION svbrl on(brbl.bib_record_id=svbrl.bib_record_id and svbrl.LOCATION_CODE in ($sierrapreviouslocationcodes))
                    # WHERE
                    # ($sierralocationcodes) and
                    # svbrl.bib_record_id is null
                    # !!orderlimit!!
				# )
			# )
		# )
	# ";
	# setupEGTable($query,"item_varfield_view", $firstrun);

	# #get holds
	# my $query = "
        # select * from
        # sierra_view.hold
        # where patron_record_id in
        # (
            # select id from sierra_view.patron_view where ($patronlocationcodes)
        # )
	# ";
	# setupEGTable($query,$institutionName . ".patron_holds", $firstrun);

    # #get holds metadata
	# my $query = "
        # select * from
        # sierra_view.record_metadata
        # where id in
        # (
            # select record_id from
                # sierra_view.hold
                # where patron_record_id in
                # (
                    # select id from sierra_view.patron_view where ($patronlocationcodes)
                # )
        # )
	# ";
	# setupEGTable($query,$institutionName . ".record_metadata", $firstrun);

    ## proquest counts
    # my $query =<<'splitter';
# select svln.name,count(distinct svvv.record_id) from
# sierra_view.location_name svln
# join sierra_view.location svl on(svl.id=svln.location_id and !!!sierralocationcodes!!!)
# join sierra_view.item_view sviv on(sviv.location_code=svl.code)
# join sierra_view.bib_record_item_record_link svbrirl on(svbrirl.item_record_id=sviv.id)
# join (
# select record_id from sierra_view.varfield_view
# where
		# record_type_code='b' and
        # marc_tag='856' and
		# field_content~'ebookcentral\.proquest\.com' and
        # record_id in
        # (
			# select svrirl2.bib_record_id from
            # sierra_view.bib_record_item_record_link svrirl2
			# join sierra_view.item_view brbl on(svrirl2.item_record_id=brbl.id and !!!sierralocationcodes_og!!!)
        # )
        # !!orderlimit!!
        # ) svvv
	# on( svvv.record_id=svbrirl.bib_record_id )
# group by 1
# splitter

    # my $t = $sierralocationcodes;
    # $t =~ s/^brbl/svl/g;
    # $t =~ s/LOCATION_CODE/code/g;
    # $query =~ s/!!!sierralocationcodes_og!!!/$sierralocationcodes/g;
    # $query =~ s/!!!sierralocationcodes!!!/$t/g;
    # setupEGTable($query, $configFile."_proquest_stats", $firstrun);
