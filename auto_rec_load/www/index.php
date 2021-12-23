<?php

date_default_timezone_set('America/Chicago');
global $debug;

require_once ("util/global.php");

# $debug = false;
$debug = true;
global $uri;
global $sqlconnect;

if(isset($uri["logout"]))
{	
	printHead();
	global $currentUser;
	$tracking = new tracking(null,null,"Logged Out",null,null,null,null,null);
	$tracking->write();
	
	unset($currentUser);
	unset($_SESSION["currentUser"]);
	session_unset();
	echo "<span class=\"submiterror\">Logging Out<br /><br />....</span>";
	redirectTo("index.php");
}
else if(isset($uri["getdata"]))
{
	if(allowedHere())
	{	
		if(isset($uri['iframe']))	
			printJustHeader(true);
		
		$decideUI = decideUI(); 
		if(isset($decideUI))
		echo $decideUI->go();
		
		if(isset($uri['iframe']))
			printJustEnder();
	}
}
else if(isset($uri["getgraph"]))
{
	if(allowedHere())
	{	
		require_once ("util/graph.php");
		$graph = new graphit(); 
		$graph->getGraph();
	}
}
else if(isset($uri["getjson"]))
{
	if(allowedHere())
	{	
		$decideUI = decideUI();
		if(isset($decideUI))
		{
			header('Content-type: application/json');
			echo $decideUI->go();
		}
	}
}
else
{	
	printHead();
	
    if(allowedHere())
    {
        if(isset($uri["unimpersonate"]))
        {
            $login = new login();
            echo $login->unimpersonate();
        }
        
        $decideUI = decideUI();
        if(isset($decideUI))
        {
            echo $decideUI->go();
        }
        else
        {
            printWelcome();
        }
    }
    else
    {
        printWelcome();
    }

	if($debug)
	{	
		echo "<div class=\"debugWindow\">";
		foreach($debugOutput as $internal => $value)
		echo $value."<br />";
		echo "<hr />";
		foreach($_SESSION as $internal => $value)
		echo "$internal <br />";
		echo "</div> <!-- END Debug Windows -->";
	}
	global $currentUser;
	if(isset($currentUser))
	{
		$seeTracking = $currentUser->getPrivileges()->findID("tracking");
		if($seeTracking!==false)
		{
			echo "<div class=\"trackingWindow\"><div class=\"titlesmaller\">Recent Activity</div><div id=\"trackingDIV\">";
			$tracking = new trackingUI();
			echo $tracking->getRecentActivity()."</div>";
			echo "</div> <!-- END tracking -->";
		}
	}
	printFoot();
}

$sqlconnect->close();
?>