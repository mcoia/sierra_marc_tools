<?php

class user
{	
	private $userID=-1;
	private $userTraits;
	private $privileges;
	private $sqlconnect;
	private $fields = array();

	function __construct($userID)
	{
		global $sqlconnect;
        global $tablePrefix;

		addDebug("Creating User... $userID");

		$this->sqlconnect = $sqlconnect;
        $this->tablePrefix = $tablePrefix;

		//$id, $maxwidth, $type, $table, $friendlyName)
		$this->fields["first_name"]=new dbField("first_name",50,"text",$this->tablePrefix . 'wwwusers',"First Name",false,"");
		$this->fields["last_name"]=new dbField("last_name",50,"text",$this->tablePrefix . 'wwwusers',"Last Name",false,"");
		$this->fields["username"]=new dbField("username",15,"text",$this->tablePrefix . 'wwwusers',"Login User ID",true,"");
		$this->fields["phone1"]=new dbField("phone1",15,"text",$this->tablePrefix . 'wwwusers',"Phone Number 1",false,"");
		$this->fields["phone2"]=new dbField("phone2",15,"text",$this->tablePrefix . 'wwwusers',"Phone Number 2",false,"");
		$this->fields["address1"]=new dbField("address1",50,"text",$this->tablePrefix . 'wwwusers',"Address 1",false,"");
		$this->fields["address2"]=new dbField("address2",50,"text",$this->tablePrefix . 'wwwusers',"Address 2",false,"");
		$this->fields["email_address"]=new dbField("address2",300,"text",$this->tablePrefix . 'wwwusers',"Email Address",false,"");
		$this->userID=$userID;
		if(isset($userID) && $userID!=-1)
        {
            $this->fillVars();
        }
	}

	function getUserID()
	{
		return $this->userID;
	}

	function getUserArray()
	{
		if($this->userID>-1)
        {
            return $this->userTraits;
        }
		else
        {
            return false;
        }
	}
	
	function getFields()
	{	
		return $this->fields;
	}
	
	function getPrivileges()
	{
		if($this->userID>-1)
		return $this->privileges;
		else
		return false;
	}
	
	function fillVars()
	{
		
		$this->userTraits = array();
		$this->privileges = array();
		$query="SELECT ";
		foreach($this->fields as $internal => $value)
		$query.=$internal.",";
		$query=substr($query,0,strlen($query)-1);
		$query.=" FROM " . $this->tablePrefix ."wwwusers WHERE ID=?";
		$vars = array();
		$vars[]=$this->userID;
		$result = $this->sqlconnect->executeQuery($query,$vars);
		if(count($result)==1)
		{
			foreach($result as $internal => $row)
			{
				foreach($row as $internal2 => $col)
				{
					$this->userTraits[$internal2] = $this->fields[$internal2]->getType()=='date'?convertFromDatabaseDate($col) : $col;
				}
			}
		}
	}

	function checkUserExists($userName,$emailAddress,$userIDExclude)
	{
		$emailAddress = strtoupper($emailAddress);
		$userName=strtoupper($userName);
		$query = "SELECT id,EMAIL_ADDRESS,USERNAME FROM " . $this->tablePrefix ."wwwusers WHERE (UPPER(EMAIL_ADDRESS)=? OR UPPER(USERNAME)=?)";
		$vars = array($emailAddress,$userName);
		if($userIDExclude!=null)
		{
			$query.=" AND id!=?";
			$vars[]=$userIDExclude;
		}
		$result = $this->sqlconnect->executeQuery($query,$vars);
		if(count($result)!=0)
		{
			addDebug($query);
			addDebug("found user");
			return true;
		}
		else
		return false;
	}
	
	function updateUser($fields)
	{
		$ret=false;
		$valid = $this->validate($fields);
		
		if($valid===true)
		{
			$ret = $this->sqlconnect->paramaterizedUpdate($fields, $this->fields, "WHERE id=".$this->userID, $this->tablePrefix . "wwwusers", true);
			if($ret===true)
			$this->fillVars();
		}
		else
		$ret=$valid;
		
		return $ret;
		
	}
	
	function validate($fields)
	{
		$ret=false;
		if($this->userID>-1)
		{
			if(isset($fields["USERNAME"]))
			{
				$email = "";
				if(isset($fields["EMAIL_ADDRESS"]))
				$email = $fields["EMAIL_ADDRESS"];
				$conflict = $this->checkUserExists($fields["USERNAME"],$email,$this->userID);
				if($conflict===false)
				{
					foreach($fields as $internal => $value)
					{
						if(isset($this->fields[$internal]))
						{
							if(($this->fields[$internal]->getRequired()) && (strlen($value)==0))
							$ret.=$this->fields[$internal]->getFriendlyName()." is required";
						}
						else $ret.="Invalid Field".$internal;
					}
					
				}
				else
				$ret.="Login User ID or email address already exists";
			}
		}
		addDebug("ret  = $ret");
		if($ret===false)
		{
			addDebug("Totally Valid Post Variables");
			$ret=true;
		}
		return $ret;
	}
	
	function createNewUser($firstName, $lastName, $emailAddress, $userName, $start_date)
	{
		$ret="";
		$vals = array("First Name"=>$firstName,
		"Last Name"=>$lastName,
		"Email Address"=>$emailAddress,
		"User ID"=>$userName);
		foreach($vals as $internal => $value)		
		if(strlen($value)==0)
		$ret.="Please Provide $internal<Br />";
		
		if(strlen($ret)==0)
		{
			if(!$this->checkUserExists($userName,$emailAddress,null))
			{
				$start_date = convertToDatabaseDate($start_date);
				$query="INSERT INTO " . $this->tablePrefix ."wwwusers(USERNAME,PASSWORD,FIRST_NAME,LAST_NAME,EMAIL_ADDRESS,START_DATE) VALUES(?,MD5(?),?,?,?,?)";
				$pass = generateRandomString(8);
				$vars = array($userName,$pass,$firstName,$lastName,$emailAddress,$start_date);
				addDebug($query);
				foreach($vars as $internal =>$value)
				addDebug($value);
				$result = $this->sqlconnect->executeQuery($query,$vars);
				if($result===true)
				{
					$query="SELECT MAX(id) AS \"id\" FROM " . $this->tablePrefix ."wwwusers";
					$vars = array();
					$result = $this->sqlconnect->executeQuery($query,$vars);
					foreach($result as $internal => $value)
					$ret=$value["id"];
				}
				else
				$ret="Could Not Create User";
			}
			else 
				$ret="Username or Email Already Exists";
		}
		
		return $ret;
	}
	
	function changePassword($newPassword)
	{
		$ret=true;
		if(isset($newPassword) && strlen($newPassword)>5)
		{
			$query="UPDATE " . $this->tablePrefix ."wwwusers SET PASSWORD = MD5(?) WHERE id=?";
			$vars = array($newPassword,$this->userID);
			$ret = $this->sqlconnect->executeQuery($query,$vars);
		}
		else
		$ret="Invalid Password - make sure it's at least 5 characters";
		
		return $ret;
		
	}
	
	function createRandomPassword()
	{
		$ret="";
		$uppercase = array("A","B","C","D","E","F","G","H","J","K","M","N","P","Q","R","S","T","W","X","Y","Z");
		$lowercase = array();
		$someCharacters = array("?",">","!","#",")","-");
		
		foreach($uppercase as $internal => $value)
			$lowercase[]=strtolower($value);
		$allarrays = array($uppercase,$lowercase,$someCharacters);
		addDebug("allarrays count: " . count($allarrays));
		for($i=0;$i<8;$i++)
		{
			$rand_keys = array_rand($allarrays);
			$rand_keys2 = array_rand($allarrays[$rand_keys]);
			addDebug("First random: ". $rand_keys);
			addDebug("second random: ". $rand_keys2);
			$ret.=$allarrays[$rand_keys][$rand_keys2];
		}
		addDebug("generated new password: $ret");
		return $ret;		
	}

}

class userUI
{
	private $sqlconnect;
	private $uri;
	private $url;
	private $currentUser;
	private $currentURLBase;
	private $user;
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
		if(isset($this->uri['userid']) && $this->uri['userid']>0)
			$this->user = new user($this->uri['userid']);
	}
	
	function go()
	{			
		$ret="";
		if(isset($this->uri['userform']))
			$ret = $this->getCreateUserForm(null);
		
		else if(isset($this->uri['getresults']))
			$ret = $this->getUserSearchResultsTable();	
			
		else if(isset($this->uri['list']))
			$ret = $this->getUserListForm();
			
		else if(isset($this->uri['getwagesummary']))
			$ret = $this->getUserWageDetails($this->user);
			
		else if(isset($this->uri['impersonate']))
			$ret = $this->impersonate($this->uri['impersonate']);
		else if(isset($this->uri['getdata']))
		{
			if(isset($this->uri['getdebtsummary']))
			{	
				if(isset($this->uri["debtid"]))
				{
					$userDebtUI = new userdebtui($this->user);
					$debtID = $this->uri["debtid"];
					$ret = $userDebtUI->getSingleDebtSummary($debtID, false);
				}
			}
			else if(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1 )
			{
				$this->getUserSearchResultsTable($this->uri['searchstring']);
				exit();
			}
		}
		else if(isset($this->uri['getjson']))
		{
			if(isset($this->uri['hourseq']) && isset($this->uri['dom']) && isset($this->uri['val']))
			{
				$ret = $this->updateHours($this->uri['hourseq'],$this->uri['dom'],$this->uri['val']);
			}
			else if(isset($this->uri['updateDebt']) && isset($this->uri['newval']) && isset($this->uri['seqid']) && isset($this->uri['dom']))
			{
				$test = 0;
				if(preg_match('/Date/',$this->uri['dom']))
				{
					if(preg_match('/\d\d\-\d\d\-\d\d\d\d/',$this->uri['newval']))
						$test = 1;
				}
				else
					$test = 1;
				if($test)
				{
					$ret = $this->updateUserDebt($this->uri['seqid'], $this->uri['dom'], $this->uri['newval']);
				}
				else
					$ret = array("worked"=>0);
			}
			$ret = json_encode($ret);
		}
		else
			$ret = $this->userEditUI();
			
		return $ret;
	}
	
	function impersonate($impersonateID)
	{
		$ret="";
		$login = new login();
		if($login->impersonate($impersonateID) === true)
		{
			$ret = redirectTo("index.php");
		}
		else
			$ret = $this->userEditUI();
		return $ret;
	}
	
	function userEditUI()
	{	
		
		$ret="";
		
		//$userSearch = "<div id=\"resizeiframe\" class=\"ui-resizable searchdivframe\"><iframe id=\"usersearchframe\" src=\"$this->currentURLBase/index.php?pageid=".$this->uri['pageid']."&list=1&getdata=1&iframe=1\"></iframe></div>";
		$userSearch = "<div class=\"regularBox\"><div class=\"title\">Search Employees</div>".$this->getUserListForm()."</div>";
		$userEdit="";
		$userName="";
		
		$tabArray = array();
		if(isset($this->user))
		{	
			$userStuff = $this->user->getUserArray();
			$userName = $userStuff['FIRST_NAME']." ".$userStuff['LAST_NAME'];
			$tabArray[] = new tabUI("editUserTab",$userName,$this->getUserEditForm($this->user,array("employeeTab"=>count($tabArray))));
		}
		$ret.="<div class=\"regularBox\"><div class=\"title\">Employees</div>";
		
		$tabArray[] = new tabUI("searchUserTab","Search Employees",$userSearch);
		if($this->currentUser->getPrivileges()->findID("createnewemps")!==false)
		$tabArray[] = new tabUI("createNewUserTab","Create New Employee",$this->getCreateUserForm(array("employeeTab"=>count($tabArray))));
		
		$userDebtUI = new userDebtUI($this->user);
		$tabArray[] = new tabUI("createNewDebtTab","Debt Types",$userDebtUI->getGlobalDebtChangeForms(array("employeeTab"=>count($tabArray))));
	
		
		$tabs = new tabsUI($tabArray,"employeeTab");
		
		$ret.=$tabs->getTabHTML()."</div>";
		
		return $ret;
	}
	
	function getUserEditForm($userObject, $tabInfo)
	{
		$ret="";
		if(isset($userObject) && get_class($userObject)!==false && get_class($userObject)=='user')
		{	
			$userStuff = $userObject->getUserArray();
			$userName = $userStuff['FIRST_NAME']." ".$userStuff['LAST_NAME'];
			$ret.="<div class=\"regularBox\"><div class=\"title\">$userName</div>";
			
			$tabArray = array();
			$tabInfo["employeeInfoEditTab"]=count($tabArray);
			$tabArray[]=new tabUI("basicInfoTab","Basic Info",$this->getBasicUserInfoForm($userObject, copyArray($tabInfo)));
			$tabInfo["employeeInfoEditTab"]=count($tabArray);
			$tabArray[]=new tabUI("userDebtTab","Employee Debt",$this->getUserDebtForm($userObject, copyArray($tabInfo)));
			$tabInfo["employeeInfoEditTab"]=count($tabArray);
			$tabArray[]=new tabUI("userPrivilegesTab","Privileges",$this->getUserPrivilegeEditForm($userObject,copyArray($tabInfo)));
			$tabInfo["employeeInfoEditTab"]=count($tabArray);
			$tabArray[]=new tabUI("changePasswordTab","Change Password",$this->getChangePasswordForm($userObject, copyArray($tabInfo)));
			
			$tabs = new tabsUI($tabArray,"employeeInfoEditTab");
			$ret.=$tabs->getTabHTML();
			$ret.="</div>";			
		}
		return $ret;
	}
	
	function getBasicUserInfoForm($userObject, $tabInfo)
	{
		$ret="";

		if(isset($userObject) && get_class($userObject)!==false && get_class($userObject)=='user')
		{	
			global $currentUser;
			$userFields = $userObject->getFields();
			$userStuff = $userObject->getUserArray();
			$formPostVals = array();
			$formInputs = array();
			$error="";
			
			if(isset($_POST['submitUser']))
			{
				foreach($userFields as $internal => $value)
				{	
					$formPostVals[$internal]=$_POST[$internal];
					if($value->getType() == "checkbox")
					{
						$formPostVals[$internal]=(isset($_POST[$internal])?1:0);
					}
				}
				
				$result = $userObject->updateUser($formPostVals);
				if($result===true)
				{
					$error = "<div class=\"submitsuccess\">Information Updated Successfully!</div>";
					$userStuff = $userObject->getUserArray();
					$tracking = new tracking(null,null,"Changed",$userObject->getUserID(),null,null,null,null);
					$tracking->write();
					if($userObject->getUserID()==$currentUser->getUserID())
					{
						$currentUser = $userObject;
						$_SESSION["currentUser"] = $currentUser->getUserID();
						addDebug("Refreshed Current Logged In User with Edited Fields");
					}
				}
				else
				$error = $result;
			}
			else
			{
				foreach($userStuff as $internal => $value)
				$formPostVals[$internal]=$value;
			}
			
			foreach($userFields as $internal => $value)
			{
				$extraclass = $value->getRequired()===true?"req":"";
				$extraHTML = $value->getExtraHTML();
				//if($value->getType()=='date')
//					$extraclass.=" date";
				if($value->getType() == "checkbox")
				{
					if($formPostVals[$internal]===1)
					{
						$extraHTML.="checked=\"checked\"";
					}
				}
				$formInputs[$internal] = createHTMLTextBox($internal,$value->getFriendlyName(),$value->getMaxWidth(),$extraclass,false,$formPostVals[$internal],$value->getRequired(),$extraHTML,true,$value->getType());
			}
			
			
			$submit = createHTMLTextBox("submitUser","",5,"",false,"UPDATE",true,"",false,"submit");
			$ret.=$this->getUserWagePanel($userObject,$tabInfo);
			$ret.="<div class=\"regularBox\" id=\"userBasicInfoBox\"><div class=\"title\">Basic Info</div>
			<div class=\"submiterror\">$error</div>";
			
			$actionUrl =getComebackURLString($tabInfo);
			$impersonateLink="";
			addDebug("impersonate".$this->currentUser->getPrivileges()->findID("impersonate"));
			if($this->currentUser->getPrivileges()->findID("impersonate")!==false)
			{
				$impersonateLink="<a href='$actionUrl&impersonate=".$userObject->getUserID()."'>Impersonate</a>";
			}
			$ret.="<form id=\"userForm\" name=\"userForm\" method=\"post\" action=\"$actionUrl\" onsubmit=\"return validate('userForm');\"><table>";
			foreach($formInputs as $internal => $value)
			$ret.="<tr>".$value."</tr>";
			$ret.="<tr><td colspan=\"2\">$submit $impersonateLink</td></tr>";
			$ret.="</table></form>";
			$ret.="</div>";
			
		}
		
		return $ret;
	}
	
	function getUserPrivilegeEditForm($userObject, $tabInfo)
	{
		$ret="";
		
		if(isset($userObject) && get_class($userObject)!==false && get_class($userObject)=='user')
		{
			$privClass = new privilegesUI();
			$array = $privClass->getSelectPrivsTable($userObject);
			$availablePrivs=$array[0];
			$tableOrg = $array[1];
			$formPostVals = array();			
			$error="";
			
			if(isset($_POST['submitUpdatePrivileges']))
			{
				global $currentUser;
				$privsAdjust = array();
				foreach($availablePrivs as $internal => $value)
				{
					if(isset($_POST[$value->getInternalName()]))
					$privsAdjust[$value->getInternalName()]=true;
					else
					$privsAdjust[$value->getInternalName()]=false;
				}
				$p = new privileges(-1);
				$result = $p->updatePrivliegesForUser($userObject, $privsAdjust);
				if($result===true)
				{
					$error = "<div class=\"submitsuccess\">Information Updated Successfully!</div>";
					$userObject->fillVars();
					$array = $privClass->getSelectPrivsTable($userObject);
					$availablePrivs=$array[0];
					$tableOrg = $array[1];
					if($userObject->getUserID()==$currentUser->getUserID())
					{
						$currentUser = $userObject;
						$_SESSION["currentUser"] = $currentUser->getUserID();
						addDebug("Refreshed Current Logged In User with Edited Fields");
					}
				}
				else
				$error = $result;
			}	
			
			
			$ret.="<div class=\"regularBox\"><div class=\"title\">Privileges</div>
			<div class=\"submiterror\">$error</div>";
				
			$actionUrl = getComebackURLString($tabInfo);
			$i=0;
			$ret.="<form action=\"$actionUrl\" method=\"post\" id=\"userPrivilegesForm\">$tableOrg";
			$submit = createHTMLTextBox("submitUpdatePrivileges","",5,"",false,"Update",true,"",false,"submit");
			$ret.="$submit</form></div>";
		}
		return $ret;
	}
	
	function getChangePasswordForm($userObject, $tabInfo)
	{
		$ret="";
		if(isset($userObject) && get_class($userObject)!==false && get_class($userObject)=='user')
		{
			
			if(isset($_POST['submitChangePassword']))
			{
				if($_POST['pass1']==$_POST['pass2'])
				{
					$error = $userObject->changePassword($_POST['pass1']);
					if($error===true)
					$error = "<div class=\"submitsuccess\">Password Updated!</div>";
				}
				else
				$error = "Passwords do not match";
			}
			
			
			$ret.="<div class=\"regularBox\" id=\"changePasswordDiv\"><div class=\"title\">Change Password</div>
			<div class=\"submiterror\">$error</div>";
			$actionUrl = getComebackURLString($tabInfo);
			$ret.="<form id=\"changePasswordForm\" action=\"$actionUrl\" method=\"post\" onsubmit=\"return validate('changePasswordForm');\"><table>";
			//($id, $label, $maxSize, $additionalClass, $labelTop, $value, $required, $extraStuff, $table, $type)
			$primaryPassword = createHTMLTextBox("pass1","New Password", 35,"req",false,"",true,"",true,"password");
			$verifyPassword = createHTMLTextBox("pass2","Re-type Password", 35,"req",false,"",true,"",true,"password");
			$submit = createHTMLTextBox("submitChangePassword","",5,"",false,"Change Password",true,"",false,"submit");
			$ret.="<tr>$primaryPassword</tr><tr>$verifyPassword</tr>";
			$ret.="<tr><td colspan=\"2\">$submit</td></tr></table></form>";
			$ret.="</div>";
		}
		
		return $ret;
		
	}
	
	function getUserDebtForm($userObject, $tabInfo)
	{
		
		$ret="";
		if(isset($userObject) && get_class($userObject)!==false && get_class($userObject)=='user')
		{
			
			$tabArray = array();
			$userDebtUI = new userdebtui($userObject);
			$tabInfo["userDebtTabSub"]=count($tabArray);
			$tabArray[] = new tabUI("userDebtSummaryTabContainer","Debt Summary", $this->getUserDebtSummary($userObject, copyArray($tabInfo)));
			$tabInfo["userDebtTabSub"]=count($tabArray);
			$tabArray[] = new tabUI("addDebtInputDiv","Input Debt",$userDebtUI->getAddDebt(copyArray($tabInfo)));
			
			$tabs = new tabsUI($tabArray, "userDebtTabSub");
			$ret.=$tabs->getTabHTML();
		}
		
		return $ret; 
		
	}
	
	function getUserDebtSummary($userObject, $tabInfo)
	{
		$ret="";
	
		if(isset($userObject) && get_class($userObject)!==false && get_class($userObject)=='user')
		{
			$userDebtUI = new userdebtui($userObject);
			$summaryList = $userDebtUI->getDebtSummary(true);
			$userIDHidden = createHTMLTextBox("thisUserID","",15,"nodisplay",false,$userObject->getUserID(),false,"",false,"hidden");
			$ret.="$userIDHidden<div class=\"regularBox\" id=\"debtSummaryList\"><div class=\"title\">Employee Debt</div><table><tr><td>
			$summaryList
			</td><td>
			<div class=\"resizeiframe\" style='min-width: 200px'><div id=\"userDebtSummaryPane\"></div></div>
			</td></tr></table></div>";
		}
		return $ret;
	}
	
	function getUserListForm()
	{
		
		addDebug("search UI Starting");
		$table = $this->getUserSearchResultsTable(null);
		$ret= "<div id=\"resulttable\">$table</div>";
		return $ret;
	}
	
	function getUserSearchResultsTable($searchstring)
	{	
		addDebug("getUserSearchResultsTable called");
		$anchorProps =array("NAME"=>"");
		if(isset($this->uri['search']))
			$search=$this->uri['search'];
		$selectCols = array("USERID","CONCAT(FIRST_NAME,' ',LAST_NAME) AS NAME","PHONE1","PHONE2","EMAIL_ADDRESS","END_DATE");
		$showCols = array("NAME"=>"Name","PHONE1"=>"Phone 1","PHONE2"=>"Phone 2","EMAIL_ADDRESS"=>"Email","END_DATE"=>"End Date");
		$ClickPos=array("NAME"=>"USERID");
		$searchCols = array("FIRST_NAME","LAST_NAME","PHONE1","PHONE2","EMAIL_ADDRESS","ADDRESS1","ADDRESS2");
		$tableID = "employeeSearchTable";
		$uriValClick = array("NAME"=>"userid");
		$additionalURI = array("NAME"=>"pageid=".$this->uri['pageid']);
		$extraWhereClause = "END_DATE IS NULL";
		$search=null;
		$getRaw=null;
		$orderClause = "LAST_NAME DESC LIMIT 50";
		if(isset($searchstring))
		{
			$search=$searchstring;
			$getRaw=1;
			$orderClause="START_DATE DESC";
			$extraWhereClause="";
		}
		$resultTable = makeSearchTable("" . $this->tablePrefix ."users",$selectCols,$ClickPos,$showCols,$searchCols,$tableID,$uriValClick,$additionalURI,$anchorProps,$search,$extraWhereClause,$orderClause,$getRaw);
		
		if(isset($searchstring))
		{
			echo json_encode($resultTable);
		}
		else
		{		
			return $resultTable;
		}		
	}
	
	function getCreateUserForm($tabInfo)
	{	
		
		addDebug("Create New User UI Starting..");
		$ret = "";
		$error = "";
		$showForm=true;
		$user = new user(-1);
		$formInputs = array("createUserDiv_FIRST_NAME"=>"","createUserDiv_LAST_NAME"=>"","createUserDiv_EMAIL_ADDRESS"=>"","createUserDiv_USERNAME"=>"","createUserDiv_START_DATE"=>"");
		$formPostVals = array();
		if(isset($_POST['submitNewUser']))
		{
			foreach($formInputs as $internal => $value)
			$formPostVals[$internal]=$_POST[$internal];
			$user = new user(-1);
			$result = $user->createNewUser($formPostVals['createUserDiv_FIRST_NAME'],$formPostVals['createUserDiv_LAST_NAME'],$formPostVals['createUserDiv_EMAIL_ADDRESS'],$formPostVals['createUserDiv_USERNAME'],$formPostVals['createUserDiv_START_DATE']);
			if(is_numeric($result))
			{
				$showForm=false;
				$this->uri["userid"]=$result;
				foreach($this->uri as $internal => $value)
				{
					if(strstr($internal,"come")===false)
					$urit.="&$internal=$value";
				}
				$error = "<div class=\"submitsuccess\">New User Created Successfully</div><br /><a href=index.php?$urit>Edit ".$formPostVals['createUserDiv_FIRST_NAME']." ".$formPostVals['createUserDiv_LAST_NAME']."</a>";
				$tracking = new tracking(null,null,"Created New Employee",$result,null,null,null,null);
				$tracking->write();
			}
			else
			$error = $result;
		}
		if($showForm)
		{
			//$id, $label, $maxSize, $additionalClass, $labelTop, $value, $required, $extraStuff, $table, $type)
			$userStuff = $user->getFields();
			
			foreach($formInputs as $internal => $value)
			{
				$int = str_replace("createUserDiv_","",$internal);
				$formInputs[$internal] = createHTMLTextBox($internal,$userStuff[$int]->getFriendlyName(),$userStuff[$int]->getMaxWidth(),$userStuff[$int]->getRequired()?"req":"",false,$formPostVals[$internal],$userStuff[$int]->getRequired(),$userStuff[$int]->getExtraHTML(),true,$userStuff[$int]->getType());
			}
			
			$submit = createHTMLTextBox("submitNewUser","",5,"",false,"Create Employee",true,"",false,"submit");
			$actionUrl = getComebackURLString($tabInfo);
			$ret="<div class=\"regularBox\" id=\"createUserDiv\">
			<div class=\"title\">Create Employee</div><div class=\"submiterror\">$error</div>
			<form id=\"createUserForm\" name=\"createUserForm\" method=\"post\" action=\"$actionUrl\" onsubmit=\"return validate('createUserForm');\">
			<table>";
			foreach($formInputs as $internal => $value)
			$ret.="<tr>".$value."</tr>";
			$ret.="</table>$submit</form>";
			$ret=$ret;
			$ret.="</div> <!-- END createUserDiv -->";
		}
		else
		$ret.=$error;
		return $ret;
	}

}

?>
