<?php


class job
{
	
	private $jobID=-1;
	private $traits = array();
	private $sqlconnect;
	private $fields = array();
	
	
	function __construct($jobID)
	{
		global $sqlconnect;
        global $tablePrefix;
		$this->sqlconnect = $sqlconnect;
        $this->tablePrefix = $tablePrefix;
		//$id, $maxwidth, $type, $table, $friendlyName)
		$this->fields["id"]=new dbField("id",10,"hidden", $tablePrefix . "job","Job ID",true,"");
		$this->fields["create_time"]=new dbField("create_time",25,"date", $tablePrefix . "job", "Create Time",true,"");
        $this->fields["start_time"]=new dbField("start_time",25,"date", $tablePrefix . "job", "Start Time",true,"");
        $this->fields["last_update_time"]=new dbField("start_time",25,"date", $tablePrefix . "job", "Last Update Time",true,"");
		$this->fields["current_action"]=new dbField("current_action",1000,"text", $tablePrefix . "job", "Current Action",true,"");
		$this->fields["status"]=new dbField("status",100,"text", $tablePrefix . "job", "Status",true,"");
		$this->fields["current_action_num"]=new dbField("current_action_num",10,"text", $tablePrefix . "job", "Number of Actions",true,"");

		$this->jobID=$jobID;
		$this->fillVars();
	}
	
	function getJobID()
	{
		return $this->jobID;
	}

	function getTraits()
	{
		if($this->jobID>-1)
        {
            return $this->traits;
        }
		else
        {
            return false;
        }
	}
	
	function getFields()
	{	
		return $this->fields;
	}
	
	function fillVars()
	{
		$this->traits = array();
	
		if(isset($this->jobID) && $this->jobID!=-1)
		{
			$this->traits = array();		
			$query="SELECT ";
			foreach($this->fields as $internal => $value)
            {
                $query.=$internal.", ";
            }
			$query = substr($query, 0, -2); #remove the last ', '
			$query .= " FROM " . $tablePrefix . "job WHERE id=?";
			$vars = array($this->jobID);
			$result = $this->sqlconnect->executeQuery($query, $vars);
			if(count($result)==1)
			{
				foreach($result as $internal => $row)
				{
					foreach($row as $internal2 => $col)
					{
                        $this->traits[$internal2] = $this->fields[$internal2]->getType()=='date'?convertFromDatabaseDate($col) : $col;
					}
				}
			}
		}
	}

	function getActiveJobs()
	{
		$ret=array();
		$query = "SELECT JOBID,JOBNUMBER,CONCAT(NAME,\" - \",(SELECT CONCAT(IFNULL(FIRST_NAME,''),' ',IFNULL(LAST_NAME,''),' ',COMPANY_NAME) FROM CLIENTS WHERE CLIENTID=A.CLIENTID)) AS \"CLIENTNAME\" FROM JOBS A WHERE ACTIVE=1";
		$vars = array();
		$result = $this->sqlconnect->executeQuery($query,$vars);
		if(count($result)>0)			
			foreach($result as $internal => $value)
				$ret[$value["JOBNUMBER"]." ".str_replace("\"","",$value["CLIENTNAME"])] = $value["JOBID"];
				
		return $ret;
	}

	function getGraphIMG($jobID)
	{
		$ret="";
		if(isset($jobID) && $jobID!=-1)
		{	
			global $currentURLBase;
			global $uri;
			$counts = $this->getCounts($jobID);
			if($counts[$jobID]["TOTAL"] <1 )
			$percentage=0;
			else
			$percentage = format_number_significant_figures(($counts[$jobID]["USED"] / $counts[$jobID]["TOTAL"]) * 100,2,false);
			$ret="<img src='$currentURLBase/index.php?getgraph=1&percentage=$percentage&pageid=".$uri["pageid"]."' />";
		}
		return $ret;
	}
}

class jobUI
{
	
	private $sqlconnect;
	private $uri;
	private $url;
	private $currentUser;
	private $currentURLBase;
	private $job;
	function __construct()
	{	
		global $currentUser;
		global $sqlconnect;
		global $uri;
		global $url;
		global $currentURLBase;
		$this->uri = copyArray($uri);
		$this->sqlconnect = $sqlconnect;
		$this->currentUser = $currentUser;
		$this->currentURLBase = $currentURLBase;
		$this->url = $url;
		if(isset($this->uri['jobid']) && $this->uri['jobid']>0)
        {
            $this->job = new job($this->uri['jobid']);
        }
	}
	
	function go()
	{			
		$ret="";
		if(isset($this->uri['getdata']))
		{	
			if(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1 )
			{	
				$this->getJobSearchResultsTable($this->uri['searchstring']);
				exit();
			}
			else if(isset($this->uri['bidid']))
			{
				$laborid=isset($this->uri['laborid'])?$this->uri['laborid']:null;
				$materialid=isset($this->uri['materialid'])?$this->uri['materialid']:null;
				$ret = $this->updateBidItem($this->uri['bidid'],$this->uri['dec'],$laborid,$materialid,$this->uri['footage'],$this->uri['unit'],$this->uri['total']);
			}
			
		}
		else
		{
			$ret = $this->jobEditUI();
		}
		return $ret;
	}

	function jobEditUI()
	{
		$ret="";		
		$tabArray = array();
		$name="";
				
		if(isset($this->job))
		{	
			$name = $this->job->getTraits();
			$name = $name["NAME"];
			$tabArray[] = new tabUI("editJobTab",$name,$this->getJobEditWrapper($this->job, array("jobTab"=>count($tabArray))));
		}
		$ret.="<div class=\"regularBox\"><div class=\"title\">Jobs</div>";
		
		$tabArray[] = new tabUI("searchJobsTab","Search Jobs",$this->getJobSearchResultsTable(null));
		$tabArray[] = new tabUI("createNewJobTab","Create New Job",$this->getCreateJobForm(array("jobTab"=>count($tabArray))));
		
		$tabs = new tabsUI($tabArray,"jobTab");
		
		$ret.=$tabs->getTabHTML()."</div>";
		
		return $ret;
	
	}
	
	function getJobEditWrapper($jobObject, $tabInfo)
	{
		$ret="";
		if(isset($jobObject) && get_class($jobObject)!==false && get_class($jobObject)=='job')
		{	
			$tabArray = array();
			
			$name = $jobObject->getTraits();
			$name = $name["NAME"];
			$revisions = $this->getRevisionList($jobObject,array("getJobEditWrapper"=>count($tabArray)));
			$editForm = $this->getJobEditForm($jobObject,array("getJobEditWrapper"=>count($tabArray)));
			if(strlen($revisions)>0)
			{
				$html = "<div class=\"regularBox\" id=\"jobEditorBox\"><div class=\"title\">Edit Job</div>
				<table><tr><td style='vertical-align: top;'>".$editForm."</td><td  style='vertical-align: top;'>".
				$revisions.
				"</td></tr></table></div>";
			}
			else
				$html = $editForm;
			$tabArray[] = new tabUI("editJob","Basic Info",$html);
			$tabInfo["editJob"]=count($tabArray);
			$groupEditForm = $this->jobBidGroupEditForm($jobObject->getJobID(),$this->revID,copyArray($tabInfo));
			if(strlen($groupEditForm)>0)
				$tabArray[] = new tabUI("jobBidsList","Job Bids",$groupEditForm);
			
			$tabInfo["editJob"]=count($tabArray);			
			$tabArray[] = new tabUI("addBidData","Upload Bid Data",$this->importBidFiles(copyArray($tabInfo)));
			
			$tabs = new tabsUI($tabArray,"editJob");
			$ret.="<div class=\"regularBox\"><div class=\"title\">$name</div>";
			$ret.=$tabs->getTabHTML()."</div>";
		}
		return $ret;
	}
	
	function getJobEditForm($jobObject, $tabInfo)
	{
		$ret="";
		if(isset($jobObject) && get_class($jobObject)!==false && get_class($jobObject)=='job')
		{	
			$stuff = $this->job->getTraits();
			$name = $this->job->getTraits();
			$name = $name["NAME"];
			$fields = $jobObject->getFields();
			$formPostVals = array();
			$formInputs = array();
			$error=array();
			
			if(isset($_POST['submitJob']))
			{
				foreach($fields as $internal => $value)
				{
					$formPostVals[$internal]=$_POST[$internal];
					if($value->getType() == "checkbox")
					{
						$formPostVals[$internal]=(isset($_POST[$internal])?1:0);
					}
				}
				// $formPostVals["JOBID"] = $jobObject->getJobID();
				$result = $jobObject->update($formPostVals);
				if($result===true)
				{
					addDebug("Job Submit Complete - Adding Change Tracking");
					$error[] = "<div class=\"submitsuccess\">Information Updated Successfully!</div>";
					$stuff = $jobObject->getTraits();
					$number = $jobObject->getJobID();
					$tracking = new tracking(null,null,"Changed",null,null,null,"Job $name;$number;jobs;jobid",null);
					$tracking->write();
				}
				else
				$error = $result;
			}
			else
			{		
				foreach($stuff as $internal => $value)
				$formPostVals[$internal]=$value;
			}
			
			foreach($fields as $internal => $value)
			{
				$extraclass = $value->getRequired()===true?"req":"";
				$extraHTML = $value->getExtraHTML();
				if($value->getType() == "checkbox")
				{
					if($formPostVals[$internal]===1)
					{
						$extraHTML.="checked=\"checked\"";
					}
				}
				if($value->getType() == "dropdown")
				{
					$extraclass.=" searchabledropdown";	
				}
				$formInputs[$internal] = createHTMLTextBox($internal,$value->getFriendlyName(),$value->getMaxWidth(),$extraclass,false,$formPostVals[$internal],$value->getRequired(),$extraHTML,true,$value->getType());
				
			}
			$submit = createHTMLTextBox("submitJob","",5,"",false,"UPDATE",true,"",false,"submit");		
			$ret.="<div class=\"regularBox\" id=\"jobEditorBox\"><div class=\"title\">$name - Basic Info</div>
			<div class=\"submiterror\">";
			foreach($error as $internal => $value)
				$ret.=$value."<br />";
			$ret.="</div><div id=\"prevwagediv\"></div>";
			
			$actionUrl = getComebackURLString($tabInfo);
			$ret.="<form id=\"jobForm\" name=\"jobForm\" method=\"post\" action=\"$actionUrl\" onsubmit=\"return validate('jobForm');\"><table>";
			foreach($formInputs as $internal => $value)
			$ret.="<tr>".$value."</tr>";
			$ret.="<tr><td colspan=\"2\">$submit</td></tr>";
			$ret.="</table></form>";
			$ret.="</div>!purchaseorderstuff!";
			$ret = str_replace("!purchaseorderstuff!",$this->getRelatedPOUI($jobObject),$ret);
		}
		return $ret;
	}
	
	function getRelatedPOUI($jobObject)
	{
		$ret="";
		if($this->currentUser->getPrivileges()->findID("purchaseorders")!==false)
		{
			if(isset($jobObject) && get_class($jobObject)!==false && get_class($jobObject)=='job')
			{	
				$relatedPOs = $jobObject->getRelatedPOs();			
				if(is_array($relatedPOs))
				{
					$ret.="<div class=\"regularBox\" id=\"jobRelatedPOsPanel\"><div class=\"titlesmaller\">Related POs</div><ul>";
					
					foreach($relatedPOs as $interal => $value)
					{
						$ret.="<li><a href='".makeLink($value["PURCHASEORDERID"],"purchaseorders",null)."'>".$value["PONUM"]."</a></li>";
					}
					$ret.="</ul></div>";
				}
			}
		}
		
		return $ret;
	}
	
	function getJobSearchResultsTable($searchstring)
	{	
		$anchorProps =array("NAME"=>"");
		#"(CASE ACTIVE WHEN 0 THEN \"NO\" WHEN 1 THEN \"YES\" ELSE ACTIVE END) AS ACTIVE",
		
		/*"'input type=\"checkbox\" checked=\"'
		||(CASE ACTIVE WHEN 0 THEN \"\" WHEN 1 THEN \"checked\" ELSE ACTIVE END)||'\"
		class=\"quickjobactivate\" jobid=\"'||A.JOBID||'\" '",*/
		
		$ret="<div class=\"regularBox\"><div class=\"title\">Search Jobs</div>";
		$selectCols = array("JOBID","JOBNUMBER","CONCAT(IFNULL((SELECT COMPANY_NAME FROM CLIENTS WHERE CLIENTID=A.CLIENTID),''),' - ',IFNULL(NAME,'')) AS NAME","STARTDATE","ENDDATE",
		"(CASE ACTIVE WHEN 0 THEN \"NO\" WHEN 1 THEN \"YES\" ELSE ACTIVE END) AS ACTIVE",
		
		"IFNULL((SELECT COUNT(DISTINCT REVISION) FROM JOB_BID_DATA WHERE JOBID=A.JOBID),'None') AS BIDS");
		$showCols = array("JOBNUMBER"=>"NUM","NAME"=>"Name","STARTDATE"=>"Start Date","ENDDATE"=>"End Date","ACTIVE"=>"Job Active","BIDS"=>"Bids");
		$ClickPos=array("NAME"=>"JOBID");
		$searchCols = array("NAME","STARTDATE","ENDDATE","ACTIVE");
		$tableID = "jobSearchTable";
		$uriValClick = array("NAME"=>"jobid");
		$additionalURI = array("NAME"=>"pageid=".$this->uri['pageid']);
		$extraWhereClause = "ACTIVE=1";
		$search=null;
		$getRaw=null;
		$orderClause = "STARTDATE DESC LIMIT 50";
		if(isset($searchstring))
		{
			$search=$searchstring;
			$getRaw=1;
			$orderClause="STARTDATE DESC";
			$extraWhereClause="";
		}
		
		$resultTable = makeSearchTable("JOBS A",$selectCols,$ClickPos,$showCols,$searchCols,$tableID,$uriValClick,$additionalURI,$anchorProps,$search,$extraWhereClause,$orderClause,$getRaw);
		if(isset($searchstring))
		{
			echo json_encode($resultTable);
		}
		else
		{		
			$ret.=$resultTable."</div>";
	
			return $ret;
		}
	}
	
	function getCreateJobForm($tabInfo)
	{	
		
		addDebug("Create New Job UI Starting..");
		$ret = "";
		$error = "";
		$showForm=true;
		$job = new job(-1);
		$formInputs = array("createJobDiv_NAME"=>"","createJobDiv_STARTDATE"=>"","createJobDiv_CLIENTID"=>"");
		$formPostVals = array();
		if(isset($_POST['submitNewJob']))
		{
			foreach($formInputs as $internal => $value)
			$formPostVals[$internal]=$_POST[$internal];
			
			$result = $job->createNewJob($formPostVals['createJobDiv_NAME'],$formPostVals['createJobDiv_STARTDATE'],$formPostVals['createJobDiv_CLIENTID']);
			if(is_numeric($result))
			{
				$showForm=false;
				$this->uri["jobid"]=$result;
				foreach($this->uri as $internal => $value)
				{
					if(strstr($internal,"come")===false)
					$urit.="&$internal=$value";
				}
				$job = new job($result);
				$name = $job->getTraits();
				$name = $name["NAME"];
				$error = "<div class=\"submitsuccess\">New Job Created Successfully</div><br /><a href=index.php?$urit>Edit $name</a>";
				$tracking = new tracking(null,null,"Created New Job",null,null,null,"Client $name;$result;jobs;jobid",null);
				$tracking->write();
			}
			else
			$error = $result;
		}
		if($showForm)
		{
			$jobStuff = $job->getFields();
			
			foreach($formInputs as $internal => $value)
			{	
				$int = str_replace("createJobDiv_","",$internal);
				$add="";
				if($int=="CLIENTID")
				$add.="searchabledropdown";				
				
				$formInputs[$internal] = createHTMLTextBox($internal,$jobStuff[$int]->getFriendlyName(),$jobStuff[$int]->getMaxWidth(),$jobStuff[$int]->getRequired()?"req $add":"$add",false,$formPostVals[$internal],$jobStuff[$int]->getRequired(),$jobStuff[$int]->getExtraHTML(),true,$jobStuff[$int]->getType());
			}
			
			$submit = createHTMLTextBox("submitNewJob","",5,"",false,"Create Job",true,"",false,"submit");			
			$actionUrl = getComebackURLString($tabInfo);
			$ret="<div class=\"regularBox\" id=\"createJobDiv\">
			<div class=\"title\">Create New Job</div><div class=\"submiterror\">$error</div>
			<form id=\"createJobForm\" name=\"createJobForm\" method=\"post\" action=\"$actionUrl\" onsubmit=\"return validate('createJobForm');\">
			<table>";
			foreach($formInputs as $internal => $value)
			$ret.="<tr>".$value."</tr>";
			$ret.="</table>$submit</form>";
			$ret=$ret;
			$ret.="</div> <!-- END createJobDiv -->";
		}
		else
		$ret.=$error;
		return $ret;
	}
	
	function getRevisionList($jobObject, $tabInfo)
	{
		$ret= "";
		if(isset($jobObject) && get_class($jobObject)!==false && get_class($jobObject)=='job')
		{	
			$traits = $jobObject->getTraits();
			if($traits["ACTIVE"]==0)
			{
				$current = $jobObject->getCurrentBidRevision();
				$ret="<div class=\"regularBox\" id=\"editRevisionsDiv\"><div class=\"titlesmaller\">Bid Revisions</div><div id=\"bidRevisionUpdateThis\">";
				$revs = $jobObject->getBidRevisions();
				if(count($revs)>0)
				{
					$table = "<table>";
					foreach($revs as $internal => $value)
					{	
						$table.="<tr>";
						$price = $value[0];
						$footage = $value[1];
						$date = $value[2];
						$chosenClass = "notchosen";
						$chooseButton = "";
						if($internal == $current)
							$chosenClass = "chosen";						
						else						
							$chooseButton = "<input type =\"button\" id=\"bidrevision$internal\" class=\"bidRevisionButton\" rev=\"$internal\" jobid=\"".$jobObject->getJobID()."\" updatespan = \"bidRevisionUpdateThis\" value = \"Choose\" />";
						
						$title = "<span id=\"title$internal\" class=\"$chosenClass\">Revision $internal $date $$price</span>";
						$table.="<td>$title</td><td>$chooseButton</td></tr>"; 
					}
					$table.="</table>";
					$ret.="$table</div></div>";
				}
				else $ret="";
			}
			else $ret="";
		}
		
		return $ret;	
	}
	
	function setBidRevision($jobObject,$bidRevision)
	{
		$ret="";
		$worked = $jobObject->decideBidRevision($bidRevision);
		if($worked!==false)
		{
			$name = $jobObject->getTraits();
			$name = $name["NAME"];
			$number = $jobObject->getJobID();
			$tracking = new tracking(null,null,"Assigned Bid $bidRevision",null,null,null,"Job $name - $number;$number;jobs;jobid",null);
			$tracking->write();
			$ret = "<div class=\"submitsuccess\">Bid Revision $bidRevision Assigned Successfully</div>";
		}
		
		return $ret;
		
	
	}
	
function updateBidItem($bidID,$desc,$laborid,$materialid,$footage,$unit,$total)
	{
		$ret="";
		$jobBid = new jobBid($bidID);
		if($jobBid->getBidID() > -1)
		{
			$traits = $jobBid->getTraits();
			if($materialid != null)
				$traits["MATERIALID"] = $materialid;
			if($laborid != null)
				$traits["LABORID"] = $laborid;
			$traits["DESCRIPTION"] = $desc;
			$traits["FOOTAGE"] = $footage;
			$traits["UNIT_PRICE"] = $unit;
			$traits["TOTAL_COST"] = $total;
			//print_r($traits);
			$errors = $jobBid->update($traits);
			if($errors!==true)
			{
				$ret="<div class='submiterror'>";
				foreach($errors as $internal => $value)
				$ret.="$value <br />";
				
			}
			else
			$ret = "<div class='submitsuccess'>Success";
			
		}
		else $ret="<div class='submiterror'>Invalid bid ID";
		
		$ret.="</div>";
		return $ret;
	}
	
	function importBidFiles($tabInfo)
	{
		$showForm = true;
		$ret="";
		if(isset($_POST["comfirmImportButton"]))
		{
			if(isset($_SESSION["bidimport"]))
			{
				$jobBidGroup = new jobBidGroup(null,null);
				$importResult = $jobBidGroup->createNewJobBidGroup($_SESSION["bidimport"],true);
				if($importResult[0]===false)
				{
					$i=0;
					$ret.="<div class=\"submiterror\">There was an error importing<br />Please review these details:</div>";
					foreach($importResult as $internal => $value)
					{
						if($i!=0)
						{
							$ret.=$value."<br />";
						}
						$i++;
					}
					$ret.="<br /><br /><br />";
				}
				else
				{
					$ret.="<div class=\"submitsuccess\">Your data has been imported successfully!</div>";
					$job = new job($jobBidGroup->getJobID());
					$tra = $job->getTraits();
					$tracking = new tracking(null,null,"Import Bids",null,null,null,"Job ".$tra["NAME"].";".$jobBidGroup->getJobID().";jobs;jobid",null);
					$tracking->write();
				}
			}
		}
		else if(isset($_POST["submitButton"]))
		{
			$fileClass = new fileIOClass();			
			$safe = $fileClass->fileIsSafe($_FILES["uploadFileName"]['name']);
			if($safe===false)
			$error = "This file does not look safe - please upload the correct file";
			else
			{				
				$csvArray = $fileClass->parse($_FILES["uploadFileName"]['tmp_name'], $_FILES["uploadFileName"]['name']);
				foreach($csvArray as $internal => $value)
				{
					foreach($value as $internal2 => $value2)
					$value[$internal2]=trim($value2);
				}
				$newJobBidGroup = new jobBidGroup(null,null);
				$result=$newJobBidGroup->importBidsFromArray($csvArray,$this->job->getJobID());
				if(is_array($result))
				{
					if(isset($result[0]) && $result[0]===false)
					{
						$ret.="<div class=\"submiterror\">There was an error processing your file:</div>";
						foreach($result as $internal => $value)
						{
							$ret.=$value."<br />";
						}
						$showForm=true;
					}
					else
					{
						$ret.="<div class=\"submitsuccess\">The file looks good - here is what we received</div>";
						$_SESSION['bidimport'] = copyArray($result);

						# Let's remove the JOBID from the UI because it doesn't matter
						foreach($result as $internal => $value)							
							unset($result[$internal]["JOBID"]);

						$ret.=drawHTMLTableFrom2DArray($result, "reportResultsTable");
						
						$actionUrl = getComebackURLString($tabInfo);
						$ret.="<form id=\"comfirmImport\" name=\"jobForm\" method=\"post\" action=\"$actionUrl\">
						<input type=\"submit\" name=\"comfirmImportButton\" value=\"Confirm and Submit\" />
						</form>";
						$showForm=false;
					}
				}
				else
				{
					$ret="There was an error - Please review your file and try again";
					$showForm=true;
				}
			}
		}
		
		if($showForm===true)
		{
			$fileClass = new fileIOClass();
			$ret.="<div class=\"regularBox\"><div class=\"title\">Import Bid Data</div>";
			$actionUrl = getComebackURLString($tabInfo);
			$ret.=$fileClass->getFileUploadForm("uploadForm","uploadFileName","submitButton", "$actionUrl");
			$ret.="</div><br />";
			
		}
		
		return $ret;

	}
	
	function jobBidGroupEditForm($jobID, $revID, $tabInfo)
	{
		$ret="";
		$showForm = true;		
		if(is_null($revID) || $revID<1)
		{
			$query="SELECT REVISION FROM JOB_BID_DATA WHERE JOBID=?";
			$vars= array($jobID);
			$result = $this->sqlconnect->executeQuery($query,$vars);
			$org=-1;
			$revisionArray=array();
			foreach($result as $internal => $value)
			{	
				if(!in_array($value["REVISION"],$revisionArray))
				$revisionArray[]=$value["REVISION"];
			}
			if(count($revisionArray)>1)
			{
				$actionUrl = getComebackURLString($tabInfo);
				$ret.="<div class=\"regularBox\"><div class=\"title\">Choose Revsion</div>";
				for($i=0;$i<count($revisionArray);$i++)
				$ret.="<div class=\"revID\"><a href=\"$actionUrl&revid=".$revisionArray[$i]."\">Revision ".$revisionArray[$i]."</a></div>";
				$ret.="</div>";
				$showForm=false;
			}
			else
			{
				$revID = $revisionArray[0];
			}
			
		}
		if($showForm===true)
		{				
			$query="SELECT BID_SEQUENCE FROM JOB_BID_DATA WHERE JOBID=? AND REVISION=?";
			$vars= array($jobID,$revID);
			$result = $this->sqlconnect->executeQuery($query,$vars);
			$bidArray = array();
			$ret.="";			
			foreach($result as $internal => $value)
			{
				//$bidArray[]=;
				$back =  $this->bidEditForm(new jobBid($value["BID_SEQUENCE"]));
				if($back!="")
					$ret.="$back\n";
					
			}
		}
		return $ret;//."\n\n\n<script type=\"text/javascript\">$('label').css('display','none')</script>\n\n";
	
	}
	
	function bidEditForm($bid)
	{	
		$notEditable = array("JOBID","REVISION","INSERT_DATE");
		$traits = $bid->getTraits();
		$fields = $bid->getFields();
		$id=$bid->getBidID();
		$ret="<div class=\"bidSequence\" id=\"bidseq_$id\">";
		foreach($fields as $internal => $value)
		{	
			if($internal=="LABORID" || $internal=="MATERIALID")
			{	
				
				if($internal=="LABORID" && $traits[$internal]=="")
				{}
				else if($internal=="MATERIALID" && $traits[$internal]=="")	
				{}
				else
				{
					$ret.=createHTMLTextBox($bid->getBidID()."_".$internal,$value->getFriendlyName(),$value->getMaxWidth(),"bidinput searchabledropdown",false,$traits[$internal],$value->getRequired(),$value->getExtraHTML(),false,$value->getType(),false);
					$ret.=createHTMLTextBox($bid->getBidID()."_".$internal."_org","","10","",false,$traits[$internal],false,"",false,"hidden",false);
				}
			}
		}
		$ret.="<span id=\"bidUpdateOutput_$id\"></span>";
		$ret.="<table><tr>";
		foreach($fields as $internal => $value)
		{	
			if(!in_array($internal,$notEditable))
			{
				
				if($internal=="LABORID" || $internal=="MATERIALID")
				{}
				else
				{	
					$ret.=createHTMLTextBox($bid->getBidID()."_".$internal,$value->getFriendlyName(),$value->getMaxWidth(),"bidinput",false,$traits[$internal],$value->getRequired(),$value->getExtraHTML(),true,$value->getType(),false);
					$ret.=createHTMLTextBox($bid->getBidID()."_".$internal."_org","","10","",false,$traits[$internal],false,"",false,"hidden",false);
				
				}
			}
			
		}
		$ret.="<td><input type=\"button\" name=\"changeBid_$id\" id=\"changeBidButton_$id\" class=\"changeBidButton\" value=\"Chg\" /></td></tr></table><div class=\"bidseqFeedback\" id=\"feedback_$id\"></div></div>";
		return $ret;
	}
	
	function getBidSearchResultsTable()
	{	
		$anchorProps =array("NAME"=>"");
		$ret="<div class=\"regularBox\"><div class=\"title\">Search Bids</div>";
		$selectCols = array("JOBID","REVISION","(SELECT CONCAT(IFNULL((SELECT COMPANY_NAME FROM CLIENTS WHERE CLIENTID=A.CLIENTID),''),' - ',IFNULL(NAME,'')) FROM JOBS A WHERE JOBID=B.JOBID) AS NAME","INSERT_DATE AS DATE","SUM(TOTAL_COST) AS COST");
		$showCols = array("JOBID"=>"Job ID","NAME"=>"Name","DATE"=>"Date","COST"=>"Total Cost");
		$ClickPos=array("NAME"=>"JOBID");
		$searchCols = array("NAME","STARTDATE","ENDDATE","ACTIVE");
		$tableID = "bidSearchTable";
		$uriValClick = array("NAME"=>"jobid");
		$additionalURI = array("NAME"=>"pageid=".$this->uri['pageid']);
		$resultTable = makeSearchTable("JOB_BID_DATA B GROUP BY JOBID,REVISION ORDER BY JOBID",$selectCols,$ClickPos,$showCols,$searchCols,$tableID,$uriValClick,$additionalURI,$anchorProps,$search,"","");
		$ret.=$resultTable."</div>";
		
		//$ret.=$this->importClientFile();
		return $ret;
	}
	
	function getPrevailingWageForm($jobObject)
	{
		$ret = "";
		if(isset($jobObject) && get_class($jobObject)!==false && get_class($jobObject)=='job')
		{
			$formInputs = array();
			$query="SELECT JOBPREVAILINGWAGEID,(SELECT CONCAT(GROUPID,' ',NAME) FROM LABOR_GENERAL WHERE GENERALID=A.GENERALID) \"NAME\",AMOUNT FROM JOB_PREVAILING_WAGE A WHERE JOBID=? ORDER BY (SELECT GROUPID FROM LABOR_GENERAL WHERE GENERALID=A.GENERALID)";
			$vars = array($jobObject->getJobID());
			$result = $this->sqlconnect->executeQuery($query,$vars);
			$num = 0;
			foreach($result as $internal => $row)
			{	
				$formInputs[] = createHTMLTextBox("prev".$num,$row["NAME"],10,'prevWageInput',true,$row["AMOUNT"],true,"jobprev='".$row["JOBPREVAILINGWAGEID"]."'",false,"text");
				$num++;
			}
			$ret.="<div class=\"regularBox\"><div class=\"title\">Prevailing Wage</div>";
			foreach($formInputs as $internal => $value)
			{
				$ret.=$value."<br /><hr />";
			}
			$ret.="</div>";
		}
		return $ret;
	}
	
}