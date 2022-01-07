$(document).ready(function() {
	console.log("width " + $('.dashboard_summary_pie_chart').width());
    
	
});

function drawPie(wrapperdiv)
{
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var width = wrapperdiv.width();
    console.log("width " + width);
    wrapperdiv.html("");
    wrapperdiv.append('<img src="' + path + '/index.php?getgraph=1&summarypie=1&width="' + width + '&' + pageID + '" />');
    
}

function htmlEscape(str) 
{
	return encodeURIComponent(str);
    return String(str)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/ /g, '%20');
}

function htmlUnEscape(str) 
{
	//return str;
    return String(str)
            .replace('&amp;', '&')
            .replace('&quot;', '"')
            .replace('&#39;', "'")
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('%20', ' ');
}