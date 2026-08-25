SET search_path to 'analytics';

-- pareto concentration 

SELECT * FROM fact_orders WHERE order_status != 'Delivered' LIMIT 5;
SELECT * FROM fact_order_items LIMIT 5;
SELECT * FROM dim_restaurant LIMIT 5;
SELECT * FROM dim_city LIMIT 5;


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

