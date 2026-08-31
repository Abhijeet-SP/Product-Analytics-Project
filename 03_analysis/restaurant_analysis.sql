SET search_path to 'analytics';

-- pareto concentration 
WITH restaurant_gov AS (
    SELECT 
        restaurant_key, 
        SUM(gov) AS gov
    FROM fact_orders 
    WHERE order_status = 'Delivered'
    GROUP BY 1),

restaurant_rnking AS (
    SELECT 
        restaurant_key,
        gov,
        ROUND(100.0 * SUM(gov) OVER(ORDER BY gov DESC) / SUM(gov) OVER(), 2) AS cum_gov_pct,  
        ROUND(100.0 * ROW_NUMBER() OVER(ORDER BY gov DESC) / COUNT(*) OVER(), 2) AS restaurant_pct
    FROM restaurant_gov
    ORDER BY 2 DESC)

SELECT 
    MIN(restaurant_pct) FILTER(WHERE cum_gov_pct >= 50) AS pct_restaurant_bring_50_pct_gov,
    MIN(restaurant_pct) FILTER(WHERE cum_gov_pct >= 80) AS pct_restaurant_bring_80_pct_gov
FROM restaurant_rnking;

-- prep time vs sla (service legal agreement for delivery time)
SELECT 
    width_bucket(r.avg_prep_time_mins, 10, 40, 6) AS prep_bucket,
    MIN(r.avg_prep_time_mins) AS bucket_min,
    MAX(r.avg_prep_time_mins) AS bucket_max,
    COUNT(*) AS orders,
    ROUND(AVG(o.delivery_time_mins), 2) AS avg_delivery_time,
    ROUND(100.0* COUNT(*) FILTER(WHERE o.on_time) / COUNT(*), 2) AS on_time_pct
FROM fact_orders AS o 
JOIN dim_restaurant AS r 
    ON o.restaurant_key = r.restaurant_key
WHERE o.order_status = 'Delivered'
GROUP BY 1 ORDER BY 1;

-- city_wise cuisine performance 

WITH cuisine_city_tier AS (
    SELECT
        r.cuisine,
        ci.city,
        ROUND(AVG(o.gov),2) AS aov,
        SUM(o.gov) AS total_gov,
        COUNT(o.order_key) AS total_orders,
        RANK() OVER(PARTITION BY ci.city ORDER BY SUM(o.gov) DESC) AS rnk
    FROM fact_orders AS o
    JOIN dim_restaurant AS r 
        ON o.restaurant_key = r.restaurant_key
    JOIN dim_city as ci
        ON ci.city_key = o.city_key 
    WHERE order_status = 'Delivered'
    GROUP BY 1, 2)

SELECT 
    cuisine, 
    city, 
    avg_gov, 
    total_gov, 
    total_orders
FROM cuisine_city_tier
WHERE rnk >=5;

-- resturant leaderboard (TOP 50)

SELECT 
    r.restaurant_name,
    r.cuisine,
    ci.city,
    r.price_tier,
    r.rating,
    COUNT(o.order_key) AS orders,
    ROUND(AVG(o.gov)) AS aov,
    ROUND(SUM(o.gov)) AS total_gov,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.on_time) / COUNT(*), 1) AS on_time_pct
FROM fact_orders AS o 
JOIN dim_restaurant AS r 
    ON o.restaurant_key = r.restaurant_key
JOIN dim_city as ci
    ON ci.city_key = o.city_key 
WHERE order_status = 'Delivered'
GROUP BY 1, 2, 3, 4, 5
HAVING COUNT(o.order_key) >=30
ORDER BY ROUND(AVG(o.gov),2) DESC
LIMIT 50;


-- veg vs non-veg
SELECT 
    r.is_pure_veg,
    COUNT(*) AS order,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_orders WHERE order_status = 'Delivered'),2) AS pct_orders,
    ROUND(AVG(gov), 2) AS aov,
    SUM(gov) AS total_gov,
    ROUND(AVG(r.rating),2) AS avg_rating,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.on_time) / COUNT(*), 1) AS on_time_pct
FROM fact_orders AS o 
JOIN dim_restaurant AS r 
    ON o.restaurant_key = r.restaurant_key
WHERE o.order_status = 'Delivered'
GROUP BY 1;

-- Cancellation rate (based on city and total order recieved)

WITH cancellation AS (
    SELECT
        r.restaurant_name,
        ci.city,
        COUNT(*) FILTER (WHERE o.order_status = 'Cancelled by Restaurant') AS order_cancelled,
        COUNT(*) AS total_orders
    FROM fact_orders AS o 
    JOIN dim_restaurant AS r 
        ON o.restaurant_key = r.restaurant_key
    JOIN dim_city as ci
        ON ci.city_key = o.city_key 
    GROUP BY 1, 2)

SELECT 
    restaurant_name,
    city,
    ROUND((order_cancelled *100.0) / total_orders, 2)
FROM cancellation
WHERE order_cancelled > 10;
