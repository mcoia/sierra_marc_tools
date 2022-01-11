<?php


class vendorsUI
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
// echo "<xmp>raw: " .  $_POST['payload'] ."</xmp>";
// echo "<pre>" . htmlspecialchars_decode( $_POST['payload'])   ."</pre>";
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
        <script type=\"text/javascript\" src=\"js/vendors.js\"></script>
        <div class='regularBox'>
        <div class='vendor_container'>
            <div id='vendor_datatable' class='vendor_child'>
            <div class='loader'></div>
            </div> <!-- vendor_datatable -->

        </div> <!-- vendor_container -->
        </div><!-- regularBox -->";
		return $ret;
	}

    function getSearchTable($searchstring = null)
	{
        $fromDate = convertToDatabaseDate($fromDate);
        $toDate = convertToDatabaseDate($toDate);
		addDebug("getSearchTable called");
		$anchorProps = array();
		$selectCols = array("asource.name \"vname\"","ac.name \"clientname\"","asource.type \"type\"","asource.perl_mod \"perlmod\"",
        "concat('<a source=\"',asource.id,'\" onClick=\"editJSONClick(this)\" href=\"#\">', asource.json_connection_detail, '</a>') \"conndetail\"");
		$showCols = array("vname"=>"Vendor","clientname"=>"Institution","type"=>"Type","perlmod"=>"Perl Mod","conndetail"=>"Connection Detail");
		$ClickPos=array();
		$searchCols = array();
		$tableID = "vendorSearchTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "";
        $table = "
        " . $this->tablePrefix ."source asource
        JOIN " . $this->tablePrefix ."client ac ON (asource.client=ac.id)";

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

    function updateJSONDetails($sourceID, $json)
    {
        $ret = "";
        $query = "update " . $this->tablePrefix ."source asource " .
        "set json_connection_detail = ? where id = ?";
        $vars = array($json, $sourceID);
		return $result = $this->sqlconnect->executeQuery($query, $vars);

# Leaving this code in here for troubleshooting if needs be
        $ret .= $query;
        foreach($vars as $internal => $value)
        {
            $ret .= "$value\n";
        }
        $ret .= "<pre>$json</pre>";
        return $ret;
    }
}