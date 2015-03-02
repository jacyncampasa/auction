use Test::More;

BEGIN {
  use_ok('WyrlsX::Auction::Info');
  use_ok('DBI');
}

my $DBI   = "DBI";

my ($DBH, $DB, $DS, $USER, $PASS ) = (undef, 'database=ppp;host=localhost;port=3306', "DBI:mysql:database=ppp;host=localhost;port=3306", "ppp", "pppppp");
$DBH = $DBI->connect( $DS, $USER, $PASS, { RaiseError => 1 } )
      or die "Can't connect to $DS: $DBH->errstr\n" ;

my $TEST_CASES = [
  # raw_input_auction_date, raw_input_msisdn, expected_item_name, expected_lowest_unique_bid
  ["2015-03-02", "09358465792", "Iphone", "P2.00|", "P2.00|P3.00|"],
  ["2015-03-01", "09358465790", "", 0, 0],
];


my $CLASS = "WyrlsX::Auction::Info";
{
  my $o = $CLASS->new( DBH => $DBH, campaign_code => "BIDLOWQ12015" );

  foreach my $tc (@$TEST_CASES) {
    is $o->get_item($tc->[0]), $tc->[2];
    is $o->get_lowest_unique_bid(), $tc->[3];
    is $o->get_lowest_unique_bid($tc->[1]), $tc->[4], "auction_date => " . $tc->[0];
  }
}


done_testing()


# Check
