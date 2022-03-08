<?php


class noticeUI
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
                $ret = $this->getSearchTable();
            }
            else if(isset($this->uri['submitjson']) && isset($_POST['payload']))
            {
//echo "<xmp>raw: " .  $_POST['payload'] ."</xmp>";
// echo "<pre>" . html_entity_decode(htmlspecialchars_decode($_POST['payload']))   ."</pre>";
// $this->updateJSONDetails($this->uri['submitjson'], html_entity_decode(html_entity_decode(preg_replace('/%20/',' ', $_POST['payload']) ) ));
               echo $this->updateJSONDetails($this->uri['submitjson'], html_entity_decode(htmlspecialchars_decode($_POST['payload'])));
            }
		}
        else if(isset($this->uri['getjson']))
        {
            If(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1 )
			{	
				$ret = $this->getSearchTable($this->uri['searchstring']);
			}
            else if(isset($this->uri['screenshotdiag']) && isset($this->uri['sourceid']))
            {
                $ret = $this->getScreenShotImages($this->uri['sourceid']);
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
        <script type=\"text/javascript\" src=\"js/notice.js\"></script>
        <div class='regularBox'>
        <div class='notice_container'>
            <div id='notice_history_datatable' class='notice_child'>
            <div class='loader'></div>
            </div> <!-- notice_history_datatable -->

        </div> <!-- notice_container -->
        </div><!-- regularBox -->";
		return $ret;
	}

    function getSearchTable($searchstring = null)
	{
        $fromDate = convertToDatabaseDate($fromDate);
        $toDate = convertToDatabaseDate($toDate);
		addDebug("getSearchTable called");
		$anchorProps = array();
		$selectCols = array(
        "nt.name \"name\"",
        "nh.status \"nhstatus\"",
        "nh.create_time AS DATE \"create_time\"",
        "nh.send_time \"send_time\"",
        "nh.status \"nhstatus\"");
		$showCols = array("name"=>"Template Name","nhstatus"=>"Notice Status","create_time"=>"Created","send_time"=>"Send Time");
		$ClickPos=array();
		$searchCols = array();
		$tableID = "noticeSearchTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "";
        $table = "
        " . $this->tablePrefix ."notice_history nh
        JOIN " . $this->tablePrefix ."notice_template nt ON (nt.id=nh.notice_template)
        LEFT JOIN " . $this->tablePrefix ."job job ON (job.id=nh.job)";

		$search=null;
		$getRaw=null;
        $groupClause = "";
		$orderClause = "";
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