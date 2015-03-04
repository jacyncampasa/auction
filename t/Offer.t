use Test::More;

BEGIN {
  use_ok('WyrlsX::Auction::Offer');
  use_ok('DBI');
}

my $DBI   = "DBI";

my ($DBH, $DB, $DS, $USER, $PASS ) = (undef, 'database=ppp;host=localhost;port=3306', "DBI:mysql:database=ppp;host=localhost;port=3306", "ppp", "pppppp");
$DBH = $DBI->connect( $DS, $USER, $PASS, { RaiseError => 1 } )
      or die "Can't connect to $DS: $DBH->errstr\n" ;

my $TEST_CASES = [
  # raw_input_auction_date, raw_input_amount, expected_is_unique_amount, expected_outbid_id, expected_outbid_msisdn, expected_outbid_cstamp, expected_outbid_sent_update_done
  ["2015-03-02", "5.00", 1, undef, undef, undef, 0],
  ["2015-03-02", "1.00", 0, 1, "09358465792", "", 1],
];


my $CLASS = "WyrlsX::Auction::Offer";
{
  my $o = $CLASS->new( DBH => $DBH, campaign_code => "BIDLOWQ12015" );

  foreach my $tc (@$TEST_CASES) {
    is $o->is_unique_amount($tc->[0], $tc->[1]), $tc->[2];
    is $o->_get_outbid()->{id}, $tc->[3];
    is $o->_get_outbid()->{msisdn}, $tc->[4];
    is $o->_get_outbid()->{cstamp}, $tc->[5], "unique " . $tc->[1] . " amount? " . $tc->[2];
    #is $o->set_outbid_sent(), $tc->[6];
  }
}


done_testing()
