#!/usr/bin/perl
#
# email.pm
#
# Requires:
#
# Mobiusutil.pm
#
#
# Blake Graham-Henderson MOBIUS blake@mobiusconsortium.org 2013-1-24
package email;

 use Email::MIME;
 use Data::Dumper;
 use Mobiusutil;

sub new {
    my $class = @_[0];
    my @a;
    my @b;

    my $self =
    {
        fromEmailAddress => @_[1],
        emailRecipientArray => \@{ @_[2] },
        notifyError => @_[3],  #true/false
        notifySuccess => @_[4],   #true/false
        confArray => \%{@_[5]},
        errorEmailList => \@a,
        successEmailList => \@b
    };
    my $mobUtil = new Mobiusutil();
    my %theseemails = %{$self->{confArray}};

    my @emails = split(/,/,@theseemails{"successemaillist"});
    for my $y(0.. $#emails)
    {
        @emails[$y]=$mobUtil->trim(@emails[$y]);
    }
    $self->{successEmailList} = \@emails;


    my @emails2 = split(/,/,@theseemails{"erroremaillist"});
    for my $y(0.. $#emails2)
    {
        @emails2[$y]=$mobUtil->trim(@emails2[$y]);
    }
    $self->{errorEmailList} =\@emails2;

    bless $self, $class;
    return $self;
}

sub send    #subject, body
{

    my $self = @_[0];
    my $subject = @_[1];
    my $body = @_[2];
    my $log = $self->{'log'};
    my $fromEmail = $self->{fromEmailAddress};
    my @additionalEmails = @{$self->{emailRecipientArray}};
    my @toEmails = ("From", $fromEmail);
    my @success = @{$self->{successEmailList}};
    my @error = @{$self->{errorEmailList}};


    if($self->{'notifyError'})
    {
        for my $r (0.. $#error)
        {
            push(@toEmails, "To");
            push(@toEmails, @error[$r]);
        }
    }

    if($self->{'notifySuccess'})
    {
        for my $r (0.. $#success)
        {
            push(@toEmails, "To");
            push(@toEmails, @success[$r]);
        }

    }

    for my $r (0.. $#additionalEmails)
    {
#   print "Adding To : ".@additionalEmails[$r]."\n";
        push(@toEmails, "To");
        push(@toEmails, @additionalEmails[$r]);
    }
    push(@toEmails, "Subject");
    push(@toEmails, $subject);
#print Dumper(@toEmails);
    my $message;

    $message = Email::MIME->create(
      header_str => [
        @toEmails
      ],
      attributes => {
        encoding => 'quoted-printable',
        charset  => 'ISO-8859-1',
      },
      body_str => "$body\n");
     my $valid=1;
     if($valid)
     {
        use Email::Sender::Simple qw(sendmail);
        sendmail($message);
     }

}

sub sendWithAttachments     #subject, body, @attachments
{
    my $self = @_[0];
    my $subject = @_[1];
    my $body = @_[2];
    my @attachments = @{@_[3]};
    use Email::Stuffer;
    my $log = $self->{'log'};
    my $fromEmail = $self->{fromEmailAddress};
    my @additionalEmails = @{$self->{emailRecipientArray}};
    my @toEmails = ();
    my @success = @{$self->{successEmailList}};
    my @error = @{$self->{errorEmailList}};


    if($self->{'notifyError'})
    {
        for my $r (0.. $#error)
        {
            push(@toEmails, @error[$r]);
        }
    }

    if($self->{'notifySuccess'})
    {
        for my $r (0.. $#success)
        {
            push(@toEmails, @success[$r]);
        }

    }
    for my $r (0.. $#additionalEmails)
    {

        push(@toEmails, @additionalEmails[$r]);
    }
    my %alreadyEmailed;

#print Dumper(@toEmails);
    foreach(@toEmails)
    {
        if(!$alreadyEmailed{$_})
        {
            $alreadyEmailed{$_}=1;
            my $message = new Email::Stuffer;
            $message->to($_)->from($fromEmail)->text_body("$body\n")->subject($subject);
            foreach(@attachments)
            {
                $message->attach_file($_);
            }
            $message->send;
        }
    }
}
1;