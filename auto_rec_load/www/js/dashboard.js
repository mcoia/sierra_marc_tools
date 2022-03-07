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
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var width = wrapperdiv.width();
    var fromDate = '';
    if($('#datesince'))
    {
        fromDate = '&fromdate=' + convertStringToDate($('#datesince').val());
    }
    console.log("width " + width);
    width = width > 500 ? 500 : width;
    console.log("width " + width);
    var url = path + '/index.php?getgraph=1&summarypie=1' + fromDate + '&width=' + width + '&' + pageID;
    console.log("Getting img: "+url);
    wrapperdiv.html("");
    wrapperdiv.append('<img src="' + url + '" />');
    wrapperdiv.remove('.loader');
}

function getSummaryTable(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"></div>');
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var fromDate = '';
    if($('#datesince'))
    {
        fromDate = '&fromdate=' + convertStringToDate($('#datesince').val());
    }
    var url = path+"/index.php?getdata=1" + fromDate + "&getsummarytable=1&"+pageID;
    console.log("Getting data: "+url);
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
        var pageID = "pageid="+$("#thisPageID").val();
        var path = location.protocol+"//"+location.hostname;
        var fromDate = '';
        if($('#datesince'))
        {
            fromDate = '&fromdate=' + convertStringToDate($('#datesince').val());
        }
        var url = path+"/index.php?getdata=1&getstat=1" + fromDate + "&statid=" + statID + "&"+pageID;
        console.log("Getting data: "+url);
        $.get(url,
            function(data){
                affectElement.remove('.loader');
                affectElement.html(data);
        });
    });
}