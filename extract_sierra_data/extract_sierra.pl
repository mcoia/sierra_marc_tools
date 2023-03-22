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
$log->truncFile("");
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

$dbHandler->query("drop schema $schema cascade");
$dbHandler->query("create schema $schema");
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


my @sp = @{getLocationCodes()};
my $firstrun = 1;
foreach(@sp)
{
    my $thisLoc = $_;
    my $sierralocationcodes="brbl.LOCATION_CODE=\$\$$thisLoc\$\$";
    my $sierrapreviouslocationcodes = "";
    $sierrapreviouslocationcodes .= "\$\$$_\$\$," foreach(@previousLocs);
    $sierrapreviouslocationcodes = substr($sierrapreviouslocationcodes,0,-1);


    my $patronlocationcodes = $sierralocationcodes;
    $patronlocationcodes =~ s/brbl\.LOCATION_CODE/home_library_code/g;

    shift @previousLocs if $firstrun; # remove the 0-byte string from the beginning of the array
    push @previousLocs, $thisLoc;

    print "$thisLoc\n";
        
    
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
	
    # FOLIO Item File
    my $query =<<'splitter';
select
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct 'b'||bib.record_num,'!delem!' order by 'b'||bib.record_num),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"bib_ids",
concat('i', item.record_num) "record_num", --RECORD #(Item)
item_prop.call_number "item_call_no", --CALL #(Item)
(
select
btrim(
regexp_replace(
regexp_replace(regexp_replace(string_agg("bcall",'!delem!')
,'\|.',' ','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
)
from
(
select
string_agg(btrim(field_content),'' order by occ_num) "bcall",record_id
from sierra_view.varfield_view bib_call where record_id = any (('{'||string_agg(distinct bib.id::text,','::text)||'}')::bigint[]) and record_type_code='b' and marc_tag in( '090', '092' ) and field_content ~'^\|a'  group by 2) as b
) as  
"bib_call_nos", --CALL #(Bibliographic)
item.barcode,
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
regexp_replace(regexp_replace(string_agg(distinct item_volume.field_content,'!delem!' ),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
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
regexp_replace(regexp_replace(string_agg(distinct item_message.field_content,'!delem!' ),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"message",
item_note.note

from
sierra_view.item_view item
join sierra_view.bib_record_item_record_link bib_item_link on ( bib_item_link.item_record_id = item.id)
join sierra_view.bib_view bib on ( bib.id = bib_item_link.bib_record_id )
join sierra_view.record_metadata metarecord on(metarecord.id=item.id)
left join (
select
regexp_replace(
regexp_replace(regexp_replace(string_agg(btrim(call_number_norm),'!delem!'),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g') "call_number",item_record_id
 from sierra_view.item_record_property group by 2
) as "item_prop" on(item_prop.item_record_id=item.id)
left join sierra_view.varfield_view item_message on(item_message.record_id = item.id and item_message.varfield_type_code='m' and item_message.marc_tag is null)
left join (
select
regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct item_note.field_content,'!delem!' ),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"note", record_id from sierra_view.varfield_view item_note where item_note.varfield_type_code in ('x','n') and item_note.marc_tag is null group by 2) item_note on(item_note.record_id = item.id )
left join sierra_view.varfield_view item_volume on(item_volume.record_id = item.id and item_volume.varfield_type_code = 'v' and item_volume.marc_tag is null)
where
!!!sierralocationcodes!!!
group by 2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18,20,21,22,23,24,25,26,27,28,29,31
splitter

    my $t = $sierralocationcodes;
    $t =~ s/^brbl/item/g;
    $query =~ s/!!!sierralocationcodes!!!/$t/g;
    setupEGTable($query,"folio_items", $firstrun);


    #FOLIO Patron File
    my $query =<<'splitter';

 select
concat('p', patron.record_num) "patron_num",

-- Names
regexp_replace(
regexp_replace(regexp_replace(string_agg(pname.last_name,'!delem!' ORDER BY pname.display_order),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"last_name",


regexp_replace(
regexp_replace(regexp_replace(string_agg(pname.first_name,'!delem!' ORDER BY pname.id),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"first_name",

regexp_replace(
regexp_replace(regexp_replace(string_agg(pname.middle_name,'!delem!' ORDER BY pname.id),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"middle_name",

patron.barcode,

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pvisibleid.field_content,'!delem!'),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"visible_patron_id",

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pphone.phone_number,'!delem!'),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"phone_number",

regexp_replace(
regexp_replace(regexp_replace(string_agg(distinct pemail.field_content,'!delem!'),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
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
regexp_replace(regexp_replace(string_agg(distinct pnote.field_content,'!delem!'),'\|.','!delem!','g'),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
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
paddress.country


from
sierra_view.patron_view patron
join sierra_view.record_metadata pmetarecord on(pmetarecord.id=patron.id and pmetarecord.record_type_code='p')
left join sierra_view.patron_record_fullname pname on(pname.patron_record_id=patron.id)
left join sierra_view.varfield_view pemail on(pemail.record_type_code='p' and pemail.field_content~'[^@]+@[^\.]+\.\D{2,}' and pemail.record_id=patron.id)
left join sierra_view.patron_record_phone pphone on(pphone.patron_record_id=patron.id)
left join sierra_view.varfield_view pnote on(pnote.varfield_type_code='x' and pnote.record_id=patron.id)
left join sierra_view.varfield_view pvisibleid on(pvisibleid.varfield_type_code='u' and pvisibleid.record_id=patron.id)
left join (select 

-- Address section
patron_record_id,
regexp_replace(
regexp_replace(string_agg(patron_record_address_type_id::text,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"patron_record_address_type_id",

regexp_replace(
regexp_replace(string_agg(addr1,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"addr1",
regexp_replace(
regexp_replace(string_agg(addr2,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"addr2",

regexp_replace(
regexp_replace(string_agg(addr3,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"addr3",

regexp_replace(
regexp_replace(string_agg(village,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"village",

regexp_replace(
regexp_replace(string_agg(city,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"city",

regexp_replace(
regexp_replace(string_agg(region,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"region",

regexp_replace(
regexp_replace(string_agg(postal_code,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
"postal_code",

regexp_replace(
regexp_replace(string_agg(country,'!delem!' order by display_order),'^!delem!','','g'),
'!delem!!delem!','!delem!','g')
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
    setupEGTable($query,"folio_patrons", $firstrun);

	#get patrons
	my $query = "
		select * from sierra_view.patron_view pview join sierra_view.record_metadata precord on(precord.id=pview.id and precord.record_type_code='p') where ($patronlocationcodes) 
	";
	setupEGTable($query,"patron_view", $firstrun);
	
  
  
	#get patron addresses	
	my $query = "
		select * from sierra_view.patron_record_address where 
		patron_record_id in
		(
		select id from sierra_view.patron_view where ($patronlocationcodes)
		) 
	";
	setupEGTable($query,"patron_record_address", $firstrun);
	
	#get patron names	
	my $query = "
		select * from sierra_view.patron_record_fullname where 
		patron_record_id in
		(
		select id from sierra_view.patron_view where ($patronlocationcodes)
		) 
	";
	setupEGTable($query,"patron_record_fullname", $firstrun);
	
	#get patron phone numbers	
	my $query = "
		select * from sierra_view.patron_record_phone where 
		patron_record_id in
		(
		select id from sierra_view.patron_view where ($patronlocationcodes)
		) 
	";
	setupEGTable($query,"patron_record_phone", $firstrun);
	
	#get patron checkouts
	my $query = "
		select * from sierra_view.checkout where 
		patron_record_id in
		(
		select id from sierra_view.patron_view where ($patronlocationcodes)
		) 
	";
	setupEGTable($query,"checkout", $firstrun);
	
	# get patron fines
	my $query = "
		select * from sierra_view.fine where 
		patron_record_id in
		(
		select id from sierra_view.patron_view where ($patronlocationcodes)
		) 
	";
	setupEGTable($query,"fine", $firstrun);
	
	#get patron fines paid
	my $query = "
		select * from sierra_view.fines_paid where 
		patron_record_metadata_id in
		(
		select id from sierra_view.patron_view where ($patronlocationcodes)
		) 
	";
	setupEGTable($query,"fines_paid", $firstrun);
	
	#get bibs - minus title column
	my $query = "select id,
    record_type_code,
    record_num,
    language_code,
    bcode1,
    bcode2,
    bcode3,
    country_code,
    is_available_at_library,
    index_change_count,
    allocation_rule_code,
    is_on_course_reserve,
    is_right_result_exact,
    skip_num,
    cataloging_date_gmt,
    marc_type_code,
    record_creation_date_gmt
    from sierra_view.bib_view where id in
	(
		SELECT brbl.BIB_RECORD_ID FROM
        SIERRA_VIEW.BIB_RECORD_LOCATION brbl
        left join SIERRA_VIEW.BIB_RECORD_LOCATION svbrl on(brbl.bib_record_id=svbrl.bib_record_id and svbrl.LOCATION_CODE in ($sierrapreviouslocationcodes))
        WHERE
		($sierralocationcodes) and
        svbrl.bib_record_id is null
        !!orderlimit!!
	)
	";
	setupEGTable($query,"bib_view", $firstrun);
	
	#get items
	my $query = "select * from sierra_view.item_view brbl where ($sierralocationcodes)";
	setupEGTable($query,"item_view", $firstrun);
	
	#get items bib links
	my $query = "
		select * from sierra_view.bib_record_item_record_link where bib_record_id
		in
		(
			select id from sierra_view.bib_view where id in
			(
				SELECT brbl.BIB_RECORD_ID FROM
                SIERRA_VIEW.BIB_RECORD_LOCATION brbl
                left join SIERRA_VIEW.BIB_RECORD_LOCATION svbrl on(brbl.bib_record_id=svbrl.bib_record_id and svbrl.LOCATION_CODE in ($sierrapreviouslocationcodes))
                WHERE
                ($sierralocationcodes) and
                svbrl.bib_record_id is null
                !!orderlimit!!
			)
		)
	";
	setupEGTable($query,"bib_record_item_record_link", $firstrun);

	#get patron messages
	my $query = "
		select * from sierra_view.varfield_view where record_type_code='p' and
		record_id in
		(
			select id from sierra_view.patron_view where ($patronlocationcodes)
		)
	";
	setupEGTable($query,"patron_varfield_view", $firstrun);
	
	#get item extra
	my $query = "
		select * from sierra_view.varfield_view where record_type_code='i' and varfield_type_code='y' and
		record_id in
		(
			select item_record_id from sierra_view.bib_record_item_record_link where bib_record_id
			in
			(
				select id from sierra_view.bib_view where id in
				(
					SELECT brbl.BIB_RECORD_ID FROM
                    SIERRA_VIEW.BIB_RECORD_LOCATION brbl
                    left join SIERRA_VIEW.BIB_RECORD_LOCATION svbrl on(brbl.bib_record_id=svbrl.bib_record_id and svbrl.LOCATION_CODE in ($sierrapreviouslocationcodes))
                    WHERE
                    ($sierralocationcodes) and
                    svbrl.bib_record_id is null
                    !!orderlimit!!
				)
			)
		)
	";
	setupEGTable($query,"item_varfield_view", $firstrun);
  
	#get holds
	my $query = "
        select * from 
        sierra_view.hold
        where patron_record_id in
        (
            select id from sierra_view.patron_view where ($patronlocationcodes)
        )
	";
	setupEGTable($query,"patron_holds", $firstrun);
	
    #get holds metadata
	my $query = "
        select * from 
        sierra_view.record_metadata
        where id in
        (
            select record_id from 
                sierra_view.hold
                where patron_record_id in
                (
                    select id from sierra_view.patron_view where ($patronlocationcodes)
                )
        )
	";
	setupEGTable($query,"record_metadata", $firstrun);	

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


sub setupEGTable
{
	my $query = @_[0];
	my $tablename = @_[1];
    my $resetTable = @_[2];
    my $tabFile = $conf{'marcoutdir'} . "/$tablename.tsv";
    my $tabOutput = '';
    my $thisFhandle;
    open($thisFhandle, '>> '.$tabFile) if (!$fileHandles{$tabFile});
    $thisFhandle = $fileHandles{$tabFile} if ($fileHandles{$tabFile});

    my $insertChunkSize = 500;
	
    my @ret = @{getRemoteSierraData($query)};
    
	my @allRows = @{@ret[0]};
	my @cols = @{@ret[1]};
	
	#drop the table
	my $query = ""; "DROP TABLE IF EXISTS $schema.$tablename";
	
    if( $resetTable )
    {
        $query = "DROP TABLE IF EXISTS $schema.$tablename";
        $log->addLine($query);
        $dbHandler->update($query) if $doDB;
        close($thisFhandle);
        unlink $tabFile;
        open($thisFhandle, '>> '.$tabFile);
        binmode($thisFhandle, ":utf8");

        #create the table
        $query = "CREATE TABLE $schema.$tablename (";
        $query.=$_." TEXT," for @cols;
        $tabOutput .= $_."\t" for @cols;
        $query=substr($query,0,-1).")";
        $tabOutput=substr($tabOutput,0,-1) . "\n";
        print $thisFhandle "$tabOutput";
        $tabOutput='';
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

exit;