package WyrlsX::Auction::Info;
use strict;
use Moose;

has 'DBH'           => ( isa => 'Ref', is => 'rw', required => 1);
has 'campaign_code' => ( isa => 'Str', is => 'rw', required => 1);
has 'item'          => ( isa => 'Ref', is => 'ro', required => 0, writer => '_set_item', reader => '_get_item');

my $sth_get_item = undef;
my $sth_get_lowest_unique_bid = undef;
my $sth_get_msisdn_lowest_unique_bid = undef;

sub BUILD {
    my $self = shift;

    $sth_get_item                     = $self->DBH->prepare("SELECT * 
                                                        FROM auction_item 
                                                        WHERE campaign_code = '" . $self->campaign_code . "' AND auction_date = ?;")
                                                        or die "$0: FATAL: prepare failed\n";

    $sth_get_lowest_unique_bid        = $self->DBH->prepare("SELECT msisdn, ao.offer_amount as bid_amount, count(ab.id) as bid_count 
                                                        FROM auction_offer AS ao INNER JOIN auction_bid AS ab ON (ao.id=ab.offer_id)
                                                        WHERE ao.item_id = ? 
                                                        GROUP BY ab.offer_id
                                                        HAVING bid_count = 1
                                                        ORDER BY bid_amount ASC
                                                        LIMIT 1;")
                                                        or die "$0: FATAL: prepare failed\n";

    $sth_get_msisdn_lowest_unique_bid = $self->DBH->prepare("SELECT msisdn, ao.offer_amount as bid_amount, count(ab.id) as bid_count 
                                                        FROM auction_offer AS ao INNER JOIN auction_bid AS ab ON (ao.id=ab.offer_id)
                                                        WHERE ao.item_id = ?
                                                        GROUP BY ab.offer_id
                                                        HAVING bid_count = 1 AND ab.msisdn = ?
                                                        ORDER BY bid_amount ASC
                                                        LIMIT ?;")
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

    return 0;
}

sub get_lowest_unique_bid {
    my ($self, $msisdn, $limit) = @_;
    $limit = 1 if (!defined($limit));

    my ($result, $data);
    if (defined($msisdn)) {
        $result = $sth_get_msisdn_lowest_unique_bid->execute( $self->_get_item->{id}, $msisdn, $limit ) or die "$0: get_msisdn_lowest_unique_bid() FATAL: Unable to execute query\n";
        $data = $sth_get_msisdn_lowest_unique_bid->fetchall_hashref('bid_amount') or die "$0: get_msisdn_lowest_unique_bid() FATAL: fetchrow_hashref query failed\n";
    } 
    else {
        $result = $sth_get_lowest_unique_bid->execute( $self->_get_item->{id} ) or die "$0: get_lowest_unique_bid() FATAL: Unable to execute query\n";
        $data = $sth_get_lowest_unique_bid->fetchall_hashref('bid_amount') or die "$0: get_lowest_unique_bid() FATAL: fetchrow_hashref query failed\n";
    }

    if ($result eq '0E0') {
        return 0;
    } else {
        my $bid_amount = '';
        foreach my $row (sort keys%$data) {
            $bid_amount .= "P" . $data->{$row}->{bid_amount} . ">>";
        }
        return $bid_amount;
    }

    return undef;
}


sub STATUS { return "STATUS"; }
sub ITEM { return "ITEM"; }
sub OUTBID { return "OUTBID"; }
sub BIDALERT { return "BIDALERT"; }

1;


__END__ 
