<?php
class sqlconnect{
	var $link;
	var $mysqli;


	function __construct()
	{
		$this->selectCorrectDatabase();
	}

	function updateDataVars($dataFields,$whereClause,$update,$table)
	{
		$quoteMarks=false;

		foreach($dataFields as $inside => $value)
		if((strpos($dataFields[$inside],"\"")!=false)||(strpos($dataFields[$inside],"'")!=false))
		$quoteMarks=true;
		if($quoteMarks===false)
		{
			if($update===false)
			{
				$query = "INSERT INTO ".$table." (";
				foreach($dataFields as $inside => $value)
				$query=$query.$inside.",";
				$query = trim($query,',');
				$query=$query.") VALUES(";
				foreach($dataFields as $inside => $value)
				{
					$string="";
					if(!is_numeric($value))
					$string="\"";
					if(!is_null($value))
					$query=$query.$string.$value."$string,";
					else
					$query=$query."null,";
				}
				$query = trim($query,',');
				$query=$query.")";
			}
			else
			{
				$query = "UPDATE $table SET ";
				foreach($dataFields as $inside => $value)
				{
					if(!is_null($value))
						$query=$query.$inside."=\"".$value."\",";
					else
						$query=$query.$inside."=null,";
				}
				$query = trim($query,",");
				$query=$query." ".$whereClause;
			}

			//echo "<div id=\"nowrap\">",str_ireplace(",","<br />,",$query),"</div>";
			
			if($this->link)
			$result=mysql_query($query,$this->link);

			else echo 'unable to connect or something';			
		}
		else
		$result="Quotation and tick marks are not allowed";
			
		return $result;
	}

	function paramaterizedUpdate($dataValues, $databaseDefinitions, $whereClause, $table, $update)
	{
		$ret=false;
		if($update)
		{
			$query = "UPDATE $table SET ";
			$outputQ = "UPDATE $table SET ";
			$vars = array();
			foreach($dataValues as $internal => $value)
			{
				if($databaseDefinitions[$internal]->getType()=='date')
				{
					if(isset($value))
						$vars[]=strlen($value)==0?null: convertToDatabaseDate($value);
					else
						$vars[]=null;
				}
				else
					$vars[]=$value;

				$query.="$internal = ? ,";
				$outputQ.="$internal = '$value' ,";
			}
			$query = substr($query,0,strlen($query)-1);
			$outputQ=substr($outputQ,0,strlen($outputQ)-1);
			$query.=" $whereClause";
			$outputQ.=" $whereClause";
			#addDebug($outputQ);
			#foreach($vars as $internals => $v)
			#addDebug("$internals = $v");
		}
		else
		{
			$query = "INSERT INTO $table(";
			$vars = array();
			$questions = "";
			foreach($dataValues as $internal => $value)
			{
				if($databaseDefinitions[$internal]->getType()=='date')
				{
					if(isset($value))
						$vars[]=strlen($value)==0?null: convertToDatabaseDate($value);
					else
						$vars[]=null;
				}
				else
					$vars[]=$value;

				
				$query.="$internal,";
				$questions.="?,";
				
			}
			$query = substr($query,0,strlen($query)-1);
			$questions= substr($questions,0,strlen($questions)-1);
			$query.=") VALUES($questions)";
			$query.=" $whereClause";
			#addDebug($query);
			#foreach($vars as $internals => $v)
			#addDebug("$internals = $v");
			
		}
		
		$ret = $this->executeQuery($query,$vars);
		return $ret;
	}

	function executeQuery( $query, $params )
	{

		$ret=false;
		
		if( $this->mysqli->connect_error ) {
			echo $this->mysqli->connect_error, '<br />';
			$this->mysqli = false;
			return false;
		}
		if( $stmt = $this->mysqli->prepare( $query ))
		{
			# Bind the incoming parameters
			if( count( $params ) > 0 )
			{
				$binding = '$stmt->bind_param( "';
				for( $i = 0; $i < count( $params ); $i++ )
				{
					$paramtype = gettype( $params[ $i ] );
					if( $paramtype == 'integer' ) $paramtype = 'i';
					else $paramtype = 's';
					$binding .= $paramtype;
				}
				$binding .= '", ';
				for( $i = 0; $i < count( $params ); $i++ )
				{
					if( $i > 0 ) $binding .= ', ';
					$binding .= '$params[' . $i . ']';
					//echo "p$i: " . $params[ $i ] . "(" . ( gettype( $params[ $i ] ) == 'integer' ? 'i' : 's' ) . ")<br />\n";
				}
				$binding .= ' );';

				//echo $binding, "<br />$query<br />\n";
				eval( $binding );
			}

			if( strpos( strtoupper( $query ), 'SELECT' ) !== false )
			{
				if( $stmt->execute())
				{
					$ret=array();
					$i=0;
					while($rows = $this->fetchArray($stmt))
					{
						foreach($rows as $internal => $value)
						$ret[$i][$internal]=$value;
						$i++;
					}
				}
				else
				{
					echo 'Execute Error: ', $stmt->errno, ': ', $stmt->error, '<br />', "\n";
					$stmt->close();
				}
			}
			else
			{	// Non-Query
				$output = $stmt->execute();
				if($output===true)
					$ret=true;
				else
					$ret=$output;
		
			}
			$stmt->close();
		}
		else
		echo 'Prepare Error: ', $this->mysqli->error, '<br />'."\n$query<br />";
		
		return $ret;
	}

	private function fetchArray ($stmt) {
		$data = $stmt->result_metadata();
		$fields = array();
		$out = array();

		$fields[0] = &$stmt;
		$count = 1;

		while($field = mysqli_fetch_field($data)) {
			$fields[$count] = &$out[$field->name];
			$count++;
		}

		call_user_func_array('mysqli_stmt_bind_result', $fields);
		if( $stmt->fetch() )
		return (count($out) == 0) ? false : $out;
		return false;
	}
	
	function selectCorrectDatabase()
	{
        $config = array();
        $configFile = file_get_contents('auto_rec_load.conf');
        $lines = explode("\n", $configFile);
        foreach($lines as $line)
        {
            $line = trim($line);
            if(strcmp(substr($line,0,1),"#") != 0) # Make sure it's not a commented line
            {
                if(strstr($line, "="))
                {
                    $con = explode("=", $line);
                    $key = array_shift($con);
                    $key = trim($key);
                    $therest = implode("=", $con);
                    $therest = trim($therest);
                    $config[$key] = $therest;
                }
            }
        }
        $needed = array("dbhost", "db", "dbuser", "dbpass", "port");
        $missing = array();
        foreach($needed as $key)
        {
            if(!$config[$key])
            {
                array_push($missing, $key);
            }
        }
        if( isset($missing[0]) )
        {
            echo "Configuration error, missing:<br >";
            foreach($missing as $key)
            {
                echo "$key <br />";
            }
            exit;
        }

        $this->mysqli = new mysqli($config["dbhost"], $config["dbuser"], $config["dbpass"], $config["db"] );

		return $this->mysqli;
	}
	
	function close()
	{
		$this->mysqli->close();
	}

}
function stripQuotes($var)
{
	$ret=str_ireplace("\"","",$var);
	$ret=str_ireplace("'","",$ret);
	return $ret;
}

function toDataBaseTime($rawTime)
{
	$ret="";
	if(strlen($rawTime)==0)
	$ret=date("Y-m-d H:i:s");
	else
	$ret = date("Y-m-d H:i:s",$rawTime);
	return $ret;
}

?>