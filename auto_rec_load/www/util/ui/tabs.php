<?php

class tabUI
{
	private $tabID;
	private $title;
	private $content;
	
	function __construct($tabID, $title, $content)
	{
		$this->tabID = $tabID;
		$this->title = $title;
		$this->content = $content;
	}
	
	function getContent()
	{
		return $this->content;
	}
	
	function getID()
	{
		return $this->tabID;
	}
	
	function getTitle()	
	{
		return $this->title;
	} 
}

class tabsUI
{
	
	private $tabArray;
	private $tabPageID;
	
	function __construct($tabArray, $tabPageID)
	{
		$this->tabArray = $tabArray;
		$this->tabPageID = $tabPageID;
	}
	
	function getTabHTML()
	{
		$ret="";
		if(count($this->tabArray)>0)
		{
			addDebug("more than 0 tab");
			$ret.='<div id="'.$this->tabPageID.'" class="tabui" >';//class="tabui">
			$ret.='<ul>';
			
			foreach($this->tabArray as $internal => $value)
				$ret.='<li><a href="#'.$value->getID().'">'.$value->getTitle().'</a></li>';
			
			$ret.='</ul>';
			
			foreach($this->tabArray as $internal => $value)
			{
				$ret.='<div id="'.$value->getID().'">'.$value->getContent().'</div> <!-- END '.$value->getID().'--> ';
			}
				
			$ret.='</div>  <!-- END '.$this->tabPageID.' -->';
			
		}
		return $ret;
		
	}
}