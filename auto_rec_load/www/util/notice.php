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
                $ret = $this->updateTemplate();
            }
            else if(isset($this->uri['deletetemplate']))
            {
                $ret = $this->deleteTemplate($this->uri['deletetemplate']);
            }
            else if(isset($this->uri['emailme']) && isset($this->uri['emailmeaddress']))
            {
                $ret = $this->emailMeHistory($this->uri['emailme'], $this->uri['emailmeaddress']);
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
        "CONCAT(
        '<a href=\"#\" onclick=\"templateAction(\\'edit\\', ',nt.id,')\">Edit</a>  |  ',
        '<a href=\"#\" onclick=\"templateAction(\\'clone\\', ',nt.id,')\">Clone</a>  |  ',
        '<a href=\"#\" onclick=\"templateAction(\\'delete\\', ',nt.id,')\">Delete</a>'
        ) \"action\"",
        "nt.name \"name\"",
        "CASE WHEN nt.enabled IS TRUE THEN 'Enabled' ELSE 'Disabled' END \"enabled\"",
        "CASE WHEN source.id IS NOT NULL THEN (CONCAT(source.name, '_', client.name)) ELSE 'All Client/Vendors' END \"ntsource\"",
        "nt.type \"type\"",
        "nt.upon_status \"ntupon_status\"",
        "nt.template \"nttemplate\"",
        "count(nh.id) \"historycount\""
        );
		$showCols = array(
        "action"=>"Action",
        "name"=>"Template Name",
        "enabled"=>"Enabled",
        "ntsource"=>"Client/Vendor",
        "type"=>"Notice Type",
        "ntupon_status"=>"Upon Status",
        "historycount"=>"History Count"
        );
		$ClickPos=array();
		$searchCols = array("nt.name","nt.upon_status","nt.template","nt.type");
		$tableID = "noticeTemplateTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "";
        $table = "
        " . $this->tablePrefix ."notice_template nt
        LEFT JOIN " . $this->tablePrefix ."source source ON (nt.source=source.id)
        LEFT JOIN " . $this->tablePrefix ."client client ON (client.id=source.client)
        LEFT JOIN " . $this->tablePrefix ."notice_history nh ON (nh.notice_template=nt.id)";

		$search=null;
		$getRaw=null;
        $groupClause = "1,2,3,4,5";
		$orderClause = "3,4,5";
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
        "CONCAT(
        '<a href=\"#\" onclick=\"historyAction(\\'emailme\\', ',nh.id,')\">Email Me</a>'
        ) \"action\"",
        "nt.name \"name\"",
        "nh.status \"nhstatus\"",
        "DATE(nh.create_time) \"create_time\"",
        "nh.send_time \"send_time\"",
        "nh.status \"nhstatus\"",
        "nh.data \"nhdata\""
        );
		$showCols = array("action"=>"Action", "name"=>"Template Name","nhstatus"=>"Notice Status","create_time"=>"Created","send_time"=>"Send Time");
		$ClickPos=array();
		$searchCols = array("nt.name","nh.data","nh.send_status","nh.status");
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
        $template = html_entity_decode(htmlspecialchars_decode($_POST['template']));
        $name =  $_POST['name'];
        $editingID =  $_POST['editingID'];
        $source =  $_POST['source']; # This could be set to null, which means the template is for ALL SOURCES
        $type =  $_POST['type'];
        $upon_status =  $_POST['upon_status'];
        $enabled =  $_POST['enabled'];
        $enabled = strcmp($enabled, 'false') == 0 ? 0 : 1;

        if($editingID > 0) # handle update
        {
            $query = "UPDATE " . $this->tablePrefix ."notice_template " .
            "SET template = ?, enabled = ?, name = ? WHERE id = ?";
            $vars = array($template, $enabled, $name, $editingID);
            return $this->sqlconnect->executeQuery($query, $vars);
        }
        else # handle new
        {
            $query = "INSERT INTO " . $this->tablePrefix ."notice_template " .
            "(name, enabled, source, type, upon_status, template)
            VALUES(?, ?, $source, ?, ?, ?)";            
            $vars = array($name, $enabled, $type, $upon_status, $template);
            return $this->sqlconnect->executeQuery($query, $vars);
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

    function deleteTemplate($templateID)
    {
        $ret = "";
        $query = "DELETE FROM " . $this->tablePrefix ."notice_history WHERE notice_template = ?";
        $vars = array($templateID);
        if($this->sqlconnect->executeQuery($query, $vars))
        {
            $query = "DELETE FROM " . $this->tablePrefix ."notice_template WHERE id = ?";
            return $this->sqlconnect->executeQuery($query, $vars);
        }
        else
        {
            return 0;
        }
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
        # Append to the top of the array our special "All Sources"
        array_unshift($result, Array("id" => "null", "sourcename" => "All", "clientname" => "Sources"));
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
        $query = "SELECT nt.id \"id\", nt.source \"sourceid\", nt.type \"type\", nt.upon_status \"upon_status\", nt.enabled \"enabled\", nt.name \"name\"
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
            $ret = $result[0]["template"];
        }

        return $ret;
    }

    function emailMeHistory($historyID, $toEmailAddress)
    {
        # basic check to make sure we have a numeric ID and an email address that contains the at symbol
        if(is_numeric($historyID) && ($historyID+0 > 0) && preg_match("/@/", $toEmailAddress))
        {
            return insertWWWAction('emailme', $historyID, $toEmailAddress);
        }
        return 0;
    }


}