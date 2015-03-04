package WyrlsX::Auction::Offer;
use strict;
use Moose;

has 'DBH'           => ( isa => 'Ref', is => 'rw', required => 1);
has 'campaign_code' => ( isa => 'Str', is => 'rw', required => 1);

has 'item'          => ( isa => 'Ref', is => 'ro', required => 0, writer => '_set_item', reader => '_get_item');
has 'offer'         => ( isa => 'Ref', is => 'ro', required => 0, writer => '_set_offer', reader => '_get_offer');
has 'offer_amount'  => ( isa => 'Num', is => 'ro', required => 0, writer => '_set_offer_amount', reader => '_get_offer_amount');
has 'outbid'        => ( isa => 'Ref', is => 'ro', required => 0, writer => '_set_outbid', reader => '_get_outbid');


my $sth_get_item = undef;
my $sth_get_offer = undef;
my $sth_get_outbid = undef;
my $sth_update_outbid = undef;
my $sth_insert_offer = undef;
my $sth_insert_bid = undef;


sub BUILD {
    my $self = shift;


    $sth_get_item       = $self->DBH->prepare("SELECT * 
                                                FROM auction_item 
                                                WHERE campaign_code = '" . $self->campaign_code . "' AND auction_date = ?;")
                                                or die "$0: FATAL: prepare failed\n";

    $sth_get_offer      = $self->DBH->prepare("SELECT *
                                                FROM auction_offer
                                                WHERE item_id = ? AND offer_amount = ?;")
                                                or die "$0: FATAL: prepare failed\n";

    $sth_get_outbid     = $self->DBH->prepare("SELECT id, msisdn, cstamp
                                                FROM auction_bid 
                                                WHERE offer_id = ? AND is_first = 1 AND is_outbid_sent is NULL;")
                                                or die "$0: FATAL: prepare failed\n";

    $sth_update_outbid  = $self->DBH->prepare("UPDATE auction_bid SET is_outbid_sent = 1
                                                WHERE id = ?;")
                                                or die "$0: FATAL: prepare failed\n";

    $sth_insert_offer   = $self->DBH->prepare("INSERT INTO auction_offer (item_id, offer_amount, created) VALUES (?, ?, NOW())") 
                                                or die "$0: FATAL: prepare failed\n";

    $sth_insert_bid     = $self->DBH->prepare("INSERT INTO auction_bid (offer_id, msisdn, cstamp, is_first, created) VALUES (?, ?, ?, ?, NOW())") 
                                                or die "$0: FATAL: prepare failed\n";


}


sub has_item {
    my ($self, $auction_date) = @_;

    $self->_set_item({});
    
    my $result = $sth_get_item->execute( $auction_date ) or die "$0: get_item() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        my $data = $sth_get_item->fetchrow_hashref() or die "$0: get_item() FATAL: fetchrow_hashref query failed\n";
        $self->_set_item($data);
        return 1;
    }

    return undef;
}


sub set_offer_data {
    my ($self) = @_;

    $self->_set_offer({});

    my $result = $sth_get_offer->execute( $self->_get_item->{id}, $self->_get_offer_amount ) or die "$0: get_offer() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        my $data = $sth_get_offer->fetchrow_hashref() or die "$0: get_offer() FATAL: fetchrow_hashref query failed\n";
        $self->_set_offer($data);
        return 1;
    }

    return undef;

}


sub set_outbid_data {
    my ($self) = @_;

    my $result = $sth_get_outbid->execute( $self->_get_offer->{id} ) or die "$0: get_outbid() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return {};
    } else {
        my $data = $sth_get_outbid->fetchrow_hashref() or die "$0: get_outbid() FATAL: fetchrow_hashref query failed\n";
        $self->_set_outbid($data);

        return $data;
    }

    return undef;
}


sub is_unique_amount {
    my ($self, $auction_date, $amount) = @_;

    return undef if (not $self->has_item($auction_date));
    $self->_set_offer_amount($amount);

    return undef if (not defined ($self->_get_item));

    $self->_set_outbid({});

    if ($self->set_offer_data()) {
        $self->set_outbid_data();
        return 0;
    }

    return 1;
}

sub add_offer {
    my ($self) = @_;

    my $result = $sth_insert_offer->execute( $self->_get_item->{id}, $self->_get_offer_amount ) or die "$0: add_offer() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        $self->set_offer_data();
        return 1;
    }

    return undef;
}

sub add_bid {
    my ($self, $msisdn, $cstamp, $is_first) = @_;

    my $result = $sth_insert_bid->execute( $self->_get_offer->{id}, $msisdn, $cstamp, $is_first ) or die "$0: add_bid() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        return 1;
    }

    return undef;

}

sub set_outbid_sent {
    my ($self) = @_;

    my $result = $sth_update_outbid->execute( $self->_get_outbid->{id} ) or die "$0: set_outbid_sent() FATAL: Unable to execute query\n";
    if ($result eq '0E0') {
        return 0;
    } else {
        return 1;
    }

    return undef;
}

1;


__END__ 
