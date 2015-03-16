#!/bin/bash

CAMPAIGN_CODE="BIDLOWQ12015"
AUTOMEDIA_ID="FREEBIDALERT-D"


### START ITEM INFO ###

today_string=($(date +"%Y-%m-%d %m %d %y %H %M %S %a"))

AUCTION_DATE=${today_string[0]}
mm=${today_string[1]}
dd=${today_string[2]}
yy=${today_string[3]}
HH=${today_string[4]}
MM=${today_string[5]}
SS=${today_string[6]}
WEEKDAY=${today_string[7]}

item=($(mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT CONCAT(id, ':', name) 
                            FROM auction_item   
                            WHERE campaign_code = '$CAMPAIGN_CODE' AND auction_date = '$AUCTION_DATE';" | sed -e 's/\s/_/g;s/:/ /'))

ITEM_ID=${item[0]}
ITEM_NAME=${item[1]}

### END ITEM INFO ###


### START TARGET BASE ###

dir="$HOME/work/jacyn/promo/$CAMPAIGN_CODE/NightAlert/$AUCTION_DATE/"
mkdir -p $dir

LOWEST_UNIQUE_BID_MSISDN_LIST=$dir/$yy$mm$dd.lowest_unique_bid_list.txt
mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT msisdn, MIN(bid_amount) as bid_amount 
                            FROM (
                                SELECT msisdn, ao.offer_amount as bid_amount, count(ab.id) as bid_count
                                    FROM auction_offer AS ao INNER JOIN auction_bid AS ab ON (ao.id=ab.offer_id)
                                    WHERE ao.item_id = $ITEM_ID
                                    GROUP BY ab.offer_id
                                    HAVING bid_count = 1 
                                 ) AS unique_offer_bid
                            GROUP BY msisdn;" > $LOWEST_UNIQUE_BID_MSISDN_LIST

TARGET_BASE=$dir/$yy$mm$dd.target_base.with_ubid.txt
TARGET_BASE_UMINS=$dir/$yy$mm$dd.target_base.umins
TARGET_BASE_NOUBID=$dir/$yy$mm$dd.target_base.without_ubid.txt
TMP_TARGET_BASE=$(mktemp)

mysql -uppp -ppppppp -h2346db ppp -NBe "SELECT cstation FROM autosubs WHERE cautomediaid = '$AUTOMEDIA_ID' AND lon = 1 AND don='$AUCTION_DATE'" > $TMP_TARGET_BASE
fgrep -f $TMP_TARGET_BASE $LOWEST_UNIQUE_BID_MSISDN_LIST > $TARGET_BASE
cut -f1 $TARGET_BASE | sort -u > $TARGET_BASE_UMINS
fgrep -vf $TARGET_BASE_UMINS $TMP_TARGET_BASE | sort -u > $TARGET_BASE_NOUBID

rm $TMP_TARGET_BASE

### END TARGET BASE ###


CMSGTYPE="NightAlert"
CMSGTYPE_NOUBID="NightAlertNoUBid"
if [[ $WEEKDAY == "Fri" ]]
then
    CMSGTYPE="$CMSGTYPE-$WEEKDAY"
    CMSGTYPE_NOUBID="$CMSGTYPE_NOUBID-$WEEKDAY"
fi

USERMSG_PARAMS=$dir/$yy$mm$dd.usermsg_params.txt
echo -e "PRODUCT_NAME=$(echo $ITEM_NAME | sed -e 's/_/ /g')" > $USERMSG_PARAMS
echo -e "HH=$HH" >> $USERMSG_PARAMS
echo -e "MM=$MM" >> $USERMSG_PARAMS
echo -e "SS=$SS" >> $USERMSG_PARAMS

if [ -f $TARGET_BASE ]; then

    TODAY="$mm-$dd-$yy"
    $HOME/bin/usermsg_alert.pl $CAMPAIGN_CODE $CMSGTYPE $TODAY $HOME/etc/dbh_2346globe.rc --targets_file=$TARGET_BASE --usermsg_params_file=$USERMSG_PARAMS --delivery_mode=deliverymode::fsqucp_txt --delivery_mode_rc=/home/ppp/bin/deliverymodes.rc
    #$HOME/bin/usermsg_alert.pl $CAMPAIGN_CODE $CMSGTYPE $TODAY $HOME/etc/dbh_2346globe.rc --targets_file=$TARGET_BASE --usermsg_params_file=$USERMSG_PARAMS

    if [ -f $TARGET_BASE_NOUBID ]; then
        $HOME/bin/usermsg_alert.pl $CAMPAIGN_CODE $CMSGTYPE_NOUBID $TODAY $HOME/etc/dbh_2346globe.rc --targets_file=$TARGET_BASE_NOUBID --usermsg_params_file=$USERMSG_PARAMS --delivery_mode=deliverymode::fsqucp_txt --delivery_mode_rc=/home/ppp/bin/deliverymodes.rc
    fi
    exit 0
else
    dot_safecheck=$(echo "$HOME/safecheck/$(date +"%y%m")/$(date +"%y%m%d%H%M%S").safecheck")
    echo "$0: Failure! No Targets File! Please escalate to Developers!" > ${dot_safecheck}
    exit 1
fi
