$(document).ready(function() {
    $('#datesince').on('change', function() {
        console.log('clicked: ' + $(this).val());
        autoloadSetCookie('controlfromdate', $(this).val(), 30);
    });
    var fromDateCookie = autoloadGetCookie('controlfromdate');
    if(fromDateCookie)
    {
        var currentSelect = $('#datesince').val();
        selectElement('datesince', fromDateCookie);
        var nowVal = $('#datesince').val();
        if(nowVal != currentSelect)
        {
            console.log("current: "+currentSelect +" nowVal: "+nowVal);
            $('#datesince').trigger('change');
        }
    }
});

function convertStringToDate(dateString)
{
    console.log("convertStringToDate");
    var ret = new Date();
    switch(dateString)
    {
        case 'lastsevendays':
            ret = new Date(ret.setDate(ret.getDate() - 7));
        break;
        case 'lasttwoweeks':
            ret = new Date(ret.setDate(ret.getDate() - 14));
        break;
        case 'lastmonth':
            ret = new Date(ret.setMonth(ret.getMonth() - 1));
        break;
        case 'lastsixmonths':
            ret = new Date(ret.setMonth(ret.getMonth() - 6));
        break;
        case 'lastyear':
            ret = new Date(ret.setMonth(ret.getMonth() - 12));
        break;
    }
    return ret.yyyymmdd();
}

Date.prototype.yyyymmdd = function() {
      var mm = this.getMonth() + 1; // getMonth() is zero-based
      var dd = this.getDate();

      return [this.getFullYear(),
              (mm>9 ? '' : '0') + mm,
              (dd>9 ? '' : '0') + dd
             ].join('-');
    };

