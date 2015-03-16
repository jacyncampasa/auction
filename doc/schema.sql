--

create table if not exists auction_campaign (
  id integer unsigned not null auto_increment,
  code varchar(64) not null,
  name varchar(255) not null,
  date_begin date,
  date_end date,
  remarks text,
  created datetime,
  last_modified timestamp,
  primary key (id),
  unique index (code),
  index (code)
) engine=InnoDB default charset=utf8;


create table if not exists auction_item (
  id integer unsigned not null auto_increment,
  campaign_code varchar(64) not null,
  auction_date date not null,
  auction_time_hhmm_begin varchar(4) not null,
  auction_time_hhmm_end varchar(4) not null,
  name varchar(255) not null,
  remarks text,
  created datetime,
  last_modified timestamp,
  primary key (id),
  constraint foreign key (campaign_code) references auction_campaign (code) on update cascade,
  index (campaign_code, auction_date)
) engine=InnoDB default charset=utf8;


-- automatic tables

create table if not exists auction_bidder (
  id integer unsigned not null auto_increment,
  campaign_code varchar(64) not null,
  msisdn varchar(32) not null,
  credits integer unsigned not null default 0,
  created datetime,
  last_modified timestamp,
  primary key (id),
  constraint foreign key (campaign_code) references auction_campaign (code) on update cascade,
  unique key (campaign_code, msisdn),
  index (campaign_code, msisdn)
) engine=InnoDB default charset=utf8;



create table if not exists auction_offer (
  id integer unsigned not null auto_increment,
  item_id integer unsigned not null,
  offer_amount decimal(65,2) not null,
  created datetime,
  last_modified timestamp,
  primary key (id),
  constraint foreign key (item_id) references auction_item (id),
  unique index (item_id, offer_amount)
) engine=InnoDB default charset=utf8;



create table if not exists auction_bid (
  id integer unsigned not null auto_increment,
  offer_id integer unsigned not null,
  msisdn varchar(32) not null,
  cstamp varchar(32) not null,
  is_first tinyint not null default 0,
  is_outbid_sent tinyint null default null,
  created datetime,
  last_modified timestamp,
  primary key (id),
  constraint foreign key (offer_id) references auction_offer (id)
) engine=InnoDB default charset=utf8;



