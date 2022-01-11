<?php


class control_panel
{
    function __construct()
    {
        
    }

    function getDateControlPanel()
    {
        $options = array(
            "Last 7 days" => "lastsevendays",
            "Last 2 weeks" => "lasttwoweeks",
            "Last 30 days" => "lastmonth",
            "Last 6 months" => "lastsixmonths",
            "Last 365 days" => "lastyear"
        );
        $selectMenu = $this->getSelect($options, 'datesince');
        $ret = "
        <script type=\"text/javascript\" src=\"js/control_panel.js\"></script>
        <div id='datecontrolpanel'>
            <div id='datesincediv' class='controlpanel_child'>
                $selectMenu
            </div> <!-- datesince -->
        </div> <!-- datecontrolpanel -->";

        return $ret;
    }
    function getSelect($options, $id)
    {
        $ret = "<select id='$id'>";
        foreach($options as $internal => $value)
        {
            $ret .= "<option value='$value'>$internal</option>";
        }
        $ret .= "</select>";
        return $ret;
    }
}