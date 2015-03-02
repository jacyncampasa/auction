use Test::More;

BEGIN {
  use_ok('WyrlsX::Auction::BidCredit');
  use_ok('DBI');
}

my $DBI   = "DBI";

my ($DBH, $DB, $DS, $USER, $PASS ) = (undef, 'database=ppp;host=localhost;port=3306', "DBI:mysql:database=ppp;host=localhost;port=3306", "ppp", "pppppp");
$DBH = $DBI->connect( $DS, $USER, $PASS, { RaiseError => 1 } )
      or die "Can't connect to $DS: $DBH->errstr\n" ;

my $TEST_CASES = [
  # raw_input, expected_has_credit, expected_credit
  ["09358465792", 1, 1],
  ["09358465790", 0, 0],
  ["09358465791", 0, 0],
];


my $CLASS = "WyrlsX::Auction::BidCredit";
{
  my $o = $CLASS->new( DBH => $DBH );

  foreach my $tc (@$TEST_CASES) {
    is $o->has_credit($tc->[0]), $tc->[1];
    is $o->_get_credit(), $tc->[2], "msisdn => " . $tc->[0];
  }

  #is $o->inc_credit("09358465790"), 1;
  #is $o->dec_credit("09358465790"), 1;
}


done_testing()

__END__
