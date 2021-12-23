<?php

class dbField
{
	private $id;
	private $maxwidth;
	private $type;
	private $table;
	private $friendlyName;
	private $required;
	private $extraHTML;
	
	function __construct($id, $maxwidth, $type, $table, $friendlyName, $required, $extraHTML)
	{
		$this->id = $id;
		$this->maxwidth = $maxwidth;
		$this->type = $type;
		$this->table = $table;
		$this->friendlyName = $friendlyName;
		$this->required = $required;
		$this->extraHTML = $extraHTML;
	}
	
	function getID()
	{
		return $this->id;
	}
	
	function getType()
	{
		return $this->type;
	}
	
	function getTableName()
	{
		return $this->table;
	}
	
	function getFriendlyName()
	{
		return $this->friendlyName;
	}
	
	function getMaxWidth()
	{
		return $this->maxwidth;
	}
	
	function getRequired()
	{
		return $this->required;
	}
	
	function getExtraHTML()
	{
		return $this->extraHTML;
	}
}