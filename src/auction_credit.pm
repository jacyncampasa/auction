package fsqd::auction_credit;
use strict;
use FsqDaemon;
use base ('FsqDaemon');
# -----------------------------------------
use Data::Dumper;
use Carp;
use fsq;
use WyrlsX::Auction::BidCredit;

# Changelog:
# 2015-03-06 - jacyn
#            - initial version

# Configuration File Template

#<AUCTION_CREDIT>
#    INQUEUE                 = auction_credit
#    OUTQUEUE                = msgout1
#    LOG_EVENTS              = 1
#    
#    <CAMPAIGN_CODE>
#        BIDLOWQ12015
#    </CAMPAIGN_CODE>
#
#    <<include dbh_2346globe.rc>>
#</AUCTION_CREDIT>


sub setup {
    my $self = shift;

    # DBH
    $self->dbh_config(
        $self->config->{DBH}->{DATA_SOURCE},
        $self->config->{DBH}->{USER},
        $self->config->{DBH}->{PASS},
        { RaiseError => 1, AutoCommit => 1, },
    );

    # DBH dependencies 
    ($self->dbh->ping) or croak "invalid DBH handle";

    return 1;
}

sub pre_processcmd {
    my $self = shift;
    ($self->dbh->ping) or croak "invalid DBH handle";
}


sub processcmd {

    my $self = shift;
    my %cmd  = @_;
    my ( $operation, $campaign_code, $literal ) = $self->split_syntax( $cmd{txt} );

    # check campaign_code if exists in config
    die "FATAL: Campaign Code $campaign_code is not defined on CAMPAIGN_CODE rc section" if (not exists($self->config->{CAMPAIGN_CODE}->{$campaign_code}));
    $self->{_BidCredit} = WyrlsX::Auction::BidCredit->new( DBH => $self->dbh, campaign_code => uc $campaign_code, );

    my $result  = $self->execute_operation( $cmd{origin}, uc $operation, $literal );
    my $do_log_event = $self->config->{LOG_EVENTS} || 0;
    if ($do_log_event) {
        $self->log_event(
            "EVENT:BIDCREDITS:$operation:$campaign_code:$literal",
            $cmd{origin}, 
            $cmd{cstamp}, 
            $cmd{dest},
        );
    }
    
}

sub idle {

    my $self = shift;
    $self->SUPER::idle();
    ($self->dbh->ping) or croak "invalid DBH handle";

}

sub split_syntax {

    my $self        = shift;
    my $p_txt       = shift;

    ($p_txt) 
        or croak "empty parameters";

    my ( $operation, $campaign_code, $literal, @restparams ) = split (/\s+/, $p_txt);

    if(scalar(@restparams)){
        croak "extra parameters"
    }

    if((!$operation) || (!$campaign_code)) {
        croak "missing parameters";
    }

    $literal = 1 if (!defined($literal));
 
    if($operation !~ /^[a-zA-Z]+$/) {
        croak "operation is alpha only [$operation]";
    }
    
    if($campaign_code !~ /^[a-zA-Z0-9_]+$/) {
        croak "campaign_code is alphanumeric only [$campaign_code]";
    }
    
    if($literal !~ /^[0-9]+$/) {
        croak "literal is numeric only [$literal]";
    }

    return ( $operation, $campaign_code, $literal );

}

sub execute_operation {

    my $self   = shift;
    my $msisdn = shift;
    my ( $operation, $literal ) = @_;

    if(!$msisdn) {
        croak "missing msisdn";
    }

    my %operations_map = ( 
        INC => \&increment_bidcredits,
        DEC => \&decrement_bidcredits,
    );

    if(not exists $operations_map{$operation}) {
         croak "invalid operation [$operation]";
    }

    my $result = (defined($operations_map{$operation}) && (ref($operations_map{$operation}) eq 'CODE')) ?  $operations_map{$operation}->( $self, $msisdn, $literal ) : 0;

    return $result;

}

sub increment_bidcredits {
    my ( $self, $msisdn, $literal ) = @_;
    return $self->{_BidCredit}->inc_credit($msisdn, $literal);
}

sub decrement_bidcredits {
    my ( $self, $msisdn, $literal ) = @_;
    return $self->{_BidCredit}->dec_credit($msisdn, $literal);
}


=item $obj->log_event( $sig, $origin, $cstamp, $dest )

write to event log

=cut
sub log_event {
    my $self = shift;
    # TODO: add parameter checking
    my ($sig, $origin, $cstamp, $dest) = @_;
    my %lp = ();
    $lp{msgcode}        = $sig;
    $lp{cmdorigin}      = $origin;
    $lp{cstamp}         = $cstamp;
    $lp{dest}           = $dest;
    $lp{logfile}        = utils::setlogfilename() . ".event";
    utils::logtraffic( %lp );
}


1;

__END__
