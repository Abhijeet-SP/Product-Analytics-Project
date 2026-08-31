SET search_path TO 'analytics';

-- category mix analysis
SELECT 
    oi.category,
    SUM(oi.quantity) AS units,
    SUM(oi.line_amount) AS revenue,
    ROUND(100.0 * SUM(oi.line_amount) / SUM(SUM(oi.line_amount)) OVER(), 1) AS revenue_share_pct,
    COUNT(DISTINCT oi.order_key) AS orders_containing,
    ROUND(AVG(oi.unit_price), 2) AS avg_unit_price
FROM fact_order_items AS oi
JOIN fact_orders AS o 
    ON o.order_key = oi.order_key
WHERE o.order_status = 'Delivered'
GROUP BY oi.category
ORDER BY revenue DESC;

-- basket affinity analysis (category co-occurrence)
WITH pairs AS (
    SELECT 
        a.category AS cat_a,
        b.category AS cat_b,
        COUNT(*) AS together
    FROM fact_order_items AS a
    JOIN fact_order_items AS b 
        ON b.order_key = a.order_key AND a.category < b.category
    JOIN fact_orders AS o 
        ON o.order_key = a.order_key
    WHERE o.order_status = 'Delivered'
    GROUP BY 1, 2),
    
solo AS (
    SELECT 
        oi.category,
        COUNT(DISTINCT oi.order_key) AS orders
    FROM fact_order_items AS oi
    JOIN fact_orders AS o 
        ON o.order_key = oi.order_key
    WHERE o.order_status = 'Delivered'
    GROUP BY 1)

SELECT 
    p.cat_a,
    p.cat_b,
    p.together,
    ROUND(100.0 * p.together / sa.orders, 1) AS pct_of_a_orders,
    ROUND(100.0 * p.together / sb.orders, 1) AS pct_of_b_orders
FROM pairs AS p
JOIN solo AS sa 
    ON sa.category = p.cat_a
JOIN solo AS sb 
    ON sb.category = p.cat_b
WHERE p.together >= 100
ORDER BY p.together DESC
LIMIT 25;

-- weekday and daypart revenue profile
SELECT 
    d.weekday,
    o.daypart,
    SUM(o.gov) AS gov,
    COUNT(*) AS orders,
    ROUND(AVG(o.gov), 2) AS aov,
    SUM(o.item_count) AS item_count,
    ROUND(100.0 * SUM(o.gov) / SUM(SUM(o.gov)) OVER(PARTITION BY d.weekday), 1) AS weekday_gov_share_pct
FROM fact_orders AS o
JOIN dim_date AS d 
    ON d.date_key = o.date_key
WHERE o.order_status = 'Delivered'
GROUP BY 1, 2
ORDER BY 1, 2;

-- veg penetration by city tier
SELECT 
    ci.tier,
    SUM(oi.quantity) AS delivered_units,
    SUM(oi.quantity) FILTER(WHERE mi.is_veg) AS veg_units,
    ROUND(100.0 * SUM(oi.quantity) FILTER(WHERE mi.is_veg) / SUM(oi.quantity), 1) AS veg_unit_share_pct
FROM fact_order_items AS oi
JOIN fact_orders AS o 
    ON o.order_key = oi.order_key
JOIN dim_menu_item AS mi 
    ON mi.menu_item_key = oi.menu_item_key
JOIN dim_city AS ci 
    ON ci.city_key = o.city_key
WHERE o.order_status = 'Delivered'
GROUP BY ci.tier
ORDER BY ci.tier;

-- monthly payment method trend
WITH monthly_payment AS (
    SELECT 
        DATE_TRUNC('month', order_timestamp)::date AS month,
        payment_method,
        COUNT(*) AS orders
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY 1, 2)

SELECT 
    month,
    payment_method,
    orders,
    ROUND(100.0 * orders / SUM(orders) OVER(PARTITION BY month), 1) AS order_share_pct
FROM monthly_payment
ORDER BY 1, 2;

-- menu item price ladder
WITH menu_price_quartiles AS (
    SELECT 
        menu_item_key,
        price,
        NTILE(4) OVER(ORDER BY price) AS price_quartile
    FROM dim_menu_item)

SELECT 
    q.price_quartile,
    MIN(q.price) AS min_item_price,
    MAX(q.price) AS max_item_price,
    SUM(oi.quantity) AS units,
    SUM(oi.line_amount) AS revenue,
    ROUND(100.0 * SUM(oi.quantity) / SUM(SUM(oi.quantity)) OVER(), 1) AS unit_share_pct,
    ROUND(100.0 * SUM(oi.line_amount) / SUM(SUM(oi.line_amount)) OVER(), 1) AS revenue_share_pct
FROM menu_price_quartiles AS q
JOIN fact_order_items AS oi 
    ON oi.menu_item_key = q.menu_item_key
JOIN fact_orders AS o 
    ON o.order_key = oi.order_key
WHERE o.order_status = 'Delivered'
GROUP BY q.price_quartile
ORDER BY q.price_quartile;
