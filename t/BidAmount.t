use Test::More;

BEGIN {
  use_ok('WyrlsX::Auction::BidAmount');
}


my $TEST_CASES = [
  # raw_input, expected_is_valid, expected_amount, expected_err_code
  ["1", 1, "1.00", undef],
  ["12.", 1, "12.00", undef],
  ["1.25", 1, "1.25", undef],
  ["<12>", 1, "12.00", undef],
  ["< 12 >", 1, "12.00", undef],
  ["P12", 1, "12.00", undef],
  ["PH12", 1, "12.00", undef],
  ["PHP12", 1, "12.00", undef],
  ["12P", 1, "12.00", undef],
  ["12PH", 1, "12.00", undef],
  ["12PHP", 1, "12.00", undef],
  ["(12)", 1, "12.00", undef],
  ["( 12 )", 1, "12.00", undef],
  ["( 12 )", 1, "12.00", undef],
  ["1,200", 1, "1200.00", undef],
  ["1.2", 1, "1.20", undef],
  ["1 2", 0, undef, WyrlsX::Auction::BidAmount::INVALID_FORMAT],
  ["1.2.4.5", "0", undef, WyrlsX::Auction::BidAmount::INVALID_FORMAT],
  ["0.10", 1, "0.10", WyrlsX::Auction::BidAmount::INVALID_LT_MINIMUM],
  #["500,000.25", 1, "500000.25", WyrlsX::Auction::BidAmount::INVALID_GT_MAXIMUM],
  ["5,000,000.25", 1, "5000000.25", undef],
];



my $CLASS = "WyrlsX::Auction::BidAmount";
{
  foreach my $tc (@$TEST_CASES) {
    my $o = $CLASS->new( input => $tc->[0], minimum => 1, );
    is $o->is_valid(), $tc->[1];
    is $o->get_error, $tc->[3];
    is $o->_get_clean_input, $tc->[2], "clean_amount => " . $tc->[2];
  }

}


done_testing()
