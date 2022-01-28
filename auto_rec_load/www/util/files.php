<?php


class filesUI
{
	private $sqlconnect;
	private $uri;
	private $url;
	private $currentUser;
	private $currentURLBase;
    private $tablePrefix;
	function __construct()
	{	
		global $currentUser;
		global $sqlconnect;
		global $uri;
		global $url;
		global $currentURLBase;
        global $tablePrefix;
		$this->uri = copyArray($uri);
		$this->sqlconnect = $sqlconnect;
		$this->currentUser = $currentUser;
		$this->currentURLBase = $currentURLBase;
		$this->url = $url;
        $this->tablePrefix = $tablePrefix;
	}
	
	function go()
	{
		$ret="";
        if(isset($this->uri['getdata']))
		{
            if(isset($this->uri['getsummarytable']))
            {
                $ret = $this->getSearchTable(null);
            }	
		}
        else if(isset($this->uri['getjson']) && isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1 )
        {
            $this->getSearchTable($this->uri['searchstring']);
        }
        else
        {
            $ret = $this->UI();
        }
		return $ret;
	}

	function UI()
	{
		$ret="
        <script type=\"text/javascript\" src=\"js/files.js\"></script>
        <div class='regularBox'>
        <div class='files_summary_container'>
            <div id='files_summary_datatable' class='files_summary_container_child'>
            <div class='loader'></div>
            </div> <!-- files_summary_datatable -->

        </div> <!-- files_summary_container -->
        </div><!-- regularBox -->";
		return $ret;
	}

    function makePieChart($percents, $labels, $width, $height, $title)
	{
        $width = $width ? $width : 500;
        $height = $height ? $height : 500;

        $piegraph = new PieGraph($height, $width);
        $pieplot = new PiePlot($percents);
        $pieplot->SetLabels($labels);
        if(isset($title))
        {
            $pieplot->title->Set($title);
        }
        $pieplot->ExplodeAll(10);
        $piegraph->Add($pieplot); 
        $piegraph->Stroke();
	}
    
    function getSearchTable($searchstring = null)
	{
		addDebug("getSearchTable called");
		$anchorProps = array();
		if(isset($this->uri['search']))
			$search=$this->uri['search'];
        $selectCols = array
        (
            "aj.id \"jobid\"",
            "date(aj.start_time) \"jobdate\"",
            "aj.status \"jobstatus\"",
            "ac.name \"clientname\"",
            "asource.name \"sourcename\"",
            "concat('<a sourcefile=\"1\" fileid=\"', aft.id, '\" onClick=\"marcFileDownloadClick(',aft.id,', this)\" href=\"#\">', aft.filename, '</a>') \"orgfile\"",
            "concat('<a fileid=\"', aft.id, '\" onClick=\"marcFileDownloadClick(',aoft.id,', this)\" href=\"#\">', substring_index(aoft.filename,'/',-2), '</a>') \"outfile\"",
            "ais.itype",
            "ais.tag",
            "(case ais.loaded when true then 'true' else 'false' end) \"ilsconfirmed\"",
            "count(*) \"count\""
        );

		$showCols = array
        (
            "jobid"=>"Job ID",
            "jobdate"=>"Start Date",
            "jobstatus"=>"Job Status",
            "clientname"=>"Institution",
            "sourcename"=>"Vendor",
            "orgfile"=>"Source File",
            "outfile"=>"Output File",
            "itype"=>"Record Type",
            "tag"=>"Internal Tag",
            "ilsconfirmed"=>"ILS Loaded Confirmation",
            "count"=>"Count"
        );
		$ClickPos=array();
		$searchCols = array("ac.name","asource.name","aft.filename","aoft.filename","ais.tag");
		$tableID = "filesSearchTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "aj.start_time > DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)";
        $table = "
        ". $this->tablePrefix ."file_track aft
        JOIN ". $this->tablePrefix ."import_status ais ON (ais.file=aft.id)
        LEFT JOIN ". $this->tablePrefix ."output_file_track aoft on(aoft.id=ais.out_file)
        JOIN ". $this->tablePrefix ."client ac ON (ac.id=aft.client)
        JOIN ". $this->tablePrefix ."source	asource ON (asource.id=aft.source)
        JOIN ". $this->tablePrefix ."job aj ON aj.id=ais.job";

		$search=null;
		$getRaw=null;
        $groupClause = "1,2,3,4,5,6,7,8,9,10";
		$orderClause = "1,2,3,4,5,6,7,8";
		if(isset($searchstring))
		{
			$search=$searchstring;
			$getRaw=1;
			$extraWhereClause="";
		}
		$resultTable = makeSearchTable($table, $selectCols, $ClickPos, $showCols, $searchCols, $tableID, $uriValClick, $additionalURI, $anchorProps, $search, $extraWhereClause, $orderClause, $getRaw, $groupClause);
		
		if(isset($searchstring))
		{
			echo json_encode($resultTable);
		}
		else
		{		
			return $resultTable;
		}
	}

}