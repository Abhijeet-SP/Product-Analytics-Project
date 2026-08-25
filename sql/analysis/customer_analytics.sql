SET search_path TO 'analytics';

-- rfm Segementation for 10675 distinct customers 
/*
Customer Segemenataion: Dividing the customer as based on scores (given rating by ntile() function)

1. Champion
2. Big Spender
3. Promising 
4. Loyal
5. At risk 
6. Lost
*/
WITH rfm AS(
    SELECT
        customer_key,
        MAX(order_timestamp)::date AS "last_order",
        COUNT(*) AS "frequency",
        SUM(gov) AS "monetary_value"
    FROM fact_orders 
    WHERE order_status = 'Delivered'
    GROUP BY customer_key),

scored AS(
    SELECT
    customer_key,
    last_order,
    frequency,
    monetary_value,
    NTILE(5) OVER(ORDER BY last_order) AS r_score,
    NTILE(5) OVER(ORDER BY frequency) AS f_score,
    NTILE(5) OVER(ORDER BY monetary_value) AS m_score
    FROM rfm), 

seg AS(
    SELECT 
        s.customer_key,
        c.persona,
        c.is_gold_member,
        monetary_value,
        CASE
            WHEN s.r_score >= 4 AND s.f_score >= 4 AND s.m_score >=4 THEN 'Champion'
            WHEN s.r_score >= 4 AND s.m_score >= 4 THEN 'Big Spender'
            WHEN s.r_score >= 4 AND s.f_score <= 2 THEN 'Promising'
            WHEN s.r_score >= 3 AND s.f_score >= 3 THEN 'Loyal'
            WHEN s.r_score <= 2 AND s.f_score >= 4 THEN 'At Risk'
            WHEN s.r_score <= 2 AND s.f_score <= 2 THEN 'Lost'
            ELSE 'Regular'
        END AS segment
    FROM scored AS s
    JOIN dim_customer AS c
        ON c.customer_key = s.customer_key)

SELECT 
    segment,
    COUNT(customer_key) AS customer_count,
    ROUND((COUNT(customer_key)*100.0) / (SELECT COUNT(*) FROM seg), 2) AS pct_of_customers,
    ROUND((SUM(monetary_value) *100.0) / (SELECT SUM(monetary_value) FROM seg), 2) AS pct_of_revenue
FROM seg 
GROUP BY segment
ORDER BY customer_count DESC;


-- Repeat Rate

WITH order_count_per_customers AS(
    SELECT 
        customer_key,
        COUNT(*) AS orders
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_key)

SELECT 
    COUNT(*) AS customer_with_orders,
    COUNT(*) FILTER(WHERE orders > 2) AS cst_with_repeat_orders,
    ROUND((COUNT(*) FILTER(WHERE orders > 2) * 100.0) / COUNT(*), 2) AS repeat_percentage,
    ROUND(AVG(orders), 2) AS average_repeat_purchase,
    MAX(orders) AS max_repeat_purchase,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY orders) AS median_repeat_pruchase
FROM order_count_per_customers;

-- Analytics from Gold vs Non Gold Member

SELECT 
    is_gold_order,
    COUNT(*) AS orders_count,
    ROUND(AVG(gov), 2) AS aov,
    ROUND(AVG(delivery_fee), 2) AS avg_delivery_fee,
    ROUND(AVG(total_discount), 2) AS avg_discount,
    ROUND(AVG(commission_rate), 2) AS avg_comission,
    ROUND(AVG(contribution_margin), 2) AS avg_margin,
    ROUND((100.0 *COUNT(*) FILTER(WHERE contribution_margin < 0)) / COUNT(*),2) As pct_negative_comission
FROM fact_orders
WHERE order_status = 'Delivered'
GROUP BY is_gold_order;
   
-- customer acquisition channel quality

SELECT 
    marketing_channel,
    ROUND((100.0 * COUNT(marketing_channel)) / (SELECT COUNT(*) FROM dim_customer), 2) AS channel_quality
FROM dim_customer
GROUP BY marketing_channel
ORDER BY channel_quality DESC;

-- customer acquistion channel quality based on order number

SELECT 
    dc.marketing_channel,
    COUNT(o.order_key) AS orders_per_channel,
    ROUND((COUNT(o.order_key)*100.0) / (SELECT COUNT(*) FROM fact_orders),2) AS pct_order_per_channel,
    ROUND(AVG(o.gov),2) AS aov
FROM dim_customer AS dc
LEFT JOIN fact_orders AS o 
    ON dc.customer_key = o.customer_key
WHERE o.order_status = 'Delivered'
GROUP BY marketing_channel
ORDER BY pct_order_per_channel DESC;

-- Persona Analysis

SELECT 
    dc.persona,
    COUNT(o.order_key) AS orders_per_persona,
    ROUND((COUNT(o.order_key)*100.0) / (SELECT COUNT(*) FROM fact_orders),2) AS pct_order_per_persona,
    ROUND(AVG(o.gov),2) AS aov
FROM dim_customer AS dc
LEFT JOIN fact_orders AS o 
    ON dc.customer_key = o.customer_key
WHERE o.order_status = 'Delivered'
GROUP BY dc.persona
ORDER BY pct_order_per_persona DESC;

-- MTU (monthly transcating users)

SELECT 
    DATE_TRUNC('month', order_timestamp)::DATE AS order_month,
    COUNT(DISTINCT customer_key) AS mtu,
    COUNT(*) AS total_orders,
    ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT customer_key),2) AS orders_per_mtu
FROM fact_orders 
WHERE order_status = 'Delivered'
GROUP BY 1 ORDER BY 1;


SELECT * FROM fact_orders LIMIT 5;
SELECT * FROM dim_customer LIMIT 5;
