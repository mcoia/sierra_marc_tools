<?php


class dashboardUI
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
			$ret = $this->UI();
		}
		return $ret;
	}

	function UI()
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
		$ret.="<div class=\"regularBox\"><div class=\"title\">Dashboard</div>";
		$ret.="</div>";
		return $ret;
	}
	
}