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
	my $query = "
		select * from sierra_view.itype_property_myuser";
	setupEGTable($query,"itype_property_myuser", 1);

	#get patron types
	my $query = "
		select * from sierra_view.ptype_property_myuser
	";
	setupEGTable($query,"ptype_property_myuser", 1);
	
	#get patron types
	my $query = "
		select * from sierra_view.user_defined_pcode1_myuser
	";
	setupEGTable($query,"user_defined_pcode1_myuser", 1);
	
	#get patron types
	my $query = "
		select * from sierra_view.user_defined_pcode2_myuser
	";
	setupEGTable($query,"user_defined_pcode2_myuser", 1);
	
	#get patron types
	my $query = "
		select * from sierra_view.user_defined_pcode3_myuser
	";
	setupEGTable($query,"user_defined_pcode3_myuser", 1);
  
    #get Item Status codes
	my $query = "
        select * from sierra_view.item_status_property_myuser
	";
	setupEGTable($query,"item_status_property_myuser", 1);
  
    #get Item material types
	my $query = "
        select * from sierra_view.material_property_myuser
	";
	setupEGTable($query,"material_property_myuser", 1);
  
    #get Item material types
	my $query = "
        select * from sierra_view.material_property_name
	";
	setupEGTable($query,"material_property_name", 1);
  
    #get user_defined_bcode1_myuser
	my $query = "
        select * from sierra_view.user_defined_bcode1_myuser
	";
	setupEGTable($query,"user_defined_bcode1_myuser", 1);
  
    #get user_defined_bcode2_myuser
	my $query = "
        select * from sierra_view.user_defined_bcode2_myuser
	";
	setupEGTable($query,"user_defined_bcode2_myuser", 1);

    #get user_defined_bcode3_myuser
	my $query = "
        select * from sierra_view.user_defined_bcode3_myuser
	";
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
concat('i', item.record_num) "item_num", --RECORD #(Item)
string_agg( concat('b',bib.record_num),';') "connected_bibs", -- RECORD #(Bibliographic)
regexp_replace(regexp_replace(string_agg(item_prop.call_number,''),'\|.',';','g'),'^;','','g') "item_call_number", --CALL #(Item)
regexp_replace(regexp_replace(string_agg(bib_call.field_content,''),'\|.',';','g'),'^;','','g') "bib_call_number", --CALL #(Bibliographic)
item.barcode,
item.itype_code_num,
item.location_code,
item.item_status_code,
item.inventory_gmt,
item.copy_num,
item.icode2,
item.use3_count,
item.internal_use_count,
item.copy_use_count,
item.item_message_code,
item.opac_message_code,
item.last_year_to_date_checkout_total,
item.record_creation_date_gmt,
metarecord.record_last_updated_gmt

from
sierra_view.item_view item
left join sierra_view.item_view item_omit on(item_omit.id=item.id and item_omit.location_code in (!!!sierrapreviouslocationcodes!!!))
join sierra_view.bib_record_item_record_link bib_item_link on ( bib_item_link.item_record_id = item.id)
join sierra_view.bib_view bib on ( bib.id = bib_item_link.bib_record_id )
join sierra_view.record_metadata metarecord on(metarecord.record_num=item.record_num and metarecord.record_type_code='i')
left join sierra_view.item_record_property item_prop on(item_prop.item_record_id=item.id)
left join sierra_view.varfield_view bib_call on(bib_call.record_id = bib.id and bib_call.record_type_code='b' and bib_call.marc_tag in( '090', '092' ) and bib_call.field_content ~'^\|a' )
where
item_omit.id is null and
(!!!sierralocationcodes!!!)
group by 1,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
splitter

    my $t = $sierralocationcodes;
    $t =~ s/^brbl/item/g;
    $query =~ s/!!!sierrapreviouslocationcodes!!!/$sierrapreviouslocationcodes/g;
    $query =~ s/!!!sierralocationcodes!!!/$t/g;
    setupEGTable($query,"folio_items", $firstrun);

  
	#get patrons
	my $query = "
		select * from sierra_view.patron_view where ($patronlocationcodes) 
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
	
	#get bibs
	my $query = "select * from sierra_view.bib_view where id in
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
	my $query = "select * from sierra_view.item_view where id in
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
      
    #get Item Status
	my $query = "
        select id,item_status_code from 
        sierra_view.item_record
        where
        id in
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
        and
        item_status_code !='-'
	";
	setupEGTable($query,"non_available_item", $firstrun);	

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
        $offset = ($loops * $limit) + 1;
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
        select location_code
        from
        sierra_view.bib_record_location
        group by 1

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