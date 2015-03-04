package fsqd::auction_info;
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
use dbusermsg;
use File::Copy qw/move/;
use File::Basename qw/basename/;
use getoptsmini;
use WyrlsX::Auction::Info;

# Changelog:
# 2015-03-04 - jacyn
#            - initial version

# Configuration File Template

#<FSQD_AUCTION_INFO>
#    INQUEUE                 = auction_info
#    OUTQUEUE                = send_usermsg
#
#    <CAMPAIGN_CODE>
#        BIDLOWQ12015
#    </CAMPAIGN_CODE>
#
#    <<include dbh-globe-2346-ppp.rc>>
#</FSQD_AUCTION_INFO>


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

    my ( $campaign_code, $info, $param ) = split(/\s/, $x_msg_data, 3);

    die "FATAL: Campaign Code $campaign_code is not defined on PROMO_CODE rc section" if (not exists($self->config->{CAMPAIGN_CODE}->{$campaign_code}));
    my $AuctionInfo = WyrlsX::Auction::Info->new( DBH => $self->dbh, campaign_code => $campaign_code );

    my ($auction_date, $hh, $mm, $ss) = split (" ", strftime "%Y-%m-%d %H %M %S", localtime);
    die "FATAL: No Auction Item defined today! campaign_code: $campaign_code" if (not $AuctionInfo->has_item($auction_date));

    my $auction_item = $AuctionInfo->_get_item;
    my $item_name = $auction_item->{name};
    $item_name =~ s/\s/_/g;

    my ($ccmdset, $cmsgtype) = ($campaign_code, undef);
    my ($cmdtxt, $bid_amount) = (undef, 0);

    if ($info eq WyrlsX::Auction::Info::STATUS) {
        $bid_amount = $AuctionInfo->get_lowest_unique_bid($cmd{origin});

        $cmsgtype = "Status";
        $cmsgtype .= "-NoUBid" if (not $bid_amount);
        $cmdtxt = "$ccmdset $cmsgtype --LOWEST_UBIDS=$bid_amount --PRODUCT_NAME=$item_name --HH=$hh --MM=$mm --SS=$ss";
    }
    elsif ($info eq WyrlsX::Auction::Info::ITEM) {
        $cmsgtype = "ItemInfo";
        $cmdtxt = "$ccmdset $cmsgtype --PRODUCT_NAME=$item_name";
    }
    elsif ($info eq WyrlsX::Auction::Info::OUTBID) {
        $bid_amount = $OPTIONS->{AMOUNT};

        $cmsgtype = "OutbidAlert";
        $cmsgtype .= "-NoUBid" if (not $AuctionInfo->get_lowest_unique_bid($cmd{origin}));
        $cmdtxt = "$ccmdset $cmsgtype --AMOUNT=$bid_amount --PRODUCT_NAME=$item_name";
    }
    elsif ($info eq WyrlsX::Auction::Info::BIDALERT) {
        $ccmdset = "FREEBIDALERT";
        $cmsgtype = $param;
        $cmdtxt = "$ccmdset $cmsgtype --PRODUCT_NAME=$item_name";
    }
    else {
        die "Unidentified INFO: $info for campaign: $campaign_code";
    }


    $cmd{cmd} = $self->config->{OUTQUEUE};
    $cmd{txt} = $cmdtxt;
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
