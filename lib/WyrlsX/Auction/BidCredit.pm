package WyrlsX::Auction::BidCredit;
use strict;
use Moose;

has 'DBH'           => ( isa => 'Ref', is => 'rw', required => 1);
has 'campaign_code' => ( isa => 'Str', is => 'rw', required => 1);
has 'credit'        => ( isa => 'Int', is => 'ro', required => 0, default => 0, writer => '_set_credit', reader => '_get_credit', );


my $sth_get_credit = undef;
my $sth_dec_credit = undef;
my $sth_inc_credit = undef;

sub BUILD {
    my $self = shift;

    $sth_get_credit   = $self->DBH->prepare("SELECT credits 
                                                FROM auction_bidder 
                                                WHERE campaign_code = '" . $self->campaign_code . "' AND msisdn = ?;")
                                                or die "$0: FATAL: prepare failed\n";

    $sth_dec_credit   = $self->DBH->prepare("INSERT INTO auction_bidder (campaign_code, msisdn, credits, created) 
                                                VALUES ('" . $self->campaign_code . "', ?, 0, NOW()) 
                                                ON DUPLICATE KEY UPDATE credits=IF(credits>0, credits-?, 0);")
                                                or die "$0: FATAL: prepare failed\n";

    $sth_inc_credit   = $self->DBH->prepare("INSERT INTO auction_bidder (campaign_code, msisdn, credits, created) 
                                                VALUES ('" . $self->campaign_code . "', ?, 1, NOW()) 
                                                ON DUPLICATE KEY UPDATE credits=credits+?;")
                                                or die "$0: FATAL: prepare failed\n";
}


sub has_credit {
    my ($self, $msisdn) = @_;

    my $result = $sth_get_credit->execute( $msisdn ) or die "$0: get_credit() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        $self->_set_credit(0);
        return 0;
    } else {
        my $data = $sth_get_credit->fetchrow_hashref() or die "$0: get_credit() FATAL: fetchrow_hashref query failed\n";
        $self->_set_credit($data->{credits});
        return 1 if ($self->{credit} > 0);
        return 0;
    }

    return undef;
}

sub dec_credit {
    my ($self, $msisdn, $credit) = @_;
    $credit = 1 if (not defined($credit));

    my $result = $sth_dec_credit->execute( $msisdn, $credit ) or die "$0: dec_credit() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        $self->has_credit($msisdn);
        return 1;
    }

    return undef;
}

sub inc_credit {
    my ($self, $msisdn, $credit) = @_;
    $credit = 1 if (not defined($credit));

    my $result = $sth_inc_credit->execute( $msisdn, $credit ) or die "$0: inc_credit() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        $self->has_credit($msisdn);
        return 1;
    }

    return undef;
}


1;


__END__ 
