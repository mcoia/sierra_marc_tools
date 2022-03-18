<?php


class dashboardUI
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
                $ret = $this->getSearchTable($this->uri['fromdate'], $this->uri['todate']);
            }
            else if(isset($this->uri['getstat']))
            {
                if($this->uri['statid'] == 'dashboard_stat_panel_total_records')
                {
                    $ret = $this->getTotalRecords($this->uri['fromdate'], $this->uri['todate']);
                }
                else if($this->uri['statid'] == 'dashboard_stat_panel_total_vendors')
                {
                    $ret = $this->getTotalVendors($this->uri['fromdate'], $this->uri['todate']);
                }
                else if($this->uri['statid'] == 'dashboard_stat_panel_total_unprocessed_records')
                {
                    $ret = $this->getTotalRecords($this->uri['fromdate'], $this->uri['todate'], 1);
                }
                else if($this->uri['statid'] == 'dashboard_stat_panel_waitingils_records')
                {
                    $ret = $this->getTotalRecords($this->uri['fromdate'], $this->uri['todate'], 0, 1);
                }
            }
		}
        else if(isset($this->uri['getjson']))
        {
            If(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1 )
			{	
				$ret = $this->getSearchTable(null, null, $this->uri['searchstring']);
			}
        }
		else if(isset($this->uri['getgraph']))
        {
            if(isset($this->uri['summarypie']))
            {
                $summaryData = $this->getSummaryData($this->uri['fromdate'], $this->uri['todate']);
                $percents = array();
                $labels = array();
                $total = 0;
                if(count($summaryData) > 0)
                {
                    foreach($summaryData as $internal => $row)
                    {
                        $labels[] = $row["client"] . " " . $row["source"];
                        $percents[] = $row["count"];
                        $total += $row["count"];
                    }
                    foreach($percents as $internal => $value)
                    {
                        $percents[$internal] = round($percents[$internal] / $total, 2);
                    }
                    $title = "Percentage of records";
                    if(isset($this->uri['fromdate']))
                    {
                        $title .= isset($this->uri['todate']) ? " from " : " since ";
                        $title .= convertFromDatabaseDate($this->uri['fromdate']);
                    }
                    if(isset($this->uri['todate']))
                    {
                        $title .= " to " . convertFromDatabaseDate($this->uri['todate']);
                    }
                    if(!isset($this->uri['fromdate']) && !isset($this->uri['todate']))
                    {
                        $title .= " for all time";
                    }
                }
                else
                {
                    $percents[] = 1;
                    $labels[] = 'none';
                    $title = "No Data";
                }
                $this->makePieChart($percents, $labels, $this->uri['width'], $this->uri['height'], $title);
            }
        }
        else
		{
			$ret = $this->UI();
		}
		return $ret;
	}

	function UI()
	{
		$ret="";
        $controlPanel = new control_panel();
        $dateControlPanel = $controlPanel->getDateControlPanel();

		$ret.="
        <script type=\"text/javascript\" src=\"js/dashboard.js\"></script>
        <div class='regularBox'>
        <div class='dashboard_summary_container'>
            <div id='dashboard_date_control_panel' class='dashboard_summary_container_child'>
            $dateControlPanel
            </div><!-- dashboard_date_control_panel -->
            <div id='dashboard_stat_panel' class='dashboard_summary_container_child'>

                <div id='dashboard_stat_panel_total_records' class='dashboard_stat_panel_child'>
                    <div class='dashboard_stat_panel_child_title'>
                     Total Records
                    </div><!-- dashboard_stat_panel_child_title -->
                    <div class='dashboard_stat_panel_child_result'>
                    </div><!-- dashboard_stat_panel_child_result -->
                </div><!-- dashboard_stat_panel_total_records -->

                <div id='dashboard_stat_panel_total_vendors' class='dashboard_stat_panel_child'>
                    <div class='dashboard_stat_panel_child_title'>
                     Total Vendors
                    </div><!-- dashboard_stat_panel_child_title -->
                    <div class='dashboard_stat_panel_child_result'>
                    </div><!-- dashboard_stat_panel_child_result -->
                </div><!-- dashboard_stat_panel_total_vendors -->

                <div id='dashboard_stat_panel_waitingils_records' class='dashboard_stat_panel_child'>
                    <div class='dashboard_stat_panel_child_title'>
                     ILS Load Waiting
                    </div><!-- dashboard_stat_panel_child_title -->
                    <div class='dashboard_stat_panel_child_result'>
                    </div><!-- dashboard_stat_panel_child_result -->
                </div><!-- dashboard_stat_panel_total_records -->

                <div id='dashboard_stat_panel_total_unprocessed_records' class='dashboard_stat_panel_child'>
                    <div class='dashboard_stat_panel_child_title'>
                     Unprocessed Records
                    </div><!-- dashboard_stat_panel_child_title -->
                    <div class='dashboard_stat_panel_child_result'>
                    </div><!-- dashboard_stat_panel_child_result -->
                </div><!-- dashboard_stat_panel_total_records -->

            </div><!-- dashboard_stat_panel -->

            <div id='dashboard_summary_pie_chart' class='dashboard_summary_container_child'>
            <div class='loader'></div>
            </div> <!-- dashboard_summary_pie_chart -->

            <div id='dashboard_summary_datatable' class='dashboard_summary_container_child'>
            <div class='loader'></div>
            </div> <!-- dashboard_summary_datatable -->

        </div> <!-- dashboard_summary_container -->
        </div><!-- regularBox -->";
		return $ret;
	}

    function getSummaryData($fromDate, $toDate)
    {
        $vars = array();
        $daterange = "";
        $query = "
        select ac.name \"client\", autos.name \"source\", count(*) \"count\"
        from
        ". $this->tablePrefix ."import_status ais,
        ". $this->tablePrefix ."file_track aft,
        ". $this->tablePrefix ."source autos,
        ". $this->tablePrefix ."client ac,
        ". $this->tablePrefix ."job aj
        where
        aj.id=ais.job and
        ac.id=aft.client and
        autos.id=aft.source and
        aft.id=ais.file
        !!daterange!!
        group by 1,2";
        if($fromDate)
        {
            $daterange .= "
            and aj.start_time > ?";
            $vars[] = $fromDate;
        }
        if($toDate)
        {
            $daterange .= "
            and aj.start_time < ?";
            $vars[] = $toDate;
        }
        $query = preg_replace('/!!daterange!!/i', $daterange, $query);
		$result = $this->sqlconnect->executeQuery($query,$vars);
        return $result;
    }

    function getTotalVendors($fromDate, $toDate, $nonStarted = null)
    {
        $vars = array();
        $daterange = "";
        $query = "
        select autos.name \"source\", count(*) \"count\"
        from
        ". $this->tablePrefix ."import_status ais,
        ". $this->tablePrefix ."file_track aft,
        ". $this->tablePrefix ."source autos,
        ". $this->tablePrefix ."client ac,
        ". $this->tablePrefix ."job aj
        where
        aj.id=ais.job and
        ac.id=aft.client and
        autos.id=aft.source and
        aft.id=ais.file
        !!daterange!!
        group by 1";
        if($nonStarted)
        {
            $daterange .= "
            and aj.start_time is null";
        }
        else
        {
            if($fromDate)
            {
                $daterange .= "
                and aj.start_time > ?";
                $vars[] = $fromDate;
            }
            if($toDate)
            {
                $daterange .= "
                and aj.start_time < ?";
                $vars[] = $toDate;
            }
        }
        $query = preg_replace('/!!daterange!!/i', $daterange, $query);
		$result = $this->sqlconnect->executeQuery($query,$vars);
        if(count($result) > 0)
        {
            return count($result);
        }
        else
        {
            return "-";
        }
        return $result;
    }

    function getTotalRecords($fromDate, $toDate, $nonStarted = null, $waitingForILS = null)
    {
        $vars = array();
        $daterange = "";
        $query = "
        select count(*) \"count\"
        from
        ". $this->tablePrefix ."import_status ais,
        ". $this->tablePrefix ."job aj
        where
        aj.id=ais.job
        AND aj.type='processmarc'
        !!daterange!!";
        if($nonStarted)
        {
            $daterange .= "
            and aj.start_time is null";
        }
        else
        {
            if($fromDate)
            {
                $daterange .= "
                and aj.start_time > ?";
                $vars[] = $fromDate;
            }
            if($toDate)
            {
                $daterange .= "
                and aj.start_time < ?";
                $vars[] = $toDate;
            }
        }
        if($waitingForILS)
        {
            $daterange .= "
            and ais.loaded = ?";
            $vars[] = 0;
        }
        $query = preg_replace('/!!daterange!!/i', $daterange, $query);
		$result = $this->sqlconnect->executeQuery($query,$vars);
        if(count($result) == 1)
        {
            return $result[0]["count"];
        }
        else
        {
            return "-";
        }
        return $result;
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
    
    function getSearchTable($fromDate, $toDate, $searchstring = null)
	{
        $fromDate = convertToDatabaseDate($fromDate);
        $toDate = convertToDatabaseDate($toDate);
		addDebug("getSearchTable called");
		$anchorProps = array();
		$selectCols = array("ac.name \"clientname\"","asource.name \"sourcename\"","count(*) \"count\"");
		$showCols = array("clientname"=>"Institution","sourcename"=>"Vendor","count"=>"Count");
		$ClickPos=array();
		$searchCols = array("ac.name","asource.name");
		$tableID = "dashboardSearchTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "";
        if(isset($fromDate))
        {
            $extraWhereClause .= "aj.start_time > '$fromDate'";
        }
        if(isset($toDate))
        {
            $extraWhereClause .= isset($fromDate) ? " AND " : "";
            $extraWhereClause .= "aj.start_time < '$toDate'";
        }
        $table = "
        " . $this->tablePrefix ."file_track aft
        JOIN " . $this->tablePrefix ."import_status ais ON (ais.file=aft.id)
        JOIN " . $this->tablePrefix ."client ac ON (ac.id=aft.client)
        JOIN " . $this->tablePrefix ."source asource ON (asource.id=aft.source)
        JOIN " . $this->tablePrefix ."job aj ON (aj.id=ais.job)";

		$search=null;
		$getRaw=null;
        $groupClause = "1,2";
		$orderClause = "1,2";
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