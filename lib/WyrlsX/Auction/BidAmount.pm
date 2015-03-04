package WyrlsX::Auction::BidAmount;
use strict;
use Moose;

has 'input'          => ( isa => 'Str', is => 'rw', required => 1, );
has 'minimum'        => ( isa => 'Int', is => 'rw', required => 1, );
has 'maximum'        => ( isa => 'Int', is => 'rw', required => 0, );
has 'clean_input'    => ( isa => 'Str', is => 'ro', required => 0, writer => '_set_clean_input', reader => '_get_clean_input', );


sub is_valid {
    my ($self) = @_;

    my $clean_amount = $self->input;
    $clean_amount =~ s/(<|\(|>|\)|PHP|PH|P)//gi;
    $clean_amount =~ s/^\s+//g;
    $clean_amount =~ s/\s+$//g;

    if ($clean_amount !~ m/^[,\d]+(\.)?(\d{1,2})?$/) {
    #if ($clean_amount !~ m/^\d+(|\,\d+)(|\.|\.(\d{1}|\d{2}))$/) {
        return 0;
    }

    $clean_amount =~ s/,//g;
    $self->_set_clean_input(sprintf("%.2f", $clean_amount));

    return 1;
}

sub INVALID_LT_MINIMUM { return 4001 }
sub INVALID_GT_MAXIMUM { return 4002 }
sub INVALID_FORMAT { return 4003 }

sub get_error {
    my ($self) = @_;

    return INVALID_FORMAT() if (not $self->is_valid());

    if (defined($self->_get_clean_input)) {
        return INVALID_LT_MINIMUM() if ($self->_get_clean_input < $self->minimum);
        return INVALID_GT_MAXIMUM() if ($self->maximum && $self->_get_clean_input > $self->maximum);
    }

    return undef;
}


1;


__END__ 
