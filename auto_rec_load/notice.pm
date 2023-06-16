#!/usr/bin/perl

package notice;

use lib qw(./);
use Data::Dumper;
use JSON;
use Email::MIME;
use Email::Send;
use Encode;

use Loghandler;

use parent commonTongue;

sub new
{
    my ($class, @args) = @_;
    my ($self, $args) = $class->SUPER::new(@args);
    @args = @{$args};
    $self = _init($self, @args);
    return $self;
}

sub _init
{
    my $self = shift;
    $self->{noticeID} = shift;
 
    if($self->{noticeID} && $self->{dbHandler} && $self->{prefix} && $self->{log})
    {
        $self = _fillVars($self);
        if($self->getError())
        {
            $self->addTrace("Error loading notice object");
        }
    }
    return $self;
}

sub _fillVars
{
    my $self = shift;

    my $query = "SELECT 
    id FROM
    ".$self->{prefix}.
    "_notice_history
    WHERE
    id = ".$self->{noticeID};

    my @results = @{$self->{dbHandler}->query($query)};

    $self->setError("No notice with that ID number: " . $self->{noticeID}) if($#results == -1);
    if($#results > -1)
    {
        $query = "SELECT
        ant.name,
        ant.enabled,
        ant.source,
        ant.type,
        ant.upon_status,
        ant.template,
        anh.status,
        anh.job,
        anh.create_time,
        anh.send_time,
        anh.data,
        anh.send_status
        FROM
        ".$self->{prefix} ."_notice_history anh
        JOIN
        ".$self->{prefix} ."_notice_template ant ON (ant.id = anh.notice_template)
        WHERE
        anh.id = ".$self->{noticeID};
        @results = @{$self->getDataFromDB($query)};
        foreach(@results)
        {
            my @row = @{$_};
            $self->{name} = $row[0];
            $self->{enabled} = $row[1];
            $self->{source} = $row[2];
            $self->{type} = $row[3];
            $self->{upon_status} = $row[4];
            $self->{template} = $row[5];
            $self->{status} = $row[6];
            $self->{job} = $row[7];
            $self->{create_time} = $row[8];
            $self->{send_time} = $row[9];
            $self->{data} = $row[10];
            $self->{send_status} = $row[11];
            last; # should only be one row returned
        }
    }

    return $self;
}

sub queueNotice
{
    my $self = shift;
    my $job = shift;
    my $type = shift;
    my $upon_status = shift;
    my $additionalMessage = shift;
    my %stats = %{getJobStats($self)};
    my @possibleVars = qw/totalrecords numberoffiles filenames filecounts jobid jobcreated jobstarted jobfinished typetotalcounts typeloaded jobtrace/;
    my @template = @{getNoticeTemplateForJob($self, $job, $type, $upon_status)};
    if(@template[1] && @template[1] ne '')
    {
        # flatten the string to one line so we can do some regex
        @template[1] =~ s/\n/!!!!!!!/g;
        @template[1] =~ s/\r/_______________/g;
        foreach(@possibleVars)
        {
            if(@template[1] =~ /\$$_/)
            {
                print "replacing $_\n";
                my $flat = 0;
                my $truncate = 0;
                my $vars = @template[1];
                # Figure out if the template has flat and truncate requests
                # format is: $type($flat,$truncate)
                my $before = $vars;
                $vars =~ s/^(.*?)\$$_\(([^\)]*)\)(.*)$/$2/;
                if($vars ne $before) # it got updated
                {
                    my @vals = split(/,/, $vars);
                    for my $i (0..$#vals)
                    {
                        # trim spaces
                        @vals[$i] =~ s/^\s*//g;
                        @vals[$i] =~ s/\s*$//g;
                    }
                    $flat = @vals[0];
                    $truncate = @vals[1] || 0;
                    $flat = 0 if $flat eq '';
                    $truncate = 0 if $truncate eq '';
                    @template[1] =~ s/^(.*?\$$_)\([^\)]*?\)(.*)$/$1$2/g
                }
                my $replacement = _dataToString($self, \%stats, $_, $flat, $truncate);
                $replacement =~ s/\n/!!!!!!!/g;
                $replacement =~ s/\r/_______________/g;
                @template[1] =~ s/\$$_/$replacement/g;
            }
        }
        # unflatten
        @template[1] =~ s/!!!!!!!/\n/g;
        @template[1] =~ s/_______________/\r/g;
        @template[1] .= "\n$additionalMessage" if $additionalMessage;
        print "template: " . @template[1] ."\n";
        return _insertNotice($self, @template[0], $job, @template[1]);
    }
    return 0;
}

sub _insertNotice
{
    my $self = shift;
    my $noticeTemplateID = shift;
    my $job = shift || $self->{job};
    my $data = shift;
    my $query = "INSERT INTO
    ".$self->{prefix} ."_notice_history (notice_template,job,data)
    values(?,?,?)";
    my @vars = ($noticeTemplateID, $job, $data);
    $self->doUpdateQuery($query, undef, \@vars);
    my $id = getLastNoticeIDForJob($self, $job, 1);
    if($id)
    {
        $self->{noticeID} = $id;
        $self->_fillVars();
    }
    return $id;
}

sub getLastNoticeIDForJob
{
    my $self = shift;
    my $job = shift || $self->{job};
    my $very_recent = shift;
    my $ret = 0;
    my $query = "SELECT MAX(id)
    FROM
    ".$self->{prefix} ."_notice_history nh
    WHERE
    job = ?
    ";
    $query .= "AND create_time > NOW() - INTERVAL 1 MINUTE" if($very_recent);
    my @vars = ($job);
    my @results = @{$self->getDataFromDB($query, \@vars)};
    foreach(@results)
    {
        my @row = @{$_};
        $ret = @row[0];
    }
    return $ret;
}

sub getNoticeTemplateForJob
{
    my $self = shift;
    my $job = shift;
    my $type = shift;
    my $upon_status = shift || 'generic';
    my @ret = ();
    my $query = "
    SELECT distinct nt.id,nt.template
    FROM
    ".$self->{prefix} ."_job aj
    JOIN ".$self->{prefix} ."_notice_template nt on (nt.source=aj.source)
    WHERE
    nt.enabled is true and
    aj.id = ? and
    nt.upon_status = ? and
    nt.type = ?
    ";
    my @vars = ($job, $upon_status, $type);
    my @results = @{$self->getDataFromDB($query, \@vars)};
    foreach(@results)
    {
        my @row = @{$_};
        push(@ret, @row[0]);
        push(@ret, @row[1]);
    }
    if($#results < 0) # failover to a catchall template where source is null
    {
        my $query = "
        SELECT distinct nt.id,nt.template
        FROM
        ".$self->{prefix} ."_notice_template nt
        WHERE
        nt.enabled is true and
        nt.source is null and
        nt.upon_status = ? and
        nt.type = ?
        ";
        my @vars = ($upon_status, $type);
        my @results = @{$self->getDataFromDB($query, \@vars)};
        foreach(@results)
        {
            my @row = @{$_};
            push(@ret, @row[0]);
            push(@ret, @row[1]);
        }
    }
    return \@ret;
}

sub _dataToString
{
    my $self = shift;
    my $statsRef = shift;
    my $type = shift;
    my $flat = shift || 0;
    my $truncateLength = shift || 0;
    my %stats = %{$statsRef};
    my $ret = "";
    if($type eq 'numberoffiles')
    {
        $ret = 0;
        while ( (my $filename, my $value) = each(%{$stats{'filecounts'}}) )
        {
            $ret++;
        }
        $ret .= ''; # make it a string
    }
    if($type eq 'filenames')
    {
        while ( (my $filename, my $value) = each(%{$stats{'filecounts'}}) )
        {
            $ret .= "$filename,\n";
        }
        $ret = substr($ret,0,-2);
    }
    if($type eq 'filecounts' || $type eq 'totalrecords')
    {
        my $gtotal = 0;
        while ( (my $filename, my $value) = each(%{$stats{'filecounts'}}) )
        {
            $ret .= "$filename:\n";
            my @order = ();
            while ( (my $ftype, my $count) = each(%{$value}) )
            {
                push @order, $ftype if($ftype ne 'total');
            }
            @order = sort @order;
            foreach(@order)
            {
                $ret .= "\t$_: " . $value->{$_} . "\n";
                $gtotal += $value->{$_};
            }
            $ret .= "\tTotal: " . $value->{'total'} . "\n" if($value->{'total'});
        }
        $ret = substr($ret,0,-1);
        $ret = $gtotal if($type eq 'totalrecords');
    }
    if($type =~ /^job/)
    {
        my %jobstats = %{$stats{"jobstats"}};
        $ret = $jobstats{'create_time'} if($type =~ /created/);
        $ret = $jobstats{'start_time'} if($type =~ /started/);
        $ret = $jobstats{'last_update_time'} if($type =~ /finished/);
        $ret = $jobstats{'trace'} if($type =~ /trace/);
    }
    if($type eq 'typetotalcounts')
    {
        my @order = ();
        while ( (my $itype, my $count) = each(%{$stats{'typetotalcounts'}}) )
        {
            push @order, $itype;
        }
        @order = sort @order;
        foreach(@order)
        {
            my $v = $stats{'typetotalcounts'}{$_};
            $ret .= "$_: $v\n";
        }
        $ret = substr($ret,0,-1);
    }
    if($type eq 'typeloaded')
    {
        my @order = ();
        my @suborder = ();
        my %uniqSubOrder = ();
        while ( (my $itype, my $value) = each(%{$stats{'typeloaded'}}) )
        {
            push @order, $itype;
            while ( (my $loaded, my $count) = each(%{$value}) )
            {
                push @suborder, $loaded if(!$uniqSubOrder{$loaded});
                $uniqSubOrder{$loaded} = 1 if(!$uniqSubOrder{$loaded});
            }
        }
        @order = sort @order;
        @suborder = sort @suborder;
        foreach(@order)
        {
            my $thisType = $_;
            $ret .= "$thisType:\n";
            foreach(@suborder)
            {
                $ret .= "\t$_: " . $stats{'typeloaded'}{$thisType}{$_} . "\n";
            }
        }
        $ret = substr($ret,0,-1);
    }
    

    # remove line returns when requested to be flat
    $ret =~ s/\n//g if($flat);

    if($truncateLength && length($ret) > $truncateLength)
    {
        $ret = substr($ret,0,$truncateLength);
        $ret .= '...truncated';
    }

    return $ret;
}

sub getJobStats
{
    my $self = shift;
    my %ret = ();
    my $query = "
    SELECT aj.create_time,aj.start_time,aj.last_update_time,ft.filename,ais.loaded,ais.itype,ajt.trace,count(*)
    FROM
    ".$self->{prefix} ."_job aj
    LEFT JOIN ".$self->{prefix} ."_job_trace ajt on (aj.id=ajt.job)
    LEFT JOIN ".$self->{prefix} ."_import_status ais on (aj.id=ais.job)
    LEFT JOIN ".$self->{prefix} ."_file_track ft on (ft.id=ais.file)
    WHERE
    aj.id = ?
    GROUP BY 1,2,3,4,5,6";
    my @vars = ($self->{job});
    my @results = @{$self->getDataFromDB($query, \@vars)};
    foreach(@results)
    {
        my @row = @{$_};
        my $create_time = @row[0];
        my $start_time = @row[1];
        my $last_update_time = @row[2];
        my $filename = @row[3];
        my $loaded = @row[4] ? 'loaded' : 'not loaded';
        my $itype = @row[5];
        my $jtrace = @row[6];
        my $count = @row[7];

        # jobstats
        if(!$ret{'jobstats'}) # all rows will have this same data, because there is only one job row (repeated)
        {
            my %f = (
            'create_time' => $create_time,
            'start_time' => $start_time,
            'last_update_time' => $last_update_time,
            'trace' => $jtrace
            );
            $ret{'jobstats'} = \%f;
        }

        # typetotalcounts
        if(!$ret{'typetotalcounts'})
        {
            my %f = ();
            $ret{'typetotalcounts'} = \%f;
        }
        if(!$ret{'typetotalcounts'}{$itype})
        {
            $ret{'typetotalcounts'}{$itype} = $count;
        }
        else
        {
            $ret{'typetotalcounts'}{$itype} += $count;
        }

        # filecounts
        if(!$ret{'filecounts'})
        {
            my %f = ();
            $ret{'filecounts'} = \%f;
        }
        if(!$ret{'filecounts'}{$filename})
        {
            my %f = ();
            $ret{'filecounts'}{$filename} = \%f;
        }
        if(!$ret{'filecounts'}{$filename}{'total'})
        {
            $ret{'filecounts'}{$filename}{'total'} = $count;
        }
        else
        {
            $ret{'filecounts'}{$filename}{'total'} += $count;
        }
        if(!$ret{'filecounts'}{$filename}{$itype})
        {
            $ret{'filecounts'}{$filename}{$itype} = $count;
        }
        else
        {
            $ret{'filecounts'}{$filename}{$itype} += $count;
        }

        # typeloaded
        if(!$ret{'typeloaded'})
        {
            my %f = ();
            $ret{'typeloaded'} = \%f;
        }
        if(!$ret{'typeloaded'}{$itype})
        {
            my %f = ();
            $ret{'typeloaded'}{$itype} = \%f;
        }
        if(!$ret{'typeloaded'}{$itype}{$loaded})
        {
            $ret{'typeloaded'}{$itype}{$loaded} = $count;
        }
        else
        {
            $ret{'typeloaded'}{$itype}{$loaded} += $count;
        }

    }
    return \%ret;
}

sub setData
{
    my $self = shift;
    $self->{data} = shift;
}

sub getData
{
    my $self = shift;
    return $self->{data};
}

sub fire
{
    my $self = shift;
    my $toOverride = shift;

    if( $self->{data} )
    {
        my $text = encode_utf8($self->{data});
        return 0 if (!$text);

        my $sender = Email::Send->new({mailer => 'SMTP'});
        $sender->mailer_args([Host => '127.0.0.1']);

        my $stat;
        my $err;

        my $email = Email::MIME->new($text);

        # Handle the address fields.  In addition to encoding the values
        # properly, we make sure there is only 1 each.
        for my $hfield (qw/From To Bcc Cc Reply-To Sender/)
        {
            my @headers = $email->header($hfield);
            $email->header_str_set($hfield => decode_utf8(join(',', @headers))) if ($headers[0]);
        }

        $email->header_str_set('To' => $toOverride) if($toOverride);

        # Handle the Subject field.  Again, the standard says there can be
        # only one.
        my @headers = $email->header('Subject');
        $email->header_str_set('Subject' => decode_utf8($headers[0])) if ($headers[0]);

        $email->header_set('MIME-Version' => '1.0') unless $email->header('MIME-Version');
        $email->header_set('Content-Type' => "text/plain; charset=UTF-8") unless $email->header('Content-Type');
        $email->header_set('Content-Transfer-Encoding' => '8bit') unless $email->header('Content-Transfer-Encoding');

        local $@;
        eval
        {
            $stat = $sender->send($email);
            $self->{send_status} = 'sent';
            $self->{status} = 'processed';
            $self->{send_status} = substr($stat->type, 0, 99) if($stat and $stat->type ne 'success');
            1;
        } or do
        {
            $err = shift;
            $self->{status} = 'error';
            $self->{send_status} = substr($err, 0, 99); # column only holds 100 characters
        };
        writeDB($self, 1) if !$toOverride;
        return 1 if( $self->{send_status} eq 'sent' );
    }
    return 0;
}


sub writeDB
{
    my $self = shift;
    my $sent = shift || 0;
    my $query = "UPDATE
    ".$self->{prefix}.
    "_notice_history anh
    SET
    send_status = ?,
    status = ?
    !!send_time!!
    WHERE
    id = ?";
    $query =~ s/!!send_time!!/, send_time = NOW()/g if $sent;
    $query =~ s/!!send_time!!//g if !$sent;
    my @vars =
    (
        $self->{send_status},
        $self->{status},
        $self->{noticeID}
    );
    $self->doUpdateQuery($query, undef, \@vars);
}


1;