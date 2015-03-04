package fsqd::auction_offer;
use strict;
use FsqDaemon;
use base ('FsqDaemon');
# -----------------------------------------
use Data::Dumper;
use POSIX qw(strftime);  
use cmd;
use Carp;
use fsq;
use csp;
use utils;
use dbusermsg;
use File::Copy qw/move/;
use File::Basename qw/basename/;
use getoptsmini;
use WyrlsX::Auction::Offer;
use WyrlsX::Auction::Info;

# Changelog:
# 2015-03-04 - jacyn
#            - initial version

# Configuration File Template

#<FSQD_AUCTION_OFFER>
#    INQUEUE                 = offer_amount
#    OUTQUEUE                = send_usermsg
#    OUTBID_CMDHOOK          = auction_info
#    
#    <CAMPAIGN_CODE>
#        BIDLOWQ12015
#    </CAMPAIGN_CODE>
#
#    <<include dbh-globe-2346-ppp.rc>>
#</FSQD_AUCTION_OFFER>

sub setup {
    my $self = shift;

    $self->dbh_config(
        $self->config->{DBH}->{DATA_SOURCE},
        $self->config->{DBH}->{USER},
        $self->config->{DBH}->{PASS},
        { RaiseError => 1, AutoCommit => 1, },
    );

    # DBH dependencies 
    ($self->dbh->ping) or croak "invalid DBH handle";
    $dbusermsg::DBH = $self->dbh;

    return 1;
}

sub pre_processcmd {
    my $self = shift;
    ($self->dbh->ping) or croak "invalid DBH handle";
}


sub processcmd {

    my $self = shift;
    my %cmd  = @_;

    $cmd{txt} =~ s[\(][]g;
    $cmd{txt} =~ s[\)][]g;
    $cmd{txt} =~ s[\$][]g;

    my ($x_msg_data, $OPTIONS) = getoptsmini::getoptions( $cmd{txt} );
    $x_msg_data =~ s/^\s+//g;
    $x_msg_data =~ s/\s+$//g; 

    my ( $campaign_code, $param ) = split(/\s/, $x_msg_data, 2);

    die "FATAL: Campaign Code $campaign_code is not defined on PROMO_CODE rc section" if (not exists($self->config->{CAMPAIGN_CODE}->{$campaign_code}));
    my $AuctionOffer = WyrlsX::Auction::Offer->new( DBH => $self->dbh, campaign_code => $campaign_code );

    my ($auction_date, $hh, $mm, $ss) = split (" ", strftime "%Y-%m-%d %H %M %S", localtime);
    die "FATAL: No Auction Item defined today! campaign_code: $campaign_code" if (not $AuctionOffer->has_item($auction_date));
    my $auction_item = $AuctionOffer->_get_item;
    my $item_name = $auction_item->{name};
    $item_name =~ s/\s/_/g;

    my $bid_amount = $OPTIONS->{amount};

    my ($ccmdset, $cmsgtype) = ($campaign_code, undef);
    my $is_first = 0;
    if (not $AuctionOffer->is_unique_amount($auction_date, $bid_amount)) {

        # send outbid info msg
        my $outbid = $AuctionOffer->_get_outbid;
        if (defined($outbid->{id})) {
            $AuctionOffer->set_outbid_sent();

            my $INFO = WyrlsX::Auction::Info::OUTBID;
            my %cmdhook = %cmd;
            $cmdhook{origin}        = $outbid->{msisdn};
            $cmdhook{dest}          = $outbid->{msisdn};
            $cmdhook{cstamp}        = utils::getstamp();
            $cmdhook{cmd}           = $self->config->{OUTBID_CMDHOOK};
            $cmdhook{txt}           = "$campaign_code $INFO --AMOUNT=P$bid_amount";
            fsq::putcmdfile( %cmdhook );
        }

        $cmsgtype = "NonWinning";
        $cmsgtype .= "-".$OPTIONS->{cmsgtype_suffix} if (defined($OPTIONS->{cmsgtype_suffix}) && $OPTIONS->{cmsgtype_suffix} ne '');

        $AuctionOffer->add_bid($cmd{origin}, $cmd{cstamp}, $is_first);

        $cmd{cmd} = $self->config->{OUTQUEUE};
        $cmd{txt} = "$ccmdset $cmsgtype --AMOUNT=P$bid_amount --PRODUCT_NAME=$item_name --HH=$hh --MM=$mm --SS=$ss";
        fsq::putcmdfile( %cmd );
        return;
    }

    $is_first = 1;
    $AuctionOffer->add_bid($cmd{origin}, $cmd{cstamp}, $is_first) if ($AuctionOffer->add_offer());

    $cmsgtype = "Winning";
    $cmsgtype .= "-".$OPTIONS->{cmsgtype_suffix} if (defined($OPTIONS->{cmsgtype_suffix}) && $OPTIONS->{cmsgtype_suffix} ne '');
 
    $cmd{cmd} = $self->config->{OUTQUEUE};
    $cmd{txt} = "$ccmdset $cmsgtype --AMOUNT=P$bid_amount --PRODUCT_NAME=$item_name --HH=$hh --MM=$mm --SS=$ss";
    fsq::putcmdfile( %cmd );
}

sub idle {
    my $self = shift;
    $self->SUPER::idle();
    ($self->dbh->ping) or croak "invalid DBH handle";
    $dbusermsg::DBH = $self->dbh;
}

1;

__END__
