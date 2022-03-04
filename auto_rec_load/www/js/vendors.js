$(document).ready(function() {
    getVendorTable($('#vendor_datatable'));
});

function getVendorTable(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"</div>');
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var fromDate = '';
    var url = path+"/index.php?getdata=1" + fromDate + "&getsummarytable=1&"+pageID;
    console.log("Getting data: "+url);
    $.get(url,
        function(data){
            wrapperdiv.html(data);
            setupDataTables();
    });
}

function editJSONClick(element)
{
    var data = $(element).html();
    var source = $(element).attr('source');
    var html = "<div id='jsoneditorwrapper'><textarea id='jsoneditor'>" + htmlUnEscape(data) + "</textarea><input source = '"+source+"' type='button' value='Submit' onClick='saveJSON(this)' />"+
    "<div id='jsoneditorerrorbox'></div></div>";
    createOverlayDialog(html);
}

function saveJSON(element)
{
    var source = $(element).attr('source');
    console.log(source + ' = ' + $("#jsoneditor").val());
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var submitdata = $("#jsoneditor").val();
    
    var url = path+"/index.php?getdata=1&submitjson="+source+"&"+pageID;
    console.log("Getting data: "+url);
    $.post(url, {'payload' : htmlEscape(submitdata)} ).done(
        function(data){
$("#jsoneditorerrorbox").html(data);
            //$("#jsoneditorerrorbox").html(htmlUnEscape(data));
            if(data == '1')
            {
                $("#jsoneditorerrorbox").html("<span id='jsonsuccess' style='color:green;font-size: 12pt'>success</span>");
                $("#jsonsuccess").fadeOut(5000);
                writeBackSuccess(source, submitdata);
            }
            console.log(data);
    }, 'json');

}

function writeBackSuccess(source, jsontext)
{
    $("a").each(function(index)
    {
        if($(this).attr('source') && $(this).attr('source') == source)
        {
            $(this).html(jsontext);
        }
    });
}

function showScreenShots(element)
{
    var data = $(element).html();
    var source = $(element).attr('source');
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var fromDate = '';
    var url = path+"/index.php?getjson=1&sourceid=" + source + "&screenshotdiag=1&" + pageID;
    console.log("Getting data: "+url);
    $.get(url,
        function(data){
            var html = '';
            if(data.status == 'success')
            {
                html = '<table class="screnshot_table">\n';
                html += '<thead><th>Step</th><th>Action</th><th>Screenshot</th></thead>\n';
                html += '<tbody>\n';
                for (var d in data.images)
                {
                    html += '<tr>\n';
                    html += '<td>'+d+'</td>';
                    html += '<td>'+data.images_name[d]+'</td>';
                    html += '<td><a href="'+data.images[d]+'"><img src="'+data.images[d]+'" /></a></td></tr>\n';
                }
            }
            else
            {
                html = '<div class="screenshoterror">'+data.statuscode+'</div>';
            }
            $("#screenshotload").html(html);
    });
}
