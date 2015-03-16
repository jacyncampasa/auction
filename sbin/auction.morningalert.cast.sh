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

ITEM_NAME=$(mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT name FROM auction_item WHERE campaign_code = '$CAMPAIGN_CODE' AND auction_date = '$AUCTION_DATE';" | sed -e 's/\s/_/g')

yesterday_item=($(mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT CONCAT(id, ':', name) FROM auction_item WHERE campaign_code = '$CAMPAIGN_CODE' AND auction_date < '$AUCTION_DATE' LIMIT 1;" | sed -e 's/\s/_/g;s/:/ /'))

YEST_ITEM_ID=${yesterday_item[0]}
YEST_ITEM_NAME=${yesterday_item[1]}

yesterday_winner=($(mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT msisdn, ao.offer_amount as bid_amount, count(ab.id) as bid_count FROM auction_offer AS ao INNER JOIN auction_bid AS ab ON (ao.id=ab.offer_id) WHERE ao.item_id = $YEST_ITEM_ID GROUP BY ab.offer_id HAVING bid_count = 1 ORDER BY bid_amount ASC LIMIT 1;"))

YEST_WINNER_MSISDN=${yesterday_winner[0]}
YEST_WINNER_LUBID=${yesterday_winner[1]}


##if  NO WINNER, get first Lowest BId



### END ITEM INFO ###


### START TARGET BASE ###

dir="$HOME/work/jacyn/promo/$CAMPAIGN_CODE/MorningAlert/$AUCTION_DATE/"
mkdir -p $dir
TARGET_BASE=$dir/$yy$mm$dd.target_base.umins

TMP_TARGET_BASE=$(mktemp)
mysql -uppp -ppppppp -h2346db ppp -NBe "SELECT cstation FROM autosubs WHERE lon = 1 AND cautomediaid = '$AUTOMEDIA_ID'" > $TMP_TARGET_BASE
sort -u $TMP_TARGET_BASE > $TARGET_BASE
rm $TMP_TARGET_BASE

### END TARGET BASE ###



CMSGTYPE="MorningAlert"
if [[ $WEEKDAY == "Fri" ]]
then
    CMSGTYPE="$CMSGTYPE-$WEEKDAY"
fi

USERMSG_PARAMS=$dir/$yy$mm$dd.usermsg_params.txt
echo -e "PRODUCT_NAME=$(echo $ITEM_NAME | sed -e 's/_/ /g')" > $USERMSG_PARAMS
echo -e "YEST_PRODUCT_NAME=$(echo $YEST_ITEM_NAME | sed -e 's/_/ /g')" >> $USERMSG_PARAMS
echo -e "YEST_UBID=P$YEST_WINNER_LUBID" >> $USERMSG_PARAMS


if [ -f $TARGET_BASE ]; then

    TODAY="$mm-$dd-$yy"
    $HOME/bin/usermsg_alert.pl $CAMPAIGN_CODE $CMSGTYPE $TODAY $HOME/etc/dbh_2346globe.rc --targets_file=$TARGET_BASE --usermsg_params_file=$USERMSG_PARAMS --delivery_mode=deliverymode::fsqucp_txt --delivery_mode_rc=/home/ppp/bin/deliverymodes.rc
    #$HOME/bin/usermsg_alert.pl $CAMPAIGN_CODE $CMSGTYPE $TODAY $HOME/etc/dbh_2346globe.rc --targets_file=$TARGET_BASE --usermsg_params_file=$USERMSG_PARAMS
    exit 0
else
    dot_safecheck=$(echo "$HOME/safecheck/$(date +"%y%m")/$(date +"%y%m%d%H%M%S").safecheck")
    echo "$0: Failure! No Targets File! Please escalate to Developers!" > ${dot_safecheck}
    exit 1
fi
