<?php

date_default_timezone_set('America/Chicago');
global $debug;

require_once ("util/global.php");

$debug = false;
// $debug = true;
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
        $decideUI = decideUI();
		if(isset($decideUI))
		{
            require_once ("util/graph/src/jpgraph.php");
            require_once ('util/graph/src/jpgraph_bar.php');
            require_once ('util/graph/src/jpgraph_pie.php');
			$decideUI->go();
		}
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
else if(isset($uri["getmarc"]))
{
	if(allowedHere())
	{	
		$marc = new marc();
        header('Content-type: application/xml');
        header('Content-Type: application/octet-stream');
        $marc->go();
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

	printFoot();
}

$sqlconnect->close();
?>