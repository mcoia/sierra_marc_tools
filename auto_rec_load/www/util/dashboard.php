<?php


class dashboardUI
{
	private $sqlconnect;
	private $uri;
	private $url;
	private $currentUser;
	private $currentURLBase;
	private $job;
	function __construct()
	{	
		global $currentUser;
		global $sqlconnect;
		global $uri;
		global $url;
		global $currentURLBase;
		$this->uri = copyArray($uri);
		$this->sqlconnect = $sqlconnect;
		$this->currentUser = $currentUser;
		$this->currentURLBase = $currentURLBase;
		$this->url = $url;
	}
	
	function go()
	{			
		$ret="";
       
		if(isset($this->uri['getdata']))
		{
            $summaryData = $this->getSummaryData('2021-01-01',0);
            print_r ($summaryData);
            exit();
			if(isset($this->uri['additionalsearch']) && isset($this->uri['searchstring']) && strlen($this->uri['searchstring']) > 1 )
			{	
				$this->getJobSearchResultsTable($this->uri['searchstring']);
				exit();
			}
			else if(isset($this->uri['bidid']))
			{
				$laborid=isset($this->uri['laborid'])?$this->uri['laborid']:null;
				$materialid=isset($this->uri['materialid'])?$this->uri['materialid']:null;
				$ret = $this->updateBidItem($this->uri['bidid'],$this->uri['dec'],$laborid,$materialid,$this->uri['footage'],$this->uri['unit'],$this->uri['total']);
			}
		}
		else if(isset($this->uri['getgraph']))
        {
            if(isset($this->uri['summarypie']))
            {
                makePieChart();
            }
        }
        else
		{
			$ret = $this->UI();
		}
		return $ret;
	}

	function UI()
	{
		$ret="";
		$ret.="<div class=\"regularBox\">
        <div class='dashboard_summary_container'>
        <div class='dashboard_summary_pie_chart dashboard_summary_container_child'>
        
        </div> <!-- dashboard_summary_pie_chart -->
        <div class='dashboard_summary_datatable dashboard_summary_container_child'>
        
        </div> <!-- dashboard_summary_datatable -->
        </div> <!-- dashboard_summary_container -->
        </div>";
		return $ret;
	}

    function getSummaryData($fromDate, $toDate)
    {
        $vars = array();
        $daterange = "";
        $query = "
        select aj.status,ac.name \"client\", autos.name \"source\", count(*)
        from
        auto_import_status ais,
        auto_file_track aft,
        auto_source autos,
        auto_client ac,
        auto_job aj
        where
        aj.id=ais.job and
        ac.id=aft.client and
        autos.id=aft.source and
        aft.id=ais.file
        !!daterange!!
        group by 1,2";
        if($fromDate)
        {
            $daterange .= "
            and aj.start_time > ?";
            $vars[] = $fromDate;
        }
        if($toDate)
        {
            $daterange .= "
            and aj.start_time < ?";
            $vars[] = $toDate;
        }

        $query = preg_replace('/!!daterange!!/i', $daterange, $query);

		$result = $this->sqlconnect->executeQuery($query,$vars);
        return $result;
    }
    

    function makePieChart($percents, $labels, $small = true, $height = 500, $width = 500)
	{
        $labels = array('test1' ,'test2' ,'test3', 'test3');
        $percents =  array(.3,.3,.3,.1);
        $piegraph = new PieGraph($height, $width);
        $pieplot = new PiePlot($percents);
        $pieplot->SetLabels($labels);
        $pieplot->ExplodeAll(10);
        $piegraph->Add($pieplot); 
        $piegraph->Stroke();

	}
	
}