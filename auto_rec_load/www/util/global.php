<?php

require_once ("sqlconnect.php");
require_once ("loginclass.php");
require_once ("session.php");
require_once ("user.php");
require_once ("dashboard.php");
require_once ("control_panel.php");
require_once ("files.php");
require_once ("marc.php");
require_once ("vendors.php");
require_once ("notice.php");
require_once ("ui/dbfieldclass.php");
require_once ("ui/tabs.php");



ini_set('session.gc_maxlifetime',1200);
ini_set('session.gc_probability',1);
ini_set('session.gc_divisor',1);

global $debug;
if($debug === true)
{
	error_reporting(E_ALL);
	ini_set('display_errors', TRUE);
	ini_set('display_startup_errors', TRUE);
}

session_start();


global $debugOutput;
global $sqlconnect;
global $currentUser;
global $currentURLBase;
global $uri;
global $uriString;
global $url;
global $tablePrefix;
global $rootWWW;

$tablePrefix = "auto_";
$rootWWW = getcwd();
$debugOutput = array();
$sqlconnect = new sqlconnect();

/******          Setup URL               */
    $currentURLBase = (!empty($_SERVER['HTTPS'])) ? "https://".$_SERVER['SERVER_NAME'] : "http://".$_SERVER['SERVER_NAME'];
    $url = (!empty($_SERVER['HTTPS'])) ? "https://".$_SERVER['SERVER_NAME'].$_SERVER['REQUEST_URI'] : "http://".$_SERVER['SERVER_NAME'].$_SERVER['REQUEST_URI'];
    $debugOutput[]= "URL = $url";
    $uriString = parse_url($url);

    $parts = array();
    $uri = array();
    if(array_key_exists('query', $uriString))
    {
        $parts = explode('&', $uriString['query']);
        $uriString = $uriString['query'];
        foreach ($parts as $param)
        {
            //echo $param."<br />";
            $item = explode('=', urldecode($param));
            if(count($item)==2)
            {
                $uri[$item[0]] = $item[1];
                //echo $item[0]." = ".$item[1]."</br >";
            }
            else if(count($item)==1)
                $uri[$item[0]] = "";
        }
        if(!(array_key_exists("pageid",$uri)))
        {
            $uri["pageid"] = 1; # always load dashboard
        }
    }
    else
    {
        $uriString = '';
        $uri["pageid"] = 1;
    }
    

/******END          Setup URL               */
        
/******          Setup User               */

    if(isset($_SESSION["currentUser"]))
    {
        $currentUser=new user($_SESSION["currentUser"]);
    }
    else
    {
        $_SESSION["currentUser"] = 1; # disabling login for now, always logged in with superuser
        $currentUser = new user($_SESSION["currentUser"]);
    }

/****** END         Setup User               */
	
	foreach($_POST as $internal => $value)
	{
		addDebug("$internal = ".$_POST[$internal]);
		$_POST[$internal] = htmlspecialchars(stripslashes($value));
	}

function makePageHtml($whichPage,$resultCount,$uri,$perPageNum)
{
	$pageHtml="";
	$uri=str_replace("?","",$uri);
	if($resultCount>$perPageNum)
	{
		$pageHtml=$pageHtml."<br /><table id=\"tablepages\"><tr>";
		$rowNum=0;
		$pageNum=1;
		while($rowNum<$resultCount)
		{
			$pageHtml=$pageHtml."<td><a href=\"$whichPage?page=$pageNum&$uri\">".$pageNum."</a></td>";
			$rowNum+=$perPageNum;
			if(($pageNum%10==0)&&$rowNum<$resultCount)
			$pageHtml=$pageHtml."</tr><tr>";
			$pageNum++;
		}
		$pageHtml=$pageHtml."</tr></table><br />";
	}

	return $pageHtml;

}

function redirectTo($url)
{
	//echo "Redirecting to $url";
	echo "<a href=\"$url\">Please Wait.....</a><META HTTP-EQUIV=REFRESH CONTENT=\"1; URL=$url\">";
}

function format_number_significant_figures($number, $dp, $commas) 
{	
	$number = round($number, $dp);
	if($commas===true)
	$number = number_format($number, $dp);
	return $number;
}

function createHTMLTextBox($id, $label, $maxSize, $additionalClass, $labelTop, $datavalue, $required, $extraStuff, $table, $type, $showLabel = true)
{
	global $sqlconnect;
	$ret="";
	if($type=="date")
	{
		$type="text";
		$additionalClass.=" date";
	}
	if($showLabel)
	{
		if(($type!="submit") && ($type !="button") && ($type !="hidden"))
		{
			if($table)
			$ret.="<td>";
			$ret.="<label for=\"$id\">$label";
			if($required)
			$ret.="<span class=\"requiredfield\">  *</span>";
			$ret.="</label>";
			if(!$table && $labelTop)
			$ret.="<br />";
			if($table)
			$ret.="</td><td>";
		}	
	}
	else if($table)
		$ret.="<td>";
	if($type=="textarea")
	{
		$ret.="<$type id=\"$id\" name=\"$id\" class=\"$additionalClass\" $extraStuff>$datavalue</$type>";
	}
	else if($type=="dropdown")
	{
		$options = array();
		if(is_array($extraStuff)===false)
		{
			$query = $extraStuff;
			//addDebug($query);
			$result = $sqlconnect->executeQuery($query,array());
			
			
			$rowHeader1=-1;
			$rowHeader2=-1;
			foreach($result as $internal => $row)
			{
				if($rowHeader1==-1)
				{
					$i=0;
					foreach($row as $internal2 => $val2)
					{
						if($i==0)
						$rowHeader1=$internal2;
						else
						$rowHeader2=$internal2;
						$i++;
					}
				}
					
				$options[$row[$rowHeader1]]=$row[$rowHeader2];
			}
		}
		else
		$options = $extraStuff;
		
		$ret.= createDropDownHTML($options,$id,$datavalue,$additionalClass);
	}
	/*else if($type=="checkbox")
	{
		$checked = "";
		if(strtoupper($datavalue)=='CHECKED')
		$checked = " checked=yes ";
		$ret.="<input type=\"$type\" id=\"$id\" name=\"$id\" class=\"$additionalClass\" $extraStuff $checked />";
	}*/
	else
	{
		$ret.="<input type=\"$type\" id=\"$id\" name=\"$id\" class=\"$additionalClass\" maxlength=\"$maxSize\" $extraStuff value=\"$datavalue\" />";
	}
	
	if(($table)&&($type!="submit") && ($type !="button")&& ($type !="hidden"))
	$ret.="</td>";
	return $ret;
}

function decideUI()
{
	$ret=null;
	global $uri;
	global $currentUser;
	global $sqlconnect;
    global $tablePrefix;
	if(isset($uri["pageid"]))
	{
		$classToCall="";
		$query = "SELECT CLASS_NAME FROM " . $tablePrefix . "wwwpages WHERE ID=?";
		$vars = array($uri["pageid"]);
		$result = $sqlconnect->executeQuery($query,$vars);
		if(count($result)==1)
		{
			foreach($result as $internal => $value)
			$binding = '$classToCall = new '.$value["CLASS_NAME"].'();';
			eval($binding);
			$ret=$classToCall;
		}
	}

	return $ret;

}

function generateRandomString($strLen)
{

	$ret="";
	$nums = array('2','3','4','5','6','7','8','9');
	$alph = array('a','b','c','d','e','f','g','h','k','m','n','p','q','r','s','t','u','v','w','x','y','z');
	$i=$strLen;
	while($i>0)
	{
		//echo"ret = $ret<br />";
		if($i>4)
		{
			$rand_keys = array_rand($alph);
			$upper = array("0","1");
			$ra = array_rand($upper);
			if($ra==0)
			$ret.=strtoupper($alph[$rand_keys]);
			else
			$ret.=$alph[$rand_keys];
		}
		else
		{
			$rand_keys = array_rand($nums);
			$ret.=$nums[$rand_keys];
		}

		$i--;
	}

	return $ret;

	
}

function allowedHere()
{
	global $currentUser;
	global $uri;
	$ret=true;
	return $ret;
}

function ensureDate($date) # Expects m-d-y or y-m-d
{
	$split = preg_split("/[\\/\\\-]/", $date);
	# Must must be a date
	if(count($split) == 3)
	{
		if(strlen( $split[0]) < 2 ) $split[0] = "0".$split[0];
		if(strlen( $split[1]) < 2 ) $split[1] = "0".$split[1];
		if(strlen( $split[2]) < 2 ) $split[2] = "0".$split[2];
		
		return $split[0].'-'.$split[1].'-'.$split[2];
	}
	return null;
}


function convertToDatabaseDate($date)
{
	
	$ret = ensureDate($date);
	$keywords = preg_split("/[\\/-]/",$ret);
	if(count($keywords)==3)
	{	
		if((strlen($keywords[0])<3)&&(strlen($keywords[1])<3)&&(strlen($keywords[2])==4))
		{
			$ret = $keywords[2].'-'.$keywords[0].'-'.$keywords[1];
		}
	}

	return $ret;
}

function convertFromDatabaseDate($date)
{
	
	$ret = ensureDate($date);
	$keywords = preg_split("/[\\/-]/",$date);
	if(count($keywords)==3)
	{	
		if((strlen($keywords[0])==4)&&(strlen($keywords[1])<3)&&(strlen($keywords[2])<3))
		{	
			$ret = $keywords[1].'-'.$keywords[2].'-'.$keywords[0];
		}
	}

	return $ret;
}
	
function addDebug($string)
{
	global $debugOutput;
	$debugOutput[]=$string;
}

function makeSearchTable($dbTable,$columnNames,$clickableIDPosition,$showColumns,$searchableColumns,$tableID,$uriValForClick,$additionalUri,$additionalAnchorProperties,$searchString,$extraWhereClause, $orderClause, $getRaw = null, $groupClause)
{
	global $sqlconnect;
	global $currentURLBase;
	global $uri;
	global $url;
	
	$json=array();
	$ret="";
	$query="SELECT ";
	foreach($columnNames as $internal => $value)
	{
		$query.="\n$value,";
	}
	$query=substr($query,0,strlen($query)-1)." FROM $dbTable";
	$vars = array();
	if(isset($searchString))
	{
		if(count($searchableColumns)>0)
		{
			$query.=" WHERE (";
			foreach($searchableColumns as $internal =>$value)
				{
					$query.=" (UPPER($value) REGEXP ?) OR";
					$vars[]=trim(strtoupper($searchString));
				}
				$query=substr($query,0,strlen($query)-2);
				$query.=")";
		}
	}
	if(isset($extraWhereClause) && strlen($extraWhereClause)>0)
	{
		if(isset($searchString))
		$query.=" AND $extraWhereClause";
		else
		$query.=" WHERE $extraWhereClause";
	}
    if(isset($groupClause) && strlen($groupClause)>0)
	{
		$query.=" GROUP BY $groupClause";
	}
	if(isset($orderClause) && strlen($orderClause)>0)
	{
		$query.=" ORDER BY $orderClause";
	}
	// echo"<pre>$query</pre>";
    // exit;
	addDebug("Make Table Query = $query");
	$result = $sqlconnect->executeQuery($query,$vars);

    $ret = "<table id=\"$tableID\" class=\"tablesorter\">
        <thead><tr>";
    foreach($showColumns as $dbName => $humanColName)
    $ret.="<th>$humanColName</th>";
    $ret.="</tr></thead><tbody>";
    $i=0;
    // echo "Result count: " . count($result) . "<br />";
    // print_r($result);
    // exit;
    foreach($result as $internal => $row)
    {
        $ret.="<tr>";
        
        $rowForJSON = array();
        $shade="";
        if($i % 2==0)
        $shade=" class=\"rowshade\"";
        
        foreach($row as $colName => $colValue)
        {
            $colPos=0;
            foreach($showColumns as $showPos => $showName)
            {
                if($colName==$showPos)
                {	
                    $showPositionLinkable=-1;
                    $id="";
                    $uriVal="";
                    $additionURI="";
                    $additionalAnchorProps="";
                    $makeLinkaable=false;
                    if(isset($clickableIDPosition[$colName]))
                    {	
                        if(isset($clickableIDPosition[$colName]))
                        {
                            $id=$row[$clickableIDPosition[$colName]];
                            $makeLinkaable=true;
                        }
                        if(isset($uriValForClick[$colName]))
                        {	
                            $uriVal=$uriValForClick[$colName];
                        }
                        if(isset($additionalUri[$colName]))
                        $additionURI=$additionalUri[$colName];
                        if(isset($additionalAnchorProperties[$colName]))
                            $additionalAnchorProps=$additionalAnchorProperties[$colName];
                    }
                    
                    #addDebug("$colName = $showPos");
                    #$stringForJSON=preg_replace('/"/i','\\"',$colValue);
                    $stringForJSON=$colValue;
                    if($makeLinkaable===true)
                    {
                        #$stringForJSON="<a $additionalAnchorProps href=\\\"".$currentURLBase."/index.php?$uriVal=$id&$additionURI\\\"";
                        $stringForJSON="<a $additionalAnchorProps href=\"".$currentURLBase."/index.php?$uriVal=$id&$additionURI\"";
                        $ret.="<td$shade><a $additionalAnchorProps href=\"".$currentURLBase."/index.php?$uriVal=$id&$additionURI\"";
                        if(isset($uri['iframe']))
                        {
                            $ret.=" target='_parent'";
                            $stringForJSON.=" target='_parent'";
                        }
                        $ret.=">$colValue</a></td>";
                        #$colValue=preg_replace('/"/i','\\"',$colValue);
                        #$stringForJSON.=">$colValue<\\/a>";
                        $stringForJSON.=">$colValue</a>";
                    }
                    else
                    {
                        $ret.="<td$shade>$colValue</td>";
                    }
                    if(!isset($stringForJSON)) # make null values a blank string
                    {
                        $stringForJSON = '';
                    }
                    $rowForJSON[$showName]=$stringForJSON;
                }
                $colPos++;
            }
        }
        $ret.="</tr>";
        $json[]=$rowForJSON;
        $i++;
    }
    $ret.="</tbody></table>";//<div id=\"pager\" class=\"pager\"></div>";

	// echo"<xmp>";
	// print_r( $json);
	// echo"</xmp>";
	if($getRaw){return $json;}
	return $ret;
	
}

function getComebackURLString($tabInfo)
	{
		global $uri;
		global $currentURLBase;
		$ret="";
		
		if(isset($tabInfo) && count($tabInfo)>0)
		{	
			$gatheredComeback = array();
			$gatheredComeTabIDs = array();
			$takenIDs=array();
			$availableID=0;
			$otherURI = array();
			foreach($uri as $internal => $value)
			{
				$other = true;
				if(strlen($internal)>8)
				{
					if(substr($internal,0,8)=='comeback')
					{
						$thisID = str_replace('comeback',"",$internal);
						if(!isset($tabInfo[$uri['comeval'.$thisID]]))
						{	
							$takenIDs[$thisID]="";
							$gatheredComeback['comeval'.$thisID]=$uri['comeval'.$thisID];
							$gatheredComeTabIDs['comeval'.$thisID]="comeback$thisID=$value";
						}
						
						$other=false;
						
					}
				}
				else if(strlen($internal)>7)
				{
					if(substr($internal,0,7)=='comeval')
					$other=false;
				}
				if($other===true)
				$otherURI[$internal] = $value;
			}
			
			foreach($tabInfo as $internal => $value)
			{
				while(isset($takenIDs[$availableID]))
				$availableID++;
				$gatheredComeback['comeval'.$availableID]=$internal;
				$gatheredComeTabIDs['comeval'.$availableID]="comeback$availableID=$value";
				$takenIDs[$availableID]="";
			}
			foreach($gatheredComeback as $internal => $value)
				$ret.="&$internal=$value&".$gatheredComeTabIDs[$internal];
			foreach($otherURI as $internal => $value)
				$ret.="&$internal=$value";
			$ret=substr($ret,1);
			$ret="$currentURLBase/index.php?$ret";
		}
		return $ret;
	}
	
	function copyArray($theArray)
	{
		$ret = array();
		foreach($theArray as $internal => $value)
			$ret[$internal] = $value;
		return $ret;
	}
	
	function createDropDownHTML($optionArray, $id, $currentlySelected, $class)
	{
		$ret="<select name=\"$id\" id=\"$id\" class=\"$class\" >";
		$selects="";
		foreach($optionArray as $internal => $value)
		{	
			$thisID = $internal;
			$name = $value;
			$thisSelect="";
			if($thisID==$currentlySelected)
			$thisSelect="selected";
			$selects.="<option value=\"$thisID\" $thisSelect>$name</option>";
		}
		$ret.=$selects."</select>";
		
		return $ret;
	}
	
	function relativeTime($time = false, $limit = 86400, $format = 'g:i A M jS') 
	{
		if (empty($time) || (!is_string($time) && !is_numeric($time))) 
			$time = time();
		elseif (is_string($time)) 
			$time = strtotime($time);
		
		$now = time();
		$relative = '';
		if ($time === $now) 
			$relative = 'now';
		elseif ($time > $now) 
			$relative = 'in the future';
		else 
		{
			$diff = $now - $time;
			if ($diff >= $limit) 
				$relative = date($format, $time);
			elseif ($diff < 60) 
			{
				$relative = 'less than one minute ago';
			} 
			elseif (($minutes = ceil($diff/60)) < 60) 
			{
				$relative = $minutes.' minute'.(((int)$minutes === 1) ? '' : 's').' ago';
			} 
			else 
			{
				$hours = ceil($diff/3600);
				$relative = 'about '.$hours.' hour'.(((int)$hours === 1) ? '' : 's').' ago';
			}
		}
		return $relative;
	}

	function drawHTMLTableFrom2DArray($array, $uiClass, $columnHeaders = array())
	{	
		$ret="<table class=\"$uiClass\"><thead><tr>";
		
		$header=1;
		foreach($array as $internal => $value)
		{	
			if($header)
			{
				$i=0;
				foreach($value as $column => $value2)
				{
					if(!$columnHeaders[$i])
					{
						$columnHeaders[]=$column;
					}
					$ret.="<th>".$columnHeaders[$i]."</th>";
					$i++;
				}
				$ret.="</tr></thead><tbody>";
				$header=0;
			}
			$ret.="<tr>";
			foreach($value as $column => $value2)
			{
				$ret.="<td>$value2</td>";
			}
			$ret.="</tr>";
		}
		$ret.="</tbody></table>";
		return $ret;
	}
	
	function drawHTMLTableFrom2DArray2($array, $uiClass)
	{
		$columns = array();
		$count=0;
		$ret = "<table class=\"$uiClass\"><tr>";
		$emptyrow = "";
		$columnNamesUsed = array();
		foreach($array as $internal => $value)
		{
			if($count==0)
			{
				$colNum=0;
				foreach($value as $internal2 => $value2)
				{
					$intSeed=0;
					$colName = $internal2;
					if(strlen($internal2)==0)
					$colName="\$no-data-".$colNum;
					$rootName=$colName;
					while(in_array($colName,$columnNamesUsed))
					{
						$intSeed++;
						$colName=$rootName.$intSeed;
					}
					$columnNamesUsed[]=$colName;
					$columns[$colName]=$internal2;
					$ret.="<th>$internal2</th>";
					$emptyrow.="<td>$colName</td>";
					$colNum++;
				}
				$count++;
			}
		}
		$ret.="</tr>\n";
		$count=0;
		$columnNamesUsed = array();
		foreach($array as $internal => $value)
		{	
			$thisRow = $emptyrow;
			$colNum=0;
			foreach($value as $internal2 => $value2)
			{
				$intSeed=0;
				$colName = $internal2;
				if(strlen($internal2)==0)
				$colName="\$no-data-".$colNum;
				$rootName=$colName;
				while(in_array($colName,$columnNamesUsed))
				{
					$intSeed++;
					$colName=$rootName.$intSeed;
				}
				$thisRow = str_replace($colName,$value2,$thisRow);
				$colNum++;
			}
			$count++;
			$ret.="<tr>".$thisRow."</tr>\n";
		
		}
		
		$ret.="</tr></table>";
		
		return $ret;
		
	}

    function insertWWWAction($type, $ref, $misc)
    {
        global $sqlconnect;
        global $tablePrefix;
        $query = "INSERT INTO " . $tablePrefix ."wwwaction
        (type, referenced_id, misc_data)
        VALUES(?, ?, ?)";
        $vars = array($type, $ref, $misc);
        return $sqlconnect->executeQuery($query, $vars);
    }

	function createCSVFrom2DArray($array)
	{
		$ret="";
		foreach($array as $internal => $value)
		{
			foreach($value as $internal2 => $value2)
			{
				$ret.="\"$value2\",";
			}
			$ret=substr($ret, 0, -1)."\n";
		}
		return $ret;
	}
	
	function checkIsAValidDate($myDateString)
	{
    	return (bool)strtotime($myDateString);
	}

    function convertToRelativePath($folderPath)
    {
        global $rootWWW;
        $pattern = $rootWWW;
        # escape forward slashes from the pattern
        $pattern = preg_replace('/\//','\/',$pattern);
        $ret = preg_replace('/' . $pattern . '/', '', $folderPath);
        while(strcmp(substr($ret,0,1),'/') == 0) # remove any preceeding slash
        {
            $ret = substr($ret,1);
        }
        return $ret;
    }
	
?>