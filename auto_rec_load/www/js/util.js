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
    $("body").append("<div id=\"overlaydialog\"><div id=\"overlaydialogcontainer\"><div id=\"close-overlay\"><a href=\"#\">[close]</a></div>" + html + "<div id='jsoneditorerrorbox'></div></div></div>");
    $("#close-overlay").click(function(){
        $("#overlaydialog").remove();
    });
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