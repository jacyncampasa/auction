#!/usr/bin/perl
use strict;
use warnings;
use lib (
    "$ENV{HOME}/lib",
    "/home/logic/lib/",
    "/home/ppp/lib/",
    "/home/wyrls/lib/perl5",
);
use DBI;
use Config::General;
use WyrlsX::Compat::MsisdnSet;
use POSIX qw/strftime/;
use YAML qw/Dump/;
use Getopt::Long;
use File::Spec;
use YmdFile;
use Carp;
use dbusermsg;

my ( $namespace, $message_context, $date, $rcfilename ) = @ARGV;

my $OPTS = { };
my $res = GetOptions(
    'targets_file=s'    => \$OPTS->{targets_file},
    'delivery_mode=s'    => \$OPTS->{delivery_mode},
    'delivery_mode_rc=s'    => \$OPTS->{delivery_mode_rc},
    'alpha_origin=s'    => \$OPTS->{alpha_origin},
    'usermsg_params_file=s'    => \$OPTS->{usermsg_params_file},
);

my $usage = "$0 <namespace: usermsg.ccmdset> <message context: usermsg.cmsgtype> <tdate: yymmdd> <dbhrcfile> --targets_file=/full/path/to/targets-file.txt";

($namespace)
    or croak $usage;
($message_context)
    or croak $usage;
($date)
    or croak $usage;
($rcfilename)
    or croak $usage;

my %config;
{
    my %confgen_config = (
        -file               => "$rcfilename",
        -IncludeRelative    => 1,
    );
    if ($Config::General::VERSION >= 2.30) {
        # handle new config general appropriately
        $confgen_config{'-InterPolateEnv'}  = 1;
        $confgen_config{'-IncludeAgain'}    = 1;
    }
    my $objconfig = Config::General->new(%confgen_config);
    %config = $objconfig->getall;
}

my $LOG_DIR = File::Spec->catdir( $ENV{HOME}, 'log' );
my $ext = join('.', 'usermsg_push', 'sent');

my $dbh = DBI->connect(
    $config{DBH}->{DATA_SOURCE},
    $config{DBH}->{USER},
    $config{DBH}->{PASS},
    { RaiseError => 1 },
);

my $minpts;

$cmd::DBH = $dbh;


my $sender;
my $delivery_mode_set = 0;
my $now = strftime("%y%m%d", localtime());
my $mmdd = strftime("%m/%d", localtime());
my $yymm = unpack( 'a4', $now);
my $dotsent = File::Spec->catfile( $LOG_DIR, $yymm, $now . "." . lc(join("-", ($namespace,$message_context))) . "." . $ext );

my $subscribers = filter_dotsent( get_targets( $OPTS->{targets_file} ) ); 

if($OPTS->{delivery_mode}){
    require UNIVERSAL::require;
    ( $OPTS->{delivery_mode}->use )
        or croak "$0: failed to use: " . $OPTS->{delivery_mode} . "\n";

    $sender = $OPTS->{delivery_mode}->new(
        config => $OPTS->{delivery_mode_rc},
        signature_field2 => $namespace,
        dotsent => $dotsent,
    );
    $delivery_mode_set = 1;
}

my $USERMSG_PARAMS;
if ($OPTS->{usermsg_params_file}) {
    $USERMSG_PARAMS = get_usermsg_params($OPTS->{usermsg_params_file});
}

# my $min_counter =0;
while ( defined(my $msisdn = $subscribers->each) ){
 
    my @msg_bundle;
    my @usrmsgs = ();
    my @user_messages = dbusermsg::get3usermessage( $namespace, $message_context );
    (length(join('',@user_messages))>0)
	or croak "fatal: missing usermsg entries for ccmdset=[" . $namespace . "] cmsgtype=[" . $message_context . "]";

    foreach my $msg (@user_messages)
    {
        my $pts      = sprintf("%d", $minpts->{$msisdn} || 0) ;
        my $amount     = sprintf("%s", $minpts->{$msisdn} || 0) ;
    	$msg =~ s/{PTS}/$pts/;
    	$msg =~ s/{POINTS}/$pts/;
    	$msg =~ s/{XX}/$pts/;
    	$msg =~ s/{AMOUNT}/$amount/;
    	$msg =~ s/{MM\/DD}/$mmdd/;
    	$msg =~ s/{DATE}/$mmdd/;

        if(defined($USERMSG_PARAMS)){
            foreach my $key ( keys %{$USERMSG_PARAMS} ) {
                my $var = '{' . uc($key) . '}';
                $msg =~ s/$var/$USERMSG_PARAMS->{$key}/g;
            }
        }

	    push (@usrmsgs,$msg);
    }

    my %msg = (
        msisdn => $msisdn,
        messages => { # description => [ messages ]
            $message_context  => {
                parts  => [ @usrmsgs ],
            },
        }
    );

    if ($OPTS->{alpha_origin}) {
        $msg{messages}->{$message_context}->{alpha_origin} = $OPTS->{alpha_origin};
    }

    push @msg_bundle, { %msg };

    if ($delivery_mode_set){
	$sender->process(
           @msg_bundle,
        );
    } else {
    	print Dump( @msg_bundle ) . "\n";
    }
   
    # $min_counter++;
    # waitlessqueue 
    # system "/home/logic/sbin/waitlessqueuescheck.sh" if ( ( $min_counter % 5000 ) == 0 ); 

}

# ----------------------------------------------------------------------------------------------

sub get_targets {
    my $file = shift; 
    my $t = WyrlsX::Compat::MsisdnSet->new;
    if((not -e $file) or (not -f $file)){
        croak "Error: invalid targets file=[" . $file . "]";
    }
    my @t = ();
    open( my $fh, "<$file" ) or croak "Error: unable to open file: $!";
    while(defined(my $line = <$fh>)){
        chomp $line;
    	my ($min, $pts) = split ('\s', $line);
    	if($min =~ /^\+?(63|0)\d{10}$/) {
            $t->insert( $min ); 
	    $minpts->{$min} = $pts;
        }
        else {
            warn "msisdn=[" . $min . "] ignored, leading or trailing space perhaps?";
            next;
        }
    }
    close ($fh); 
    return $t;
}

sub get_usermsg_params {

    my $file = shift;
    if((not -e $file) or (not -f $file)){
        croak "Error: invalid usermsg_params file=[" . $file . "]";
    }
    
    my $usermsg_params = ();
    open( my $fh, "<$file" ) or croak "Error: unable to open file: $!";
    while(defined(my $line = <$fh>)){
        chomp $line;
    	my ($key, $value) = split ('=', $line);
        next if (!$key);

        $value = '' if (!defined($value));
        $usermsg_params->{$key} = $value;
    }
    close ($fh); 
    return $usermsg_params;
}

sub filter_dotsent {
    my $targets = shift;
    my $in_sent = WyrlsX::Compat::MsisdnSet->new;
    my $now = strftime("%y%m%d", localtime());
    my $yymm = unpack( 'a4', $now);
    my $logfile = $dotsent; 
    {
        no warnings;
        open ( my $fh, "<$logfile" );
        while(defined(my $msisdn=<$fh>)){
            chomp $msisdn;
            $in_sent->insert( $msisdn ); 
        }
        close $fh;
    }
    my $clean_targets = $targets->subtract_set( $in_sent );
    return $clean_targets;
}

sub append_to_dotsent {
    my $msisdn = shift;
}

