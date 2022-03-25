function autoloadGetCookie(cname)
{
    var name = "autoload_" + cname + "=";
    var ca = document.cookie.split(';');
    for(var i=0; i<ca.length; i++)
    {
        var c = ca[i];
        while (c.charAt(0)==' ') c = c.substring(1);
        if (c.indexOf(name) == 0) return c.substring(name.length,c.length).replace(/v0v/g,';').replace(/v1v/g,'&');
    }
    return 0;
}

function autoloadSetCookie(cname, cvalue, exdays)
{
    cvalue = cvalue.replace(/;/g,'v0v').replace(/&/g,'v1v');
    var d = new Date();
    d.setTime(d.getTime() + (exdays*24*60*60*1000));
    var expires = "expires="+d.toUTCString();
    var finalc = "autoload_" + cname + "="
    + cvalue
    + "; " + expires
    + "; path=/";
    //+ cvalue
    document.cookie = finalc;
}

function selectElement(id, valueToSelect)
{    
    let element = document.getElementById(id);
    element.value = valueToSelect;
}

function createOverlayDialog(html)
{
    $("body").append("<div id=\"overlaydialog\"><div id=\"overlaydialogcontainer\"><div id=\"close-overlay\"><a href=\"#\">[close]</a></div>" + html + "<div id='overlaydialogresponsecontainer'></div></div></div>");
    $("#close-overlay").click(function(){
        $("#overlaydialog").remove();
    });
}

function overlayDialogMessage(message, messageType = 'error')
{
    var cssclass = 'submiterror';
    var fade = 0;
    // design decision here, figured if it's success, we're always going to fade out
    if( message.length == 0 && messageType == 'success' )
    {
        message = 'Success';
        fade = 1;
    }
    if(messageType == 'success')
    {
        cssclass = 'submitsuccess';
    }
    var wrapper = "<div id=\"overlaydialogresponsemessage\" class=\""+cssclass+"\">"+message+"</div>";
    $("#overlaydialogresponsecontainer").html(wrapper);
    if(fade)
    {
        $("#overlaydialogresponsemessage").fadeOut(5000);
    }
}

function htmlEscape(str) 
{
	//return encodeURIComponent(str);
    return String(str)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/\\n/g,'&NewLine;')
            .replace(/ /g, '&nbsp;')
            // .replace(/\\/g, '!!backslash!!')
            // .replace(/@/g, '&commat;') // php doesn't unescape this https://www.php.net/manual/en/function.htmlspecialchars-decode.php
            ;
}

function htmlUnEscape(str) 
{
	//return str;
    return String(str)
            .replace(/&commat;/g, '@')
            .replace(/&nbsp;/g, ' ')
            .replace(/&NewLine;/g, "\n")
            .replace(/&gt;/g, '>')
            .replace(/&lt;/g, '<')
            .replace(/&#39;/g, "'")
            .replace(/&quot;/g, '"')
            .replace(/&amp;/g, '&');
}

function createServerCallBackURL(querystringOptionArray, type = 'getdata')
{
    var path = location.protocol+"//"+location.hostname;
    var pageID = "pageid="+$("#thisPageID").val();
    var querystring = '';
    for (var key in querystringOptionArray)
    {
        querystring += "&" + key + "=" + querystringOptionArray[key];
    }
    if(querystring.length > 0)
    {
        querystring = querystring.substring(1); // strip the first &
        querystring += "&"; // put it at the end
    }
    var url = path+"/index.php?"+querystring+type+"=1&"+pageID;
    console.log("Getting data: "+url);
    return url;
}