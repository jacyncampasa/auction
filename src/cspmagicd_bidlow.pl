#!/usr/bin/perl -w

use strict;
use Time::HiRes qw( usleep );
use POSIX;

use lib ( 
    "$ENV{HOME}/lib", "/home/wyrls/lib" 
);

use cmd;
use dbusermsg;
use tc;

use fsq; 
use utils;
use csp;
use franchise;
use WyrlsX::Franchise::Factory;
use WyrlsX::Auction::BidAmount;
use WyrlsX::Auction::BidCredit;

# debug
use Data::Dumper;

# wrapper for Config::General
use ezconfig qw( getConfigSection unlessDefinedDefaultsTo );
# common queue processing routines
use smscmd;
use autosubs;
use getoptsmini;
use vartable;
use blacklisted;
use VarCaps;

# ----------------
# RC configuration
# ----------------
my ($rcsection, $rcfilename, $homepath) = @ARGV;
unless ( defined($rcfilename) and defined($rcsection) ) { die "Usage: $0 <RCSECTION> <RCFILE> [<HOMEPATH>]\n"; }
my $HOMEPATH      = defined($homepath) ? $homepath : $ENV{HOME};
my $phxconf       = getConfigSection({ file=>"$HOMEPATH/etc/$rcfilename", section=>$rcsection });
my %xconf         = (ref($phxconf) eq 'HASH') ? (%$phxconf) : ();

# critical config params
my $CMDDIR            = unlessDefinedDefaultsTo( $xconf{CMDDIR},         '' );
$fsq::SENDDIR         = unlessDefinedDefaultsTo( $xconf{SENDDIR},        '' );
my $LOGDIR            = unlessDefinedDefaultsTo( $xconf{LOGDIR},         '' );
my $ACCESS_NO         = unlessDefinedDefaultsTo( $xconf{ACCESS_NO},      '' );
my $TRIGGER_ONTOON    = unlessDefinedDefaultsTo( $xconf{TRIGGER_ONTOON}, '' );

my $PROMO_CODE        = unlessDefinedDefaultsTo( $xconf{PROMO_CODE}, '' );
my $PROMO_CAP_VARNAME = unlessDefinedDefaultsTo( $xconf{PROMO_CAP_VARNAME}, '' );
my $PROMO_CAP_VALUE   = unlessDefinedDefaultsTo( $xconf{PROMO_CAP_VALUE}, '' );

my $PROMO_PAID_COMMAND= unlessDefinedDefaultsTo( $xconf{PROMO_PAID_COMMAND}, '' );
my $HOOK_COMMAND      = unlessDefinedDefaultsTo( $xconf{HOOK_COMMAND}, '' );
my $CHGWRAP_COMMAND   = unlessDefinedDefaultsTo( $xconf{CHGWRAP_COMMAND}, '' );
my $CHGWRAP_TARIFF    = unlessDefinedDefaultsTo( $xconf{CHGWRAP_TARIFF}, '' );


my $PROMO_ENDED       = unlessDefinedDefaultsTo( $xconf{PROMO_ENDED}, 0 );

my $UAT_MODE                    = unlessDefinedDefaultsTo( $xconf{UAT_MODE}, 0 );
my %WHITELISTED = ();
%WHITELISTED                    = %{$xconf{WHITELISTED}} if defined($xconf{WHITELISTED});

my $CSP_TXID_PREFIX      = '';

my %SUBSCRIPTIONS = ();
%SUBSCRIPTIONS    = %{$xconf{SUBSCRIPTIONS}} if defined($xconf{SUBSCRIPTIONS});

$franchise::FRANCHISE   = $xconf{TELCOFRANCHISE};

if (length $ACCESS_NO  <= 0) { die "Param [ACCESS_NO] not specified in config $rcsection "; }
if (length $CMDDIR     <= 0) { die "Param [CMDDIR] not specified in config $rcsection "; }
if (length $SENDDIR    <= 0) { die "Param [SENDDIR] not specified in config $rcsection "; }

my $ORIGIN_MASKED              = $ACCESS_NO;
# CSP Configuration
# ===============================================================================
my %CSPKEYWORDS                = %{$xconf{CSPKEYWORDS}} if defined($xconf{CSPKEYWORDS});
my %CSPK_PULL_INFOTEXT         = %{$CSPKEYWORDS{PULL_INFOTEXT}} if (defined($CSPKEYWORDS{PULL_INFOTEXT}));
my %CSPK_PULL_FREEINFOTEXT     = %{$CSPKEYWORDS{PULL_FREEINFOTEXT}} if (defined($CSPKEYWORDS{PULL_FREEINFOTEXT}));
unless ((%CSPK_PULL_INFOTEXT) && (%CSPK_PULL_FREEINFOTEXT)) {
    die "$0: FATAL: Error in CSPKEYWORDS section configuration\n";
}
# switch to enable CSP-style tariffing
$tc::CSPSMS = 1;
my %TCX = (); # media content TC_x wrapper, usually charged, can also be free, e.g. OFF tariffs
my %TCD = tc::gettc( deftc => $TC_D{TC}, defsd => $TC_D{SD}, primary => $CSPK_PULL_INFOTEXT{TC}, secondary => $CSPK_PULL_INFOTEXT{SD} );
my %TCC = tc::gettc( deftc => $TC_C{TC}, defsd => $TC_C{SD}, primary => $CSPK_PULL_FREEINFOTEXT{TC}, secondary => $CSPK_PULL_FREEINFOTEXT{SD} );
# ===============================================================================


# day of the week suffixes constants (WKFRQ)
my @DOWSUFFIX = qw( SUN M T W TH F SAT );

# --------------------
#  init core libs
# --------------------
autosubs::init( $DBH );
vartable::init( $DBH );
blacklisted::init( $DBH );
$dbusermsg::DBH = $DBH;
fsq::initqueues( $HOMEPATH );
utils::initlogs( $HOMEPATH );

# TODO: this is for compatibility only between smscmd.pm and the new (csp-style) fsq.pm
$fsq::QUEUEPATH = $HOMEPATH . '/' . $fsq::QUEUEDIR;

my $franchise = WyrlsX::Franchise::Factory->new(
    "RCFile",
     config => { rcfile => "$HOMEPATH/etc/franchise.rc" },
);

my $bid_credit = WyrlsX::Auction::BidCredit->new( DBH => $DBH, campaign_code => $PROMO_CODE );


# --------------------
#  process loop
# --------------------

# FIXME: BRUTE FORCE synchronization: WE REQUIRE that all subscriptions have been PROCESSED
use DirHandle;
my $magic_queues_to_wait = sub {
    my $varpath = "$HOMEPATH/var";
    my @qs = qw(
        subscribe 
    );
    my $totalq = 0;
    foreach my $q (@qs) {
        my $queuepath = join ("/", $varpath, $q );
        my $dh = DirHandle->new( $queuepath )
            or die $!;
        my $c = 0;
        while (defined($_ = $dh->read)) {
            $c++ unless (/^\./);
            last if ($c>0);
        }
        $totalq += $c;
    }
    return $totalq;
};


# =================================

#    while (1) {
#        $DBH->ping or die "$0: @ARGV: Stale Database Connection: ".$DBI::err."\n";
#    	ezqp::process_queue( "$HOMEPATH/var/$CMDDIR", \&message_logic );
#    	sleep 1;
#    }

    do {
        $DBH->ping or die "$0: @ARGV: Stale Database Connection: ".$DBI::err."\n";
        smscmd::processcmds( $CMDDIR, \&message_logic );
        sleep 2;
    } while (!$utils::QUIT);



# =====================================




# message_logic( $fullpath_queue_filename, \%queue_message
# - callback subroutine, application logic for processing each and every message
sub message_logic {

    {
        my $timestart = time();
        while (my $q = $magic_queues_to_wait->()) {
            print STDERR "waiting ($q)...\n" if ($ENV{DEBUG});
            last if ($q == 0);
            usleep 100_000;
            my $timeelapsed = time() - $timestart;
            if ($timeelapsed > 300) {
                die "FATAL $0: Please check subscribe queues\n";
            }
        }
    }

    
    my %p = @_;
    my $pqmsg  = \%p;
    my ( $msg_type, $msg_origin, $msg_cstamp, $msg_data, $msg_dest, $msg_msc, $msg_smsc, $msgid ); 
    $msg_origin  = unlessDefinedDefaultsTo( $pqmsg->{origin}, '' );
    $msg_cstamp  = unlessDefinedDefaultsTo( $pqmsg->{cstamp}, '' );
    $msg_data    = unlessDefinedDefaultsTo( $pqmsg->{txt},   '' );
    $msg_dest    = unlessDefinedDefaultsTo( $pqmsg->{dest},   '' );
    $msg_smsc    = unlessDefinedDefaultsTo( $pqmsg->{smsc},   '' );
    $msgid       = unlessDefinedDefaultsTo( $pqmsg->{msgid},      '' );

    my $SIGCOMMAND = $PROMO_CODE;

    if ($PROMO_ENDED) {
        my %p_cmd = (
            origin => "$msg_origin",	
            cstamp => "$msg_cstamp",
            dest   => "$msg_dest",
            smsc   => "$msg_smsc",
            msgid  => "$msgid",
            );       

        $p_cmd{cmd} = "send_usermsg";
        $p_cmd{txt} = "$PROMO_CODE closing_message";
        fsq::putcmdfile( %p_cmd );
        return 1;
    }

    print STDERR "processing request: origin=",$pqmsg->{origin}," txt=",$pqmsg->{txt},"\n" if ($ENV{DEBUG});
   
    my $infile = $pqmsg->{file}; 
    my $param  = utils::trim( $msg_data );
    my $switch = '';
    my $status = '';

    if ($UAT_MODE) {
        if (not exists($WHITELISTED{$msg_origin})) {
           print STDERR "request cancelled: origin=",$pqmsg->{origin}," uat_mode enabled \n" if ($ENV{DEBUG});
           unlink $infile;
           return 1; 
        }
    }
    
    # strip options
    my ( $x_param, $OPTIONS ) = getoptsmini::getoptions( $param );
    my $OPTS  .= ($OPTIONS->{'nocontent'}) ? ' --nocontent' : '';
    $OPTS .= ($OPTIONS->{'notextback'}) ? ' --notextback' : '';
    $OPTS .= ($OPTIONS->{'silentoptin'}) ? ' --silentoptin' : '';
    # add ref_code on subscription subscription OPT 111010 (for media ccmdhook) AFTM
    $OPTS .= ($OPTIONS->{'refcode'}) ? "--hook_param_refcode=$OPTIONS->{'refcode'} ": '';

    my $OPTS_REF = ($OPTIONS->{'referrer'}) ? $OPTIONS->{'referrer'} : ''; 
    $TRIGGER_ONTOON = 0 if defined($OPTIONS->{'silentontoon'});

    $param = $x_param;

    my @automediacname = split /\s+/, $param;
    
    my $lastautomediaid = undef;
    my $triggerontoon   = $TRIGGER_ONTOON;

    my ($cstamp_hhmm)   = ($msg_cstamp =~ /^\d{6}(\d{4})/);
    my $start_time='0700';
    my $end_time='2359';

    # TEST NOT PROMO HOURS -- ADD MSGORIGIN
    if ( $msg_origin eq "09355509492" || $msg_origin eq "09358465792" ){
       $start_time='0000';
       $end_time='2359';
    }
     
    #BLACKLISTED FILTER
    my $blacklisted_is_enabled = 0; 
    $blacklisted_is_enabled = blacklisted::get_value( $SIGCOMMAND, $msg_origin );
    $blacklisted_is_enabled = 0 if(!defined($blacklisted_is_enabled)); 
    if ( $blacklisted_is_enabled ne '1' ) { 

        #TIME FILTER
        if ( ($cstamp_hhmm >= $start_time ) && ($cstamp_hhmm <= $end_time ) ) { 

            my $fd;
            eval {
                $fd = $franchise->get_franchise($msg_origin);
            };
            if($@){
                my $e = $@;
                if (blessed($e) and $e->isa('Exception::Class::Base')) {
                    # special handling for Exception::Class types
                    print ( ref($e) . ": " . $e->description() );
                }
                else {
                    print( "$@" );
                }
                return;
            }
         
            my $franchise_type = $fd->type();
            if ( ($msg_origin eq "09178680114") ){
                $franchise_type = "PREPAID";
            }

            #PREPAID FILTER
            if ( $franchise_type eq "PREPAID" ) {

                # BID AMOUNT Check
                my $BID_AMOUNT;
                {   
                    my %p_cmd = (
                        origin => "$msg_origin",	
                        cstamp => "$msg_cstamp",
                        dest   => "$msg_dest",
                        smsc   => "$msg_smsc",
                        msgid  => "$msgid",
                    );

                    my $raw_input   = unlessDefinedDefaultsTo( $OPTIONS->{'bid_amount'}, '' );
                    {
                        my $CLASS = "WyrlsX::Auction::BidAmount";
                        my $bid_amount = $CLASS->new( input => $raw_input, minimum => 1, );
                        if (not $bid_amount->is_valid()) {
                            #TODO: send proper msg
                            my $error = $bid_amount->get_error;
                            if ($error == WyrlsX::Auction::BidAmount::INVALID_LT_MINIMUM) {
                                # send less than minimum
                                $p_cmd{cmd} = "send_usermsg";
                                $p_cmd{txt} = "$PROMO_CODE amount_lt_minimum";
                                fsq::putcmdfile( %p_cmd );
                            }
                            elsif ($error == WyrlsX::Auction::BidAmount::INVALID_FORMAT) {
                                # send invalid amount
                                $p_cmd{cmd} = "send_usermsg";
                                $p_cmd{txt} = "$PROMO_CODE amount_invalid_format";
                                fsq::putcmdfile( %p_cmd );
                            }
                            return;
                        }
                        $BID_AMOUNT = $bid_amount->_get_clean_input;
                    }

                    if ($bid_credit->has_credit($msg_origin)) {
                        if ($bid_credit->dec_credit($msg_origin)) {
                            # Hook Bid Amount
                            $p_cmd{cmd} = $HOOK_COMMAND;
                            $p_cmd{txt} = "$PROMO_CODE --amount=$BID_AMOUNT";
                            fsq::putcmdfile( %p_cmd );
                        }
                        return;
                    }
                }

                # MAGIC / TRY
                foreach my $ac (@automediacname) {
                    my ($xsvcsection, $cname) = split /:/, $ac;
                    my $svcsection = uc( $xsvcsection );
                    
                    unless (ref($SUBSCRIPTIONS{$svcsection}) eq 'HASH') { die "$0: FATAL: Subscription Section Not Found\n" . Dumper( $pqmsg ); }
                    my %xconf   = %{$SUBSCRIPTIONS{$svcsection}};
                    
                    # required automedia specific params
                    my $COMMAND           		 = unlessDefinedDefaultsTo( $xconf{COMMAND},       '' );
                    my $CHAINCMD_FULL     		 = unlessDefinedDefaultsTo( $xconf{CHAINCMD},      '' );
                    my $AUTOMEDIAID       		 = unlessDefinedDefaultsTo( $xconf{AUTOMEDIAID}, '' );
                    my $AUTOMEDIAID_GROUP 		 = unlessDefinedDefaultsTo( $xconf{AUTOMEDIAID_GROUP}, '' );
                    my $AUTOMEDIAIDSUFFIX 		 = unlessDefinedDefaultsTo( $xconf{AUTOMEDIAIDSUFFIX}, '' );
                    my $ADD_DOW_TO_SUFFIX 		 = unlessDefinedDefaultsTo( $xconf{ADD_DOW_TO_SUFFIX}, '' );
                    my $IS_A_PULLCMD      		 = unlessDefinedDefaultsTo( $xconf{IS_A_PULLCMD}, '' );
                    my $NONSUBSCRIBE_CHAIN		 = unlessDefinedDefaultsTo( $xconf{NONSUBSCRIBE_CHAIN}, 0 );
                    my $SHIFT_TO_PAID_IF_CAP_REACHED = unlessDefinedDefaultsTo( $xconf{SHIFT_TO_PAID_IF_CAP_REACHED}, 0 );
                    my $CAP_VARNAME                  = unlessDefinedDefaultsTo( $xconf{CAP_VARNAME}, '' );
                    my $CAP_VARVALUE                 = unlessDefinedDefaultsTo( $xconf{CAP_VARVALUE}, 0 );


                    # chain cmd is composed of: CHAINCMDqueue CHAINCMDparam
                    $CHAINCMD_FULL =~ s/^\s+//g;
                    $CHAINCMD_FULL =~ s/\s+$//g;
                    my ($CHAINCMD, $CHAINCMD_PARAM) = split /\s+/, $CHAINCMD_FULL, 2; 
    
                    $SIGCOMMAND = $COMMAND;

                    my $SERVICENAME = $COMMAND;

                    my %p_cmd = (
                        origin => "$msg_origin",	
                        cstamp => "$msg_cstamp",
                        dest   => "$msg_dest",
                        smsc   => "$msg_smsc",
                        msgid  => "$msgid",
                    );       
             
                    if ($IS_A_PULLCMD){
                        $p_cmd{cmd} = $CHAINCMD;
                        $p_cmd{txt} = "$cname --BID_AMOUNT=$BID_AMOUNT";
                        fsq::putcmdfile( %p_cmd );

                        $triggerontoon = 0; 
                        last;
                    }

                    my @ltime         = localtime();
                    my $dowidx        = $ltime[6];
                    my $automediaid   = ($AUTOMEDIAID) ? $AUTOMEDIAID : "$SIGCOMMAND-$AUTOMEDIAIDSUFFIX";
                    $automediaid   = ($AUTOMEDIAID_GROUP) ? $AUTOMEDIAID_GROUP : "$SIGCOMMAND-$AUTOMEDIAIDSUFFIX";
                
                    if ($ADD_DOW_TO_SUFFIX) { $automediaid.= $DOWSUFFIX[$dowidx]; }

                    $lastautomediaid = "$SIGCOMMAND-$AUTOMEDIAIDSUFFIX";
                    $triggerontoon = $TRIGGER_ONTOON;

                    my @automediaids = split /\s+/, $automediaid;

                    my $active = 0;
                    foreach my $id (@automediaids){
                        if (autosubs::isupdateon( $msg_origin, $id )) {
                            $active = 1;
                        }
                    }

                    if ( not $active ) {
                        if ($NONSUBSCRIBE_CHAIN) {
                            $p_cmd{cmd} = $CHAINCMD;
                            $p_cmd{txt} = $CHAINCMD_PARAM;
                            fsq::putcmdfile( %p_cmd );
                        }
                        else {

                            my $promo_service_cap = 0;
                            my $PROMO_SERVICE_CAP_VARNAME =  $PROMO_CAP_VARNAME;
                            $PROMO_SERVICE_CAP_VARNAME =~ s/{SERVICE}/$SERVICENAME/;
                            $promo_service_cap = vartable::get_value( $PROMO_SERVICE_CAP_VARNAME, $msg_origin );
                            $promo_service_cap = 0 if(!defined($promo_service_cap));

                            if($OPTS_REF){
                                my $referrer = uc $OPTS_REF;
                                my $varname = "$referrer=$SIGCOMMAND"; 
                                my $rc = vartable::set_value( $varname, $msg_origin, 1);
                                if($rc eq '0E0'){
                                    die "$0: FATAL: Referrer not set\n" . Dumper( $pqmsg );
                                }
                            }

                            $COMMAND .= " ON $cname $OPTS";

                            $p_cmd{cmd} = $CHAINCMD;
                            $p_cmd{txt} = $COMMAND;
                            fsq::putcmdfile( %p_cmd );


                            #TODO: First Time To Promo in this Service..
                            if ($promo_service_cap == 0) {
                                # Auto on on Bid Alert
                                $p_cmd{cmd} = "scriptmenu";
                                $p_cmd{txt} = "BIDALERT AUTOON";
                                fsq::putcmdfile( %p_cmd );

                                # Hook Bid Amount
                                $p_cmd{cmd} = $HOOK_COMMAND;
                                $p_cmd{txt} = "$PROMO_CODE --amount=$BID_AMOUNT";
                                fsq::putcmdfile( %p_cmd );

                                if($PROMO_CAP_VALUE) {
                                    $promo_service_cap += 1;
                                    my $rc = vartable::set_value( $PROMO_SERVICE_CAP_VARNAME, $msg_origin, $promo_service_cap);
                                    if($rc eq '0E0'){
                                        die "$0: FATAL: PROMO SERVICE CAP not set\n" . Dumper( $pqmsg );
                                    }
                                }
                            }
                            else {
                                $p_cmd{cmd} = $CHGWRAP_COMMAND;
                                $p_cmd{txt} = "$PROMO_CODE $CHGWRAP_TARIFF $SERVICENAME PaidOptin ( $HOOK_COMMAND $PROMO_CODE --amount=$BID_AMOUNT )";
                                fsq::putcmdfile( %p_cmd );
                            }

                        }

                        $triggerontoon = 0; 
                        last;
                    }
                }

                # reply with ontoon message
                if (($lastautomediaid) && ($triggerontoon)) {
                
                    my ($msg1, $msg2, $msg3, $umtc, $umsd) = dbusermsg::get3usermessage_tcsd( lc $SIGCOMMAND, "OnToOn" );
                    my $msg_dest = $msg_origin;
                    $status = 'OnToOn';

                    my %replies = ();

                    my $longmsg = join('', $msg1, $msg2, $msg3 );

                    my $x_msgid = $CSP_TXID_PREFIX.csp::getcsptxid( $ACCESS_NO, $msg_dest );
                    ($longmsg) and
                         %replies = (
                            msgcode         => "I-$x_msgid:$SIGCOMMAND:$status",
                            cmdorigin       => $msg_dest,
                            cstamp          => $msg_cstamp,
                            dest            => $msg_dest,
                            msgtype         => 'LONG',
                            txt             => $longmsg,
                            bin             => '',
                            tc              => $umtc,
                            sd              => $umsd,
                            origin          => $ORIGIN_MASKED,
                            msgid           => $x_msgid,
                        );    

                    fsq::putmsg( %replies );
                }

            } else {
                #POSTPAID MESSAGE
                my $status = 'postpaid_filter';
                my ($msg1, $msg2, $msg3, $umtc, $umsd) = dbusermsg::get3usermessage_tcsd( lc $SIGCOMMAND, $status );
                my $msg_dest = $msg_origin;

                my %replies = ();
                my $longmsg = join('', $msg1, $msg2, $msg3 );

                my $x_msgid = $CSP_TXID_PREFIX.csp::getcsptxid( $ACCESS_NO, $msg_dest );
                ($longmsg) and
                    %replies = (
                        msgcode         => "I-$x_msgid:$SIGCOMMAND:$status",
                        cmdorigin       => $msg_dest,
                        cstamp          => $msg_cstamp,
                        dest            => $msg_dest,
                        msgtype         => 'LONG',
                        txt             => $longmsg,
                        bin             => '',
                        tc              => $umtc,
                        sd              => $umsd,
                        origin          => $ORIGIN_MASKED,
                        msgid           => $x_msgid,
        	    );    
                fsq::putmsg( %replies );

            }

        } else {

            # Time bound invalid reply
            my $status = 'not_promo_hours';
            my ($msg1, $msg2, $msg3, $umtc, $umsd) = dbusermsg::get3usermessage_tcsd( lc $SIGCOMMAND, $status );
            my $msg_dest = $msg_origin;

            my %replies = ();
            my $longmsg = join('', $msg1, $msg2, $msg3 );

            my $x_msgid = $CSP_TXID_PREFIX.csp::getcsptxid( $ACCESS_NO, $msg_dest );
            ($longmsg) and
             %replies = (
                msgcode         => "I-$x_msgid:$SIGCOMMAND:$status",
                cmdorigin       => $msg_dest,
                cstamp          => $msg_cstamp,
                dest            => $msg_dest,
                msgtype         => 'LONG',
                txt             => $longmsg,
                bin             => '',
                tc              => $umtc,
                sd              => $umsd,
                origin          => $ORIGIN_MASKED,
                msgid           => $x_msgid,
            );

            fsq::putmsg( %replies );
   
        }
    } 
}


# --------------------------------- END

END {

}

