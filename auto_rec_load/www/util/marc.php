<?php


class marc
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
        if(isset($this->uri['getmarc']))
		{
            if(isset($this->uri['fileid']))
            {
// echo "<pre>";
                $filename = $this->fileName($this->uri['fileid'], isset($this->uri['sourcefile']) );
                header("Content-disposition: attachment; filename=\"$filename\"");
                $offset = 0;
                $records = 0;

                echo '<?xml version="1.0" encoding="UTF-8" ?><collection xmlns="http://www.loc.gov/MARC21/slim">' . "\n";

                while($data = $this->getFile($this->uri['fileid'], isset($this->uri['sourcefile']), $offset))
                {
                    $offset += count($data);
                    foreach($data as $internal => $value)
                    {
                        echo $value['record'] . "\n";
                    }
                    flush();
                }
                echo '</collection>';
// echo "</pre>";
           }
        }
	}

    function getFile($fileID, $source = false, $offset = 0, $limit = 100)
	{
        if(isset($fileID))
        {
            $query = $source ? 
            "select ais.record_raw \"record\" from ". $this->tablePrefix ."import_status ais
            where ais.file = ? order by id limit $offset, $limit "
            :
            "select ais.record_tweaked \"record\" from ". $this->tablePrefix ."import_status ais
            JOIN ". $this->tablePrefix ."output_file_track aoft ON (aoft.id=ais.out_file)
            where aoft.id = ? order by aoft.id limit $offset, $limit ";
// echo $query;
            $vars = array($fileID);
            $result = $this->sqlconnect->executeQuery($query, $vars);
            return $result;
        }
        return null;
	}

    function getTotalCount($fileID, $source = false)
    {
        if(isset($fileID))
        {
            $query = $source ? 
            "select count(*) \"count\" from ". $this->tablePrefix ."import_status ais
            where ais.file = ?"
            :
            "select count(*) \"count\" from ". $this->tablePrefix ."output_file_track aoft
            where aoft.id = ?";
            $vars = array($fileID);
            $result = $this->sqlconnect->executeQuery($query, $vars);
            if(count($result) == 1)
            {
                return $result[0]['count'];
            }
        }
        return null;
    }

    function fileName($fileID, $source = false)
    {
        if(isset($fileID))
        {
            $query = $source ? 
            "select substring_index(filename,'/',-1) \"filename\" from ". $this->tablePrefix ."file_track aft where aft.id = ?" :
            "select substring_index(filename,'/',-1) \"filename\" from ". $this->tablePrefix ."output_file_track aoft where aoft.id = ?";
            $vars = array($fileID);
// echo $query;
            $result = $this->sqlconnect->executeQuery($query, $vars);
            if(count($result) == 1)
            {
                $splitup = explode('.', $result[0]['filename']);
                if(count($splitup) > 1)
                {
                    array_pop($splitup);
                }
                $ret = implode('.', $splitup);
                $ret .='.xml';
                return $ret;
            }
        }
        return "download.xml";
    }

}