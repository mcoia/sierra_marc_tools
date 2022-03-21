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
            if(isset($this->uri['gethistorytable']))
            {
                $ret = $this->getNoticeHistorySearchTable($this->uri['fromdate'], $this->uri['todate']);
            }
            else if(isset($this->uri['gettemplatetable']))
            {
                $ret = $this->getNoticeTemplateTable();
            }
            else if(isset($this->uri['gettemplateid']))
            {
                $ret = $this->getTemplateFromID($this->uri['gettemplateid']);
            }
            else if(isset($this->uri['submittemplate']) && isset($_POST['template']))
            {
               echo $this->updateTemplate();
            }
		}
        else if(isset($this->uri['getjson']))
        {
            If(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1  && $this->uri['searchtable'] == 'noticeHistorySearchTable')
			{
				$ret = $this->getNoticeHistorySearchTable(null, null, $this->uri['searchstring']);
			}
            else If(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1  && $this->uri['searchtable'] == 'noticeTemplateTable')
			{	
				$ret = $this->getNoticeTemplateTable($this->uri['searchstring']);
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
        $sourceList = $this->getSourceList();
        $noticeMetadata = $this->getNoticeMetadata();
        

		$ret.="
        <script type=\"text/javascript\" src=\"js/notice.js\"></script>
        <script type=\"text/javascript\">
        var sourceList = JSON.parse('$sourceList');
        var noticeMetadata = JSON.parse('$noticeMetadata');
        </script>
        <div class='regularBox'>
        <div class='notice_container'>
            <div class=\"title\">Notice Definitions</div>
            <div id = \"create_notice_definition_button\">
              <div class=\"plusSignButton\"></div><span class=\"create_notice_definition_button_title\">Create Definition</span>
            </div>
                <div id='notice_definition_datatable' class='notice_child'>
                <div class='loader'></div>
                </div> <!-- notice_history_datatable -->

            <div class=\"title\">Notice History</div>
            <div id='notice_date_control_panel' class='notice_child'>
            $dateControlPanel
            </div><!-- dashboard_date_control_panel -->
            <div id='notice_history_datatable' class='notice_child'>
            <div class='loader'></div>
            </div> <!-- notice_history_datatable -->

        </div> <!-- notice_container -->
        </div><!-- regularBox -->";
		return $ret;
	}

    function getNoticeTemplateTable($searchstring = null)
	{
        addDebug("getNoticeHistorySearchTable called");
		$anchorProps = array();
		$selectCols = array(
        "nt.name \"name\"",
        "CASE WHEN nt.enabled IS TRUE THEN 'Enabled' ELSE 'Disabled' END \"enabled\"",
        "source.name \"ntsource\"",
        "nt.type \"type\"",
        "nt.upon_status \"ntupon_status\"",
        "nt.template \"nttemplate\"",
        "count(*) \"historycount\""
        );
		$showCols = array(
        "name"=>"Template Name",
        "enabled"=>"Enabled",
        "ntsource"=>"Client/Vendor",
        "type"=>"Notice Type",
        "ntupon_status"=>"Upon Status",
        "historycount"=>"History Count"
        );
		$ClickPos=array();
		$searchCols = array();
		$tableID = "noticeTemplateTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "";
        $table = "
        " . $this->tablePrefix ."notice_template nt
        JOIN " . $this->tablePrefix ."source source ON (nt.source=source.id)
        LEFT JOIN " . $this->tablePrefix ."notice_history nh ON (nh.notice_template=nt.id)";

		$search=null;
		$getRaw=null;
        $groupClause = "1,2,3,4,5";
		$orderClause = "1,2,3,4,5";
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

    function getNoticeHistorySearchTable($fromDate, $toDate, $searchstring = null)
	{
        $fromDate = convertToDatabaseDate($fromDate);
        $toDate = convertToDatabaseDate($toDate);
		addDebug("getNoticeHistorySearchTable called");
		$anchorProps = array();
		$selectCols = array(
        "nt.name \"name\"",
        "nh.status \"nhstatus\"",
        "DATE(nh.create_time) \"create_time\"",
        "nh.send_time \"send_time\"",
        "nh.status \"nhstatus\"",
        "nh.data \"nhdata\""
        );
		$showCols = array("name"=>"Template Name","nhstatus"=>"Notice Status","create_time"=>"Created","send_time"=>"Send Time");
		$ClickPos=array();
		$searchCols = array();
		$tableID = "noticeHistorySearchTable";
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

    function updateTemplate()
    {
        $ret = "";
        $template =  html_entity_decode(htmlspecialchars_decode($_POST['template']));
        $name =  $_POST['name'];
        $editingID =  $_POST['editingID'];
        $source =  $_POST['source'];
        $type =  $_POST['type'];
        $upon_status =  $_POST['upon_status'];
        $enabled =  $_POST['enabled'];

        if($editingID > 0) # handle update
        {
            $query = "update " . $this->tablePrefix ."notice_template " .
            "set template = ?, enabled = ? where id = ?";
            $vars = array($template, $enabled, $editingID);
            return $this->sqlconnect->executeQuery($query, $vars);
        }
        else # handle new
        {
            $query = "INSERT INTO " . $this->tablePrefix ."notice_template " .
            "(name, enabled, source, type, upon_status, template)
            VALUES(?, ?, ?, ?, ?, ?)";
            $vars = array($name, $enabled, $source, $type, $upon_status, $template);
            $this->sqlconnect->executeQuery($query, $vars);
            # return $this->sqlconnect->executeQuery($query, $vars);
        }

        # Leaving this code in here for troubleshooting if needs be
        $ret .= $query;
        foreach($vars as $internal => $value)
        {
            $ret .= "$value\n<br />";
        }
        $ret .= "<pre>$template</pre>";
        return $ret;
    }

    function getSourceList()
    {
        $query = "SELECT source.id \"id\", source.name \"sourcename\", client.name \"clientname\"
        FROM
        " . $this->tablePrefix ."source source
        JOIN " . $this->tablePrefix ."client client ON (client.id=source.client)
        ORDER BY 2,3";
        $vars = array();
        $result = $this->sqlconnect->executeQuery($query, $vars);
        if(count($result) > 0)
        {
            return json_encode($result);
        }
        return array();
    }

    function getNoticeMetadata()
    {
        $ret = array(
        'types' =>array('scraper','processmarc','ilsload'),
        'upon_statuses' =>array('success','fail','generic')
        );
        $query = "SELECT nt.id \"id\", nt.source \"sourceid\", nt.type \"type\", nt.upon_status \"upon_status\"
        FROM
        " . $this->tablePrefix ."notice_template nt";
        $vars = array();
        $result = $this->sqlconnect->executeQuery($query, $vars);

        $ret["used_templates"] = $result;

        return json_encode($ret);
    }

    function getTemplateFromID($templateID)
    {
        $ret = "";
        $query = "SELECT nt.template \"template\"
        FROM
        " . $this->tablePrefix ."notice_template nt
        WHERE id = ?";
        $vars = array($templateID);
        $result = $this->sqlconnect->executeQuery($query, $vars);
        if(count($result) == 1)
        {
            $ret = $result[0][0];
        }

        return $ret;
    }


}