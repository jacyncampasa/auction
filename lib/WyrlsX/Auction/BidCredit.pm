package WyrlsX::Auction::BidCredit;
use strict;
use Moose;

has 'DBH'       => ( isa => 'Ref', is => 'rw', required => 1);
has 'credit'    => ( isa => 'Int', is => 'ro', required => 0, default => 0, writer => '_set_credit', reader => '_get_credit', );


my $sth_get_credit = undef;
my $sth_dec_credit = undef;
my $sth_inc_credit = undef;

sub BUILD {
    my $self = shift;

    $sth_get_credit   = $self->DBH->prepare("SELECT * FROM bidder WHERE msisdn = ?;");
    $sth_dec_credit   = $self->DBH->prepare("INSERT INTO bidder (msisdn) VALUES (?) ON DUPLICATE KEY UPDATE credits=IF(credits>0, credits-1, 0);");
    $sth_inc_credit   = $self->DBH->prepare("INSERT INTO bidder (msisdn) VALUES (?) ON DUPLICATE KEY UPDATE credits=credits+1;");
}


sub has_credit {
    my ($self, $msisdn) = @_;

    my $rc = $sth_get_credit->execute( $msisdn ) or die "$0: get_credit() FATAL: Unable to execute query\n";
    if ($rc eq '0E0') {
        $self->_set_credit(0);
        return 0;
    } else {
        my $href = $sth_get_credit->fetchrow_hashref() or die "$0: get_credit() FATAL: fetchrow_hashref query failed\n";
        $self->_set_credit($href->{credits});
        return 1 if ($href->{credits} > 0);
        return 0;
    }

    return undef;
}

sub dec_credit {
    my ($self, $msisdn) = @_;

    my $rc = $sth_dec_credit->execute( $msisdn ) or die "$0: dec_credit() FATAL: Unable to execute query\n";
    if ($rc eq '0E0') {
        return 0;
    } else {
        return 1 if $self->has_credit($msisdn);
        return 0;
    }

    return undef;
}

sub inc_credit {
    my ($self, $msisdn) = @_;

    my $rc = $sth_inc_credit->execute( $msisdn ) or die "$0: inc_credit() FATAL: Unable to execute query\n";
    if ($rc eq '0E0') {
        return 0;
    } else {
        return 1 if $self->has_credit($msisdn);
        return 0;
    }

    return undef;
}


1;


__END__ 
