$(document).ready(function() {
    getVendorTable($('#vendor_datatable'));
});

function getVendorTable(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"></div>');
    var querystring = {'getsummarytable': '1'};
    var url = createServerCallBackURL(querystring);
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
    var html = "<textarea id='jsoneditor'>" + htmlUnEscape(data) + "</textarea><input source = '"+source+"' type='button' value='Submit' onClick='saveJSON(this)' />";
    
    createOverlayDialog(html);
}

function saveJSON(element)
{
    var source = $(element).attr('source');
    console.log(source + ' = ' + $("#jsoneditor").val());
    var submitdata = $("#jsoneditor").val();

    var querystring = {'submitjson': source};
    var url = createServerCallBackURL(querystring);
    console.log("Getting data: "+url);
    $.post(url, {'payload' : htmlEscape(submitdata)} ).done(
        function(data){
            if(data == '1')
            {
                overlayDialogMessage("", 'success');
                writeBackSuccess(source, submitdata);
            }
            else
            {
                overlayDialogMessage(data)
            }
            console.log(data);
    }, 'json');

}

function writeBackSuccess(source, jsontext)
{
    $("a").each(function(index)
    {
        if($(this).attr('source') && $(this).attr('source') == source && $(this).attr('json'))
        {
            $(this).html(jsontext);
        }
    });
}

function showScreenShots(element)
{
    var data = $(element).html();
    var source = $(element).attr('source');
    var querystring = {'sourceid': source, 'screenshotdiag': '1'};
    var url = createServerCallBackURL(querystring, 'getjson');
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
