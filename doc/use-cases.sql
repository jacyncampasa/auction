
-- auction_am_alert_bcast.pl 
-- params:
--    campaign_code
--    today_yyyymmdd

--
select * from auction_campaign where code="$campaign_code" and (date_begin <= "$today_yyyy-mm-dd") and (date_end >= "$today_yyyy-mm-dd");

-- targets
select * from autosubs where cautomediaid="$freebidalert-d" and lon=1
  intersect VIP
  sort uniq cstation


-- A.M. bcast message is not unique per MIN, so it's okay to have this via usermsg interpolation

select ai.id, ai.name
  from 
    auction_campaign as ac INNER JOIN auction_item as ai on (ac.code=ai.campaign_code) 
    where 
        ac.campaign_code="$campaign_code"
    and ai.auction_date="$yest_yyyy-mm-dd"
  ; -- get the item.id 

select
    ao.offer_amount as bid_amount, count(ab.id) as bid_count
  from
        auction_offer as ao INNER JOIN auction_bid as ab on (ao.id=ab.offer_id)
  where
        ao.item_id="$item_id"
  group by
        ab.offer_id
  having 
        bid_count = 1
  order by 
        bid_amount ASC
  ;

-- targets file format: tab-delimited
-- targets file fields:
    -- msisdn 
    -- 1dayago-item-name {YEST_ITEM_NAME}
    -- 1dayago-item-awarded-offer-amount-x.xx {YEST_ITEM_AMT}
    -- 0dayago-item-name {TODAY_ITEM_NAME}


-- 
