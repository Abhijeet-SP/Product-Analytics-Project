/* SLA (Service Legal Contract)  
Contractual promise between
a merchant, logistics provider, and customer, defining expected shipping timelines.
*/

SET search_path TO analytics;

-- per city analysis 
SELECT 
    dc.city,
    dc.tier,
    COUNT(*) AS orders_per_city,
    ROUND(100.0 * COUNT(*) FILTER(WHERE fo.on_time) / COUNT(*), 2) AS on_time_pct,
    ROUND(AVG(fo.delivery_time_mins), 2) AS "avg_delivery_time_min", -- range is [30 - 40] mins
    ROUND(AVG(fo.distance_km), 2) AS "avg_distance_km", -- range is [2.5 - 2.8],
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fo.delivery_time_mins) AS p50_mins,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY fo.delivery_time_mins) AS p90_mins
FROM fact_orders AS fo
INNER JOIN dim_city AS dc 
    ON dc.city_key = fo.city_key
WHERE order_status = 'Delivered'
GROUP BY dc.city, dc.tier
ORDER BY on_time_pct;

-- time of the day analysis 
SELECT 
    daypart,
    COUNT(*) AS orders_per_city,
    ROUND(100.0 * COUNT(*) FILTER(WHERE on_time) / COUNT(*), 2) AS on_time_pct,
    ROUND(AVG(delivery_time_mins), 2) AS "avg_delivery_time_min", 
    ROUND(AVG(distance_km), 2) AS "avg_distance_km"
FROM fact_orders 
WHERE order_status = 'Delivered'
GROUP BY daypart
ORDER BY daypart;

-- weekend VS weekday analysis
SELECT * FROM fact_orders LIMIT 5;

WITH weekend_division AS (
    SELECT 
    dd.is_weekend,
    ROUND(100.0 * COUNT(*) FILTER(WHERE fo.on_time)/ COUNT(*) ,2) AS on_time_delivery_pct,
    ROUND(AVG(delivery_time_mins),2) AS avg_delivery_time_in_min
    FROM fact_orders AS fo
    LEFT JOIN dim_date AS dd 
        ON fo.date_key = dd.date_key
    WHERE fo.order_status = 'Delivered'
    GROUP BY 1
)

SELECT * FROM weekend_division LIMIT 5;

-- Distance based analysis
SELECT 
    width_bucket(o.distance_km, 0, 10, 5) AS distance_band,
    ROUND(MIN(o.distance_km), 1) AS band_min_km,
    ROUND(MAX(o.distance_km), 1) AS band_max_km,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.on_time) / COUNT(*), 1) AS on_time_pct,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY o.delivery_time_mins) AS p90_mins,
    ROUND(AVG(o.delivery_fee), 2) AS avg_delivery_fee
FROM analytics.fact_orders o
WHERE o.order_status = 'Delivered'
GROUP BY 1 ORDER BY 1;

SELECT * FROM analytics.fact_orders LIMIT 5;

-- Partner Leaderboard

SELECT 
    dp.partner_name, 
    dp.vehicle_type, 
    ci.city, 
    dp.rating AS partner_rating,
    COUNT(*) AS deliveries,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.on_time) / COUNT(*), 1) AS on_time_pct,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.delivery_time_mins) AS p50_mins,
    ROUND(AVG(o.rating) FILTER (WHERE o.rating IS NOT NULL), 2) AS avg_order_rating
FROM fact_orders AS o
JOIN dim_delivery_partner AS dp 
    ON dp.delivery_partner_key = o.delivery_partner_key
JOIN analytics.dim_city AS ci
     ON ci.city_key = dp.city_key
WHERE o.order_status = 'Delivered'
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) >= 30
ORDER BY on_time_pct DESC;

-- vehicle type delivery analysis
SELECT 
    ddp.vehicle_type, 
    ROUND(AVG(fo.delivery_time_mins),2) AS avg_delivery_time,
    ROUND(AVG(fo.distance_km),2) AS avg_distance_km,
    ROUND(100.0 * COUNT(*) FILTER(WHERE fo.on_time)/ COUNT(*) ,2 ) AS on_time_pcit
FROM fact_orders AS fo 
JOIN dim_delivery_partner AS ddp
    ON fo.delivery_partner_key = ddp.delivery_partner_key
WHERE order_status = 'Delivered' 
GROUP BY ddp.vehicle_type;

-- proimise accuracy 
WITH delivery_delta AS (
    SELECT 
        delivery_time_mins - promised_time_mins AS delta_mins
    FROM analytics.fact_orders
    WHERE order_status = 'Delivered')

SELECT 
    COUNT(*) AS deliveries,
    PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY delta_mins) AS p10_delta_mins,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delta_mins) AS p50_delta_mins,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delta_mins) AS p90_delta_mins,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delta_mins BETWEEN -5 AND 5) / NULLIF(COUNT(*), 0), 1) AS pct_within_five_mins_delta
FROM delivery_delta;