<?php
require_once("sqlconnect.php");


class login
{
	private $userID=-1;
	private $sqlconnect;

	function __construct()
	{
		global $sqlconnect;
		$this->sqlconnect = $sqlconnect;
	}

	function loginBox()
	{
		$ret="";
		
        $ret.= '<script type="text/javascript">
        function checkEnter(e){
            var characterCode

            if(e && e.which){
                e = e
                characterCode = e.which
            }
            else{
                e = event
                characterCode = e.keyCode
            }

            if(characterCode == 13){ 
                $("#loginForm").submit(function(){});
                return false;
            }
            else{
                return true;
            }

        }	
            </script>';
        
        $loginBox = createHTMLTextBox("login","Login",15,"req",false,"",true,"",true,"text");
        $passwordBox = createHTMLTextBox("pass","Password",35,"req",false,"",true,'onKeyPress="checkEnter(event)"',true,"password");
        $submitButton = createHTMLTextBox("loginButton","loginButton",0,"pencilThin",false,"Login",false,"",false,"submit");
        $forgotpasswordButton = createHTMLTextBox("fpasswordButton","",0,"pencilThin",false,"Forgot Password",false,"",false,"submit");
        $ret.='
        <div id="loginDiv">
        <div class="title">Please Login</div>
        <form action="" method="post" id="loginForm" onsubmit="return validate(\'loginForm\',[\'pass\']);">
        <table id="loginBoxTable">
        <tr>'.$loginBox.'</tr><tr>'.$passwordBox.'
        </tr>
        </table>';
        $ret.=$this->handlePost()."<br />";
        $ret.=$submitButton.'<br />'.$forgotpasswordButton.'
        </form></div>';

		return $ret;
	}
	
	function userInfoBox()
	{
		global $currentUser;
		$ret="";
		if(isset($currentUser))
			{
				$userstuff = $currentUser->getUserArray();
				if($userstuff!==false)
				{
					$ret.= '<div id="userInfoBox">
					<span class="headerform">'.$userstuff["FIRST_NAME"].' '.$userstuff["LAST_NAME"].'</span><br />
					<span>'.$userstuff["PHONE1"].'</span><br />
					<span>'.$userstuff["EMAIL_ADDRESS"].'</span><br />
					<span><a href="index.php?logout=1">Logout</a></span></div>';
				}
			}
		return $ret;
	}

	function handlePost()
	{	
		$ret="";
		// $fail = new loginfailclass();
		// if(isset($_POST["fpasswordButton"]))
		// {
			// if(strlen(trim($_POST["login"]))==0)
			// $ret='<span class="submiterror">Please Provide Username<br />Or Email</span>';
			// else
			// {	
				// $fail->logBadAttempt($_POST["login"],$_POST["pass"]);
				// $email = new email();
				// $success = $email->sendForgotPassword(trim($_POST['login']));
				// if($success === true)
				// $ret='<span class="submitsuccess">Email Sent</span>';
				// else
				// $ret='<span class="submiterror">Could not find matching account.<br />Please type your email or username into the login box</span>';
			// }
		// }
		// else if(isset($_POST["login"]))
		// {
			// addDebug("Trying ".$_POST["login"]." and ".$_POST["pass"]);
			// $getLogin = $this->loginUser($_POST["login"],$_POST["pass"]);
			// if($getLogin!==true)
			// {
				// $fail->logBadAttempt($_POST["login"],$_POST["pass"]);
				// $ret='<span class="submiterror">Invalid Login</span>';
			// }
			// else
			// {	
				// $ret="<span class=\"submitsuccess\">Logging In....</span>";
				// $tracking = new tracking(null,null,"Logged In",null,null,null,null,null);
				// $tracking->write();
				// global $uriString;
				// redirectTo("index.php?$uriString");
			// }
		// }
	 	return $ret;
	}
	
	function loginUser($input_username, $input_password)
	{
		
		if(strlen($input_username)>2 && strlen($input_password)>2)
		{
			$vars = array();
			$vars[]=strtoupper($input_username);
			$vars[]=$input_password;
			//$query="SELECT USERID FROM USERS WHERE UPPER(USERNAME)='".$vars[0]."' AND PASSWORD=MD5('".$input_password."')";
			$query="SELECT USERID FROM USERS WHERE UPPER(USERNAME)=? AND PASSWORD=MD5(?)";
			addDebug($query);
			$result = $this->sqlconnect->executeQuery($query,$vars);
			addDebug("Login result count = ".count($result));
			if(count($result)==1)
			{	
				global $currentUser;
				$userID = -1;
				foreach($result as $internal => $row)
				{	
					$userID=$row["USERID"];
				}
				$currentUser=new user($userID);
				if($currentUser->getPrivileges()->findID("loginallowed")!==false)
				{
					addDebug("Found Privilege");
					$_SESSION["currentUser"] = $userID;
					$currentUser = new user($_SESSION["currentUser"]);
					$val = isset($_SESSION["currentUser"]);
					addDebug("Created user Session - ".$val);
					return true;
				}				
				else
				{
					unset($_SESSION["currentUser"]);
					$currentUser=null;
				}
			}
		}
		return false;
	}
	
	function impersonate($userToImpersonate)
	{
		$ret=false;
		if((isset($_SESSION["currentUser"])) && ($_SESSION["currentUser"]>0))
		{
			$currentUser = new user($_SESSION["currentUser"]);
			if($currentUser->getPrivileges()->findID("impersonate")!==false)
			{
				$destUser = new user($userToImpersonate);
				$traits = $destUser->getUserArray();
				if(strlen($traits["USERNAME"])>0)
				{
					$_SESSION["currentUser"] = $userToImpersonate;
					$_SESSION["impUser"] = $currentUser->getUserID();
					$ret=true;
				}
			}	
		}
		return $ret;
	}
	
	function unimpersonate()
	{	
		$ret="";
		if((isset($_SESSION["currentUser"])) && ($_SESSION["currentUser"]>0) && isset($_SESSION["impUser"]))
		{		
			$_SESSION["currentUser"] = $_SESSION["impUser"];
			unset($_SESSION["impUser"]);
			$ret=redirectTo("index.php");
		}
		return $ret;
	}
}


?>