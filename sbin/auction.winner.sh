#!/bin/bash

CAMPAIGN_CODE="BIDLOWQ12015"

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

yesterday_item=($(mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT CONCAT(id, ':', name) FROM auction_item WHERE campaign_code = '$CAMPAIGN_CODE' AND auction_date < '$AUCTION_DATE' LIMIT 1;" | sed -e 's/\s/_/g;s/:/ /'))

YEST_ITEM_ID=${yesterday_item[0]}
YEST_ITEM_NAME=${yesterday_item[1]}

WINNERS=$HOME/test.txt
mysql -uppp -ppppppp ppp -h2346db -NBe "SELECT msisdn, ao.offer_amount as bid_amount, count(ab.id) as bid_count FROM auction_offer AS ao INNER JOIN auction_bid AS ab ON (ao.id=ab.offer_id) WHERE ao.item_id = $YEST_ITEM_ID GROUP BY ab.offer_id HAVING bid_count = 1 ORDER BY bid_amount ASC LIMIT 5;" | sed -e 's/\s/>>/g' > $WINNERS

##if  NO WINNER, get first Lowest BId



### END ITEM INFO ###

for x in $(cat $WINNERS)
do
  msisdn=$(echo $x | sed -e 's/>>/\t/g' | cut -f1)
  amount=$(echo $x | sed -e 's/>>/\t/g' | cut -f2)
  echo "$msisdn, $amount"
done


#EMAIL
