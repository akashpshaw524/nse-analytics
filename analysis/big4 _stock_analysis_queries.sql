use nse_analysis;
describe prices;
show tables;
select * from prices;
select * from stocks;
alter table prices drop column price_id;
alter table prices add price_id int not null auto_increment primary key first;


-- checking loaded correctly 

select symbol , count(*) as trading_days , 
max(trade_date) as to_date , min(trade_date) as from_date from prices
group by symbol;


-- 1. Which stock had the biggest single day price gain?

select symbol , trade_date, close_price , prev_close , 
round((close_price - prev_close),2) as price_gain , round(((close_price - prev_close) * 100 / prev_close),2) as price_gain_pct 
from prices
order by price_gain_pct desc
limit 10;


-- 2. Average monthly trading volume — which stock is most actively traded?

select symbol , date_format(trade_date, '%Y-%m') as monthly , round(avg(volume),2) as avg_vol from prices
group by symbol , monthly
order by avg_vol desc;


-- 3. Monthly average close price for each stocks

select symbol , date_format(trade_date, '%Y-%m') as monthly , round(avg(close_price),2) as avg_price , max(close_price) as max_price , 
min(close_price) as min_price from prices
group by symbol , monthly;

-- 4. Monthly volatility — which stock is most volatile?

select symbol , date_format(trade_date , '%Y-%m') as monthly , round(avg((high_price - low_price) * 100 / prev_close),2) as avg_volatility_pct , 
round(max((high_price - low_price) * 100 / prev_close),2) as max_volatility ,
round(min((high_price - low_price) * 100 / prev_close),2) as min_volatility from prices
group by symbol , monthly;


-- 5. Bullish days vs bearish days with percentage on up and down , 
-- volatitlity percentage during up and down days — which stock closed up more often?

select symbol , 
-- Average % move for bullish days
count(case when close_price > open_price then 1 end) as bullish_days , 
round(avg(case when close_price > open_price then (close_price - open_price) * 100 / open_price end),2) as avg_pct_on_up , 
round(max(case when close_price > open_price then (close_price - open_price) * 100 / open_price end),2) as max_pct_on_up , 
round(avg(case when close_price > open_price then (high_price - low_price) * 100 / prev_close end),2) as avg_volatility , 
round(max(case when close_price > open_price then (high_price - low_price) * 100 / prev_close end),2) as max_volatility ,
round(min(case when close_price > open_price then (high_price - low_price) * 100 / prev_close end),2) as min_volatility , 
-- Average % move for bearish days
count(case when close_price < open_price then 1 end) as bearish_days , 
round(avg(case when close_price < open_price then (close_price - open_price) * 100 / open_price end),2) as avg_pct_on_down ,
round(min(case when close_price < open_price then (close_price - open_price) * 100 / open_price end),2) as min_pct_on_down , 
round(avg(case when close_price < open_price then (high_price - low_price) * 100 / prev_close end),2) as avg_volatility , 
round(max(case when close_price < open_price then (high_price - low_price) * 100 / prev_close end),2) as max_volatility , 
round(min(case when close_price < open_price then (high_price - low_price) * 100 / prev_close end),2) as min_volatility , 
count(case when close_price = open_price then 1 end) as flat_days
from prices
group by symbol;


-- 6. Year return — which stock gave best return over the full year?

with first_prices as (select symbol , close_price as start_price from prices
where trade_date = (select min(trade_date) from prices)),
last_prices as (select symbol , close_price as last_price from prices
where trade_date = (select max(trade_date) from prices))
select f.symbol , s.sector , f.start_price , l.last_price , 
(l.last_price - f.start_price) as absolute_gain , round(((l.last_price - f.start_price)*100 / f.start_price),2) as absolute_gain_in_pct 
from first_prices f
join last_prices l on f.symbol  = l.symbol
join stocks s on s.symbol = f.symbol
order by absolute_gain_in_pct desc;


-- 7. Day over day price change using LAG

select symbol , trade_date , close_price , 
lag(close_price) over (partition by symbol order by trade_date ) as prev_day_close,
round((close_price - lag(close_price) over (partition by symbol order by trade_date)), 2) as day_change,
round((close_price - lag(close_price) over (partition by symbol order by trade_date)) * 100.0 / 
lag(close_price) over (partition by symbol order by trade_date),2) as day_change_pct
from prices   
order by symbol , trade_date;


-- 8. Rank stocks by monthly return within each month

with monthly_prices as (select symbol, date_format(trade_date, '%y-%m') as monthly,
first_value(close_price) over (partition by symbol, date_format(trade_date, '%y-%m')
order by trade_date asc) as start_price,
first_value(close_price) over (partition by symbol, date_format(trade_date, '%y-%m')
order by trade_date desc) as end_price from prices),
monthly_distinct as (select distinct symbol, monthly, start_price, end_price,
round((end_price - start_price) * 100.0 / start_price, 2) as monthly_return_pct
from monthly_prices)
select symbol, monthly, start_price, end_price, monthly_return_pct,
rank() over (partition by monthly order by monthly_return_pct desc) as rank_in_month
from monthly_distinct
order by monthly desc, rank_in_month;


-- 9 Weighted recent months scorecard (momentum screening)

with monthly_prices as (select symbol, date_format(trade_date, '%y-%m') as monthly,
first_value(close_price) over (partition by symbol, date_format(trade_date, '%y-%m')
order by trade_date asc) as start_price,
first_value(close_price) over (partition by symbol, date_format(trade_date, '%y-%m')
order by trade_date desc) as end_price
from prices),
monthly_distinct as (select distinct symbol, monthly, round((end_price - start_price) 
* 100.0 / start_price, 2) as monthly_return_pct
from monthly_prices),
monthly_ranks as (select symbol, monthly, monthly_return_pct,
rank() over (partition by monthly order by monthly_return_pct desc) as rank_in_month
from monthly_distinct),
month_weights as (select monthly,
row_number() over (order by monthly asc) as weight
from (select distinct monthly from monthly_distinct) m)
select r.symbol,
count(case when r.rank_in_month = 1 then 1 end) as times_ranked_1st,
count(case when r.rank_in_month = 2 then 1 end) as times_ranked_2nd,
count(case when r.rank_in_month = 3 then 1 end) as times_ranked_3rd,
count(case when r.rank_in_month = 4 then 1 end) as times_ranked_4th,
round(avg(r.rank_in_month), 1) as simple_avg_rank,
round(sum(r.rank_in_month * w.weight) / sum(w.weight), 2) as weighted_avg_rank,
round(avg(r.monthly_return_pct), 2) as avg_monthly_return_pct,
round(avg(case
when r.monthly >= date_format(date_sub(curdate(), interval 3 month), '%y-%m')
then r.monthly_return_pct
end), 2) as last_3m_avg_return
from monthly_ranks r
join month_weights w on r.monthly = w.monthly
group by r.symbol
order by weighted_avg_rank asc;


-- 10. 7-day and 30 days rolling average close price and close price trend

with MovingAverages as ( 
select symbol , trade_date , close_price , 
round(avg(close_price) over (partition by symbol order by trade_date rows between 6 preceding and current row ),2) as rolling_7_day_avg,
round(avg(close_price) over (partition by symbol order by trade_date rows between 29 preceding and current row ),2) as rolling_30_day_avg
from prices)
select * , 
case when close_price > rolling_7_day_avg then 'up'
when close_price < rolling_7_day_avg then 'down' else 'flat' end as trend_7day,
round(((close_price - rolling_7_day_avg) * 100 / rolling_7_day_avg),2) as pct_from_7d_ma,
case when close_price > rolling_30_day_avg then 'up'
when close_price < rolling_30_day_avg then 'down' else 'flat' end as trend_30day,
round(((close_price - rolling_30_day_avg) * 100 / rolling_30_day_avg),2) as pct_from_30d_ma
from MovingAverages
order by symbol , trade_date;

-- 11. Distance from High/Low
with yearly as (select symbol , max(high_price) as yearly_high , 
min(low_price) as yearly_low 
from prices
group by symbol),
monthly as(select symbol, date_format(trade_date, '%Y-%m') as month,
max(high_price) as monthly_high,
min(low_price) as monthly_low
from prices 
group by symbol , month ),
weekly as (select symbol , year(trade_date) as yr, week(trade_date,1) as wk,
max(high_price) as weekly_high,
min(low_price) as weekly_low
from prices
group by symbol , yr , wk ),
latest_price as (select symbol, close_price AS current_price
from prices
where trade_date = (select max(trade_date) from prices)),
latest_month as (select date_format(max(trade_date), '%Y-%m') as month
from prices),
latest_week as (select year(max(trade_date)) as yr,
week(max(trade_date), 1) AS wk
from nse_analysis.prices)
select lp.symbol, lp.current_price, y.yearly_high, y.yearly_low,
round((lp.current_price - y.yearly_high) * 100.0 / y.yearly_high, 2) as pct_from_yearly_high,
round((lp.current_price - y.yearly_low) * 100.0 / y.yearly_low, 2) as pct_from_yearly_low,
m.monthly_high, m.monthly_low,
round((lp.current_price - m.monthly_high) * 100.0 / m.monthly_high, 2) as pct_from_monthly_high,
round((lp.current_price - m.monthly_low) * 100.0 / m.monthly_low, 2) as pct_from_monthly_low,
w.weekly_high, w.weekly_low,
round((lp.current_price - w.weekly_high) * 100.0 / w.weekly_high, 2) as pct_from_weekly_high,
round((lp.current_price - w.weekly_low) * 100.0 / w.weekly_low, 2) as pct_from_weekly_low
from latest_price lp
join yearly  y  on lp.symbol = y.symbol
join monthly m  on lp.symbol = m.symbol and m.month  = (select month from latest_month)
join weekly  w  ON lp.symbol = w.symbol and w.yr = (select yr from latest_week) 
and w.wk = (select wk from latest_week)
order by lp.symbol;


-- 1. Turn off the seatbelt
 # set sql_safe_updates = 0;

-- 2. Deleting duplicated entries on the same date and of the same exact symbol

# delete p1 from prices p1
# inner join prices p2 
# where p1.price_id < p2.price_id and
# p1.symbol = p2.symbol and
# p1.trade_date = p2.trade_date;

-- 3. Turn the seatbelt back on (Best practice)
 # set sql_safe_updates = 1;