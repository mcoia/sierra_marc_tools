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
		$ret = "";
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

		$ret.="
        <script type=\"text/javascript\" src=\"js/vendors.js\"></script>
        <div class='regularBox'>
        <div class='vendor_container'>
            <div id='vendor_datatable' class='vendor_child'>
            <div class='loader'></div>
            </div> <!-- vendor_datatable -->

        </div> <!-- vendor_container -->
        </div><!-- regularBox -->

        <div class='regularBox'>
        <a id='screenshotanchor'></a>
        <div id='screenshotload'>

        </div><!-- screenshotload -->
        </div><!-- regularBox -->";
		return $ret;
	}

    function getSearchTable($searchstring = null)
	{
		addDebug("getSearchTable called");
		$anchorProps = array();
		$selectCols = array(
        "CASE WHEN asource.enabled IS TRUE THEN 'Enabled' ELSE 'Disabled' END \"enabled\"",
        "asource.name \"vname\"",
        "cluster.name \"cname\"",
        "ac.name \"clientname\"",
        "CASE WHEN asource.type = 'web' THEN
        concat('<a source=\"',asource.id,'\" onClick=\"showScreenShots(this)\" href=\"#screenshotanchor\">', asource.type, '</a>')
        ELSE asource.type
        END \"type\"",
        "asource.perl_mod \"perlmod\"",
        "asource.marc_editor_function \"marcfunction\"",
        "asource.last_scraped \"last_scraped\"",
        "concat('<a  json =\"1\" source=\"',asource.id,'\" onClick=\"editJSONClick(this)\" href=\"#\">', asource.json_connection_detail, '</a>') \"conndetail\"");
		$showCols = array("enabled"=>"Enabled","cname"=>"Cluster","vname"=>"Vendor","clientname"=>"Institution","type"=>"Type","perlmod"=>"Perl Mod","marcfunction"=>"MARC Editor","last_scraped"=>"Last Scraped","conndetail"=>"Connection Detail");
		$ClickPos=array();
		$searchCols = array();
		$tableID = "vendorSearchTable";
		$uriValClick = array();
		$additionalURI = array();
		$extraWhereClause = "";
        $table = "
        " . $this->tablePrefix ."source asource
        JOIN " . $this->tablePrefix ."client ac ON (asource.client=ac.id)
        JOIN " . $this->tablePrefix ."cluster cluster ON (cluster.id=ac.cluster)";

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

    function getScreenShotImages($sourceID)
    {
        $vars = array();
        $ret = array();
        $allowedExt = array("png","jpg","jpeg");
        $imagesFolder = "";
        $query = "
        select scrape_img_folder
        from
        ". $this->tablePrefix ."source source
        where
        source.id=?";
        $vars[] = $sourceID;
        $result = $this->sqlconnect->executeQuery($query,$vars);
        if(count($result) == 1)
        {
            $imagesFolder = $result[0]["scrape_img_folder"];
        }
        else
        {
            $ret["status"] = "error";
            $ret["statuscode"] = "Source folder not configured";
            return json_encode($ret);
        }
        if(is_dir($imagesFolder))
        {
            $ret["trace"] = array();
            $images = scandir($imagesFolder);
            $sortImageNameArray = array();
            foreach($images as $internal => $filename)
            {
                $full = $imagesFolder . "/" . $filename;
                $add = 0;
                if(is_file($full))
                {
                    $ret["trace"][] = $full;
                    foreach($allowedExt as $int => $ext)
                    {
                        $ext = strtolower($ext);
                        $len = strlen($ext);
                        $len = $len * -1;
                        $fileExt = substr( $filename,strlen($filename) + $len );
                        $fileExt = strtolower($fileExt);
                        if(strcmp($ext, $fileExt) ==0)
                        {
                            $add = 1;
                            $ret["trace"][] = $fileExt;
                        }
                    }
                    $ret["trace"][] = $add;
                }
                if($add)
                {
                    if(!isset($ret["images"]))
                    {
                        $ret["images"] = array();
                    }
                    if(!isset($ret["images_name"]))
                    {
                        $ret["images"] = array();
                    }
                    $ret["trace"][] = $full;
                    $ret["images"][] = convertToRelativePath($full);
                    $ret["images_name"][] = $this->parseImageName($filename);
                    $sortImageNameArray[] = $this->getImageNumeric($filename);
                }
            }
            if($ret["images"])
            {
                $i = 0;
                # print_r($sortImageNameArray);
                while( $i < (count($sortImageNameArray) - 1) )
                {
                    if($i < 0)
                    {
                        $i = 0;
                    }
                    # print "Comparing: " . $sortImageNameArray[$i] . " to: " . $sortImageNameArray[$i+1] ."<Br/>";
                    if( ($sortImageNameArray[$i]+0) > ($sortImageNameArray[$i+1]+0))
                    {
                        $temp = $sortImageNameArray[$i];
                        $sortImageNameArray[$i] = $sortImageNameArray[$i+1];
                        $sortImageNameArray[$i+1] = $temp;

                        $temp = $ret["images"][$i];
                        $ret["images"][$i] = $ret["images"][$i+1];;
                        $ret["images"][$i+1] = $temp;

                        $temp = $ret["images_name"][$i];
                        $ret["images_name"][$i] = $ret["images_name"][$i+1];
                        $ret["images_name"][$i+1] = $temp;
                        $i-=2;
                    }
                    $i++;
                }
                # print_r($sortImageNameArray);
                $ret["status"] = "success";
                $ret["statuscode"] = "Found images";
            }
            else
            {
                $ret["status"] = "error";
                $ret["statuscode"] = "No images found";
            }
        }
        else
        {
            $ret["status"] = "error";
            $ret["statuscode"] = "Folder: $imagesFolder does not exist";
        }
        return json_encode($ret);
    }

    function updateJSONDetails($sourceID, $json)
    {
        $ret = "";
        $query = "update " . $this->tablePrefix ."source asource " .
        "set json_connection_detail = ? where id = ?";
        $vars = array($json, $sourceID);
		return $this->sqlconnect->executeQuery($query, $vars);

# Leaving this code in here for troubleshooting if needs be
        $ret .= $query;
        foreach($vars as $internal => $value)
        {
            $ret .= "$value\n";
        }
        $ret .= "<pre>$json</pre>";
        return $ret;
    }

    function getImageNumeric($filename) # this routine finds the first occurance of a number, and assumes that the the image sequence ID number
    {
        $split = explode("_",$filename);
        foreach($split as $internal => $value)
        {
            $match = array();
            if(preg_match('/^\d+$/', $value, $match))
            {
                return $match[0]+0;
            }
        }
        return "0";
    }

    function parseImageName($filename)
    {
        $split = explode("_",$filename);
        array_shift($split);
        array_shift($split);
        $split = explode(".",implode("_", $split));
        array_pop($split);
        return implode(".", $split);
    }

}