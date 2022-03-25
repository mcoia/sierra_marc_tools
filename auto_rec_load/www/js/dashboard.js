$(document).ready(function() {
	console.log("width " + $('#dashboard_summary_pie_chart').width());
    drawPie($('#dashboard_summary_pie_chart'));
    getSummaryTable($('#dashboard_summary_datatable'));
    getStats();

    $('#datesince').on('change', function() {
        drawPie($('#dashboard_summary_pie_chart'));
        getSummaryTable($('#dashboard_summary_datatable'));
        getStats();
    });
	
});

function drawPie(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"></div>');
    var width = wrapperdiv.width();
    var querystring = {'summarypie': '1'};
    if($('#datesince'))
    {
        querystring['fromdate'] = convertStringToDate($('#datesince').val());
    }
    console.log("width " + width);
    width = width > 500 ? 500 : width;
    console.log("width " + width);
    querystring['width'] = width;
    var url = createServerCallBackURL(querystring, 'getgraph');
    wrapperdiv.html("");
    wrapperdiv.append('<img src="' + url + '" />');
    wrapperdiv.remove('.loader');
}

function getSummaryTable(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"></div>');
    var querystring = {'getsummarytable': '1'};
    if($('#datesince'))
    {
        querystring['fromdate'] = convertStringToDate($('#datesince').val());
    }
    var url = createServerCallBackURL(querystring);
    $.get(url,
        function(data){
            wrapperdiv.html(data);
            setupDataTables();
    });
}

function getStats()
{
    $(".dashboard_stat_panel_child_result").each(function(){
        var affectElement = $(this);
        affectElement.append('<div class="loader" style="width: 60px;height: 60px;"></div>');
        var statID = affectElement.parent().attr('id');
        var querystring = {'statid': statID, 'getstat': '1'};
        if($('#datesince'))
        {
            querystring['fromdate'] = convertStringToDate($('#datesince').val());
        }
        var url = createServerCallBackURL(querystring);
        $.get(url,
            function(data){
                affectElement.remove('.loader');
                affectElement.html(data);
        });
    });
}