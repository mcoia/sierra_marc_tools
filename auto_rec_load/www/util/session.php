<?php

function printJustHeader($iframe){
echo '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
	<html>
	<head>
	<meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	
<!-- JQUERY -->
	<script type="text/javascript" src="js/jquery.js"></script>
	
	<!-- SEARCHABLE DROPDOWN -->
	<!-- THIS PLUGIN REQUIRES THE OLDER VERSION OF JQUERY, SO WE HAVE TO LOAD IT NOW -->
	<script type="text/javascript" src="js/jquery.searchabledropdown-v1.0.8/jquery.searchabledropdown-1.0.8.min.js"></script>	
	<!-- NOW NOCONFLICT TO LOAD THE NEWER VERSION OF JQUERY -->
	<script type="text/javascript">var jQuery_1_7_1 = $.noConflict(true); </script>
	
	<!-- NEWER VERSION SO JQUERY FOR THE REST OF THE CODE -->
	<script type="text/javascript" src="js/jquery-1.11.3.min.js"></script>	
	<script type="text/javascript" src="css/jquery-ui-1.11.4.custom/jquery-ui.min.js"></script>
	
<script type="text/javascript">
	console.log(jQuery_1_7_1.fn.jquery);
	console.log($.fn.jquery);
</script>

<!-- STYLES -->	
	<!-- CUSTOM STYLES -->
	<link href="css/thickbox.css" rel="stylesheet" type="text/css">
	<link href="css/style.css"    rel="stylesheet" type="text/css" media="screen">
	
	<!-- DATEPICKER DEPRICATED WITH THE NEWER VERSION OF JQUERY-UI -->
	<!-- <link href="css/jquery.datepick.css" rel="stylesheet" type="text/css" media="screen"> -->	 
		
	<!-- DATATABLES -->
	<link type="text/css" rel="stylesheet" href="js/DataTables-1.10.7/media/css/jquery.dataTables_themeroller.css">
	
	<!-- <link type="text/css" rel="stylesheet" href="js/DataTables-1.10.7/media/css/jquery.dataTables.min.css"> -->
	
	
	<!-- JQUERY UI -->
	<!-- <link type="text/css" rel="stylesheet" href="css/jquery-ui-1.8.17.custom/css/custom-theme/jquery-ui-1.8.17.custom.css"> -->
	<link type="text/css" rel="stylesheet" href="css/jquery-ui-1.11.4.custom/jquery-ui.min.css">	
	
	<!-- JSTREE -->
	<link rel="stylesheet" href="js/jstree/themes/default/style.min.css" />
	
	<!-- Hamburger Menu Icons -->
	<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
	
	
<!-- SCRIPTS -->

	<!-- DATEPICKER DEPRICATED WITH THE NEWER VERSION OF JQUERY-UI -->
	<!-- <script type="text/javascript" src="js/datepicker/jquery.datepick.min.js"></script> -->
	
	<!-- DATATABLES -->
	<script type="text/javascript" charset="utf8" src="js/DataTables-1.10.7/media/js/jquery.dataTables.min.js"></script>
	
	<!-- LIVEQUERY  -->
	<script type="text/javascript" src="js/jquery.livequery.min.js"></script>
	
	
	<!-- JSTREE -->
	<script type="text/javascript" src="js/jstree/jstree.min.js"></script>
	
	<!--  CUSTOM  -->
	<script type="text/javascript" src="js/validate.js"></script>
	<script type="text/javascript" src="js/datepicker.js"></script>
	<script type="text/javascript" src="js/tabs.js"></script>
	<script type="text/javascript" src="js/search-table.js"></script>
	<script type="text/javascript" src="js/searchable-dropdown.js"></script>
	
	<title>MOBIUS Automated Record loads</title>
	
	</head>
	<body';

	if($iframe===true)
		echo ' id="iframebody"';
		
	echo '>';
}

function printHead()
{
	printJustHeader(false);
	echo '<div id="container">';
    echo'<div id="topbar">
			<div id="titlehead">MOBIUS Automated Record Loads</div>';
    echo printUserBar();
    echo'</div><!--  End Topbar -->';
    printNav();
    echo'<div id="content">';
}

function printFoot(){
	
echo '</div><!--  End content -->
</div>   <!--  End Container -->';
printJustEnder();


}

function printJustEnder()
{
	global $uri;
	global $uriString;
	if(isset($uri['pageid']))
	{	
		echo createHTMLTextBox("thisPageID","",15,"nodisplay",false,$uri['pageid'],false,"",false,"hidden");
		echo createHTMLTextBox("thisURI","",15,"nodisplay",false,$uriString,false,"",false,"hidden");
	}
		$addJS="";
		foreach($uri as $internal => $value)
		{	
			if(strlen($internal)>8)
			{
				if(substr($internal,0,8)=='comeback')
				{
					$thisID = str_replace('comeback',"",$internal);
					$thisTabControl = $uri['comeval'.$thisID];
					$thisTabID = $value;
					$addJS.='
					$("#'.$thisTabControl.'").tabs("option","active",'.$thisTabID.');';	
				}
			}
		}
		if(strlen($addJS)>0)
		{
			echo '
				<script type="text/javascript">
				function selectTab()
				{
					'.$addJS.'			
				}
				
				</script>
				';
		}
	echo '</body></html>';
}

function printWelcome()
{
	global $currentUser;
	echo'<div class="regularBox textAlignCenterBox"><div class="title">Welcome ';
	$userStuff = $currentUser->getUserArray();
	echo $userStuff["first_name"]." ".$userStuff["last_name"];
	echo'</div><br /><br />
	<h1>Automated Record Loads!</h1><br /><br />
	<br /><br />
	<h2>Please choose a task from the menu</h2>
	</div>
	';
}

function printNav()
{
	global $currentUser;
	global $uri;
	global $sqlconnect;
    global $tablePrefix;

	if(isset($currentUser) && get_class($currentUser)!==false && get_class($currentUser)=='user')
	{
		$printThis = '';
        $printThis.="<a href='javascript:void(0);' id='navBarIcon' onclick='navBarPop()'> <i class='fa fa-bars'></i></a><div id='navbar'>";

        $query="SELECT id,name FROM " . $tablePrefix ."wwwpages";
        $vars = array();
        $result = $sqlconnect->executeQuery($query, array());

        $lis = "";
        foreach($result as $internal => $row)
        {
            $thisPageID = $row["id"];
            if(strlen($thisPageID)>0)
            {
                $pageName = $row["name"];
                $lis.='<li><a href="index.php?pageid='.$thisPageID.'"';
                if(isset($uri["pageid"]) && $uri["pageid"]==$thisPageID)
                $lis.=" class=\"selected\"";
                $lis.='>'.$pageName.'</a></li>';
            }
        }
        if(strlen($lis)>0)
        {	
            $printThis.="<ul>$lis</ul>";
        }

        $printThis.="</div><!--  End Nav Bar -->";	

        echo $printThis;
	}
}

function printUserBar()
{
	global $currentUser;
	global $uri;
	global $url;
	if(isset($currentUser) && get_class($currentUser)!==false && get_class($currentUser)=='user')
	{
		$usera = $currentUser->getUserArray();
		$name = $usera["first_name"];
		$id = $currentUser->getUserID();
		$separater = (strpos($url,"?")!==false)?"&":"?";
		$unimpersonateLink="";
		if(isset($_SESSION["impUser"]))
		{
			$unimpersonateLink = ' |  <a href="'.$url.$separater.'unimpersonate=1">Unimpersonate</a>';
		}
		addDebug("Count URI = ".count($uri));
		
		echo'<div id="userinfobar"><span id="userwelcometext">Welcome, '.$name.$unimpersonateLink.' |  <a href="'.$url.$separater.'logout=1">Logout</a></span></div>';
	}
}
?>