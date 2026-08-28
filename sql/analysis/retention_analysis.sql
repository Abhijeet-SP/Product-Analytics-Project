SET search_path TO 'analytics';

-- Monthly Churn
WITH monthly_active_user_info AS (
    SELECT 
        DISTINCT customer_key, DATE_TRUNC('month', order_timestamp)::date AS month
    FROM fact_orders
    WHERE order_status = 'Delivered'),
    
monthly_comparision AS (
    SELECT 
        customer_key, 
        month,
        LAG(month) OVER (PARTITION BY customer_key ORDER BY month) AS prev_active,
        MIN(month) OVER (PARTITION BY customer_key) AS first_month
    FROM monthly_active_user_info
    ORDER BY 2),
    
monthly_accounting AS (
    SELECT 
        month,
        COUNT(*) FILTER (WHERE month = first_month) AS new_customers,
        COUNT(*) FILTER (WHERE prev_active = (month - INTERVAL '1 month')::date) AS retained,
        COUNT(*) FILTER (WHERE prev_active IS NOT NULL
                              AND prev_active < (month - INTERVAL '1 month')::date) AS resurrected,
        COUNT(*) AS active_total
    FROM monthly_comparision
    GROUP BY 1 ORDER BY 1)

SELECT 
    month, 
    new_customers, 
    retained, 
    resurrected,
    LAG(active_total) OVER (ORDER BY month) - retained AS churned,
    active_total
FROM monthly_accounting
ORDER BY month;


-- Monthly Retention rate
WITH monthly_active_user_info AS (
    SELECT DISTINCT customer_key, DATE_TRUNC('month', order_timestamp)::date AS month
    FROM fact_orders
    WHERE order_status = 'Delivered'),
    
monthly_comparision AS (
    SELECT 
        customer_key, 
        month,
        LAG(month) OVER (PARTITION BY customer_key ORDER BY month) AS prev_active
    FROM monthly_active_user_info),

monthly_retention AS (
    SELECT month,
           COUNT(*) FILTER (WHERE prev_active = (month - INTERVAL '1 month')::date) AS retained,
           COUNT(*) AS active_total
    FROM monthly_comparision
    GROUP BY month)

SELECT 
    month, 
    retained, 
    LAG(active_total) OVER (ORDER BY month) AS prior_month_active,
    ROUND(100.0 * retained / NULLIF(LAG(active_total) OVER (ORDER BY month), 0), 1) AS mom_retention_pct
FROM monthly_retention
ORDER BY month;

-- Second order days difference (Second order latency)
WITH ranked AS (
    SELECT 
        customer_key, 
        order_timestamp,
        ROW_NUMBER() OVER (PARTITION BY customer_key ORDER BY order_timestamp) AS rn
    FROM fact_orders
    WHERE order_status = 'Delivered'),
    
gaps AS (
    SELECT 
        f.customer_key,
        EXTRACT(EPOCH FROM (s.order_timestamp - f.order_timestamp)) / 86400.0 AS days_to_second_order
    FROM ranked f
    LEFT JOIN ranked s 
        ON s.customer_key = f.customer_key AND s.rn = 2
    WHERE f.rn = 1
    ORDER BY 1
)

SELECT 
    COUNT(*) AS first_time_buyers, 
    COUNT(days_to_second_order) AS made_second_order,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 60) / NULLIF(COUNT(*), 0), 1) AS pct_second_within_60d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 30) / NULLIF(COUNT(*), 0), 1) AS pct_second_within_30d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 90) / NULLIF(COUNT(*), 0), 1)AS pct_second_within_90d,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_second_order) AS median_days_to_second
FROM gaps;


-- retention by first order
WITH customer_order_ranking AS (
    SELECT 
        customer_key, 
        order_timestamp, 
        on_time, 
        rating,
        ROW_NUMBER() OVER (PARTITION BY customer_key ORDER BY order_timestamp) AS rn
    FROM fact_orders
    WHERE order_status = 'Delivered'),

first_order_experience AS (
    SELECT 
        f.customer_key, 
        f.on_time,
        CASE 
            WHEN f.rating IS NULL THEN 'Unrated'
            WHEN f.rating BETWEEN 1 AND 2 THEN 'Rated 1-2'
            WHEN f.rating BETWEEN 4 AND 5 THEN 'Rated 4-5'
            ELSE 'Rated 3' 
        END AS rating_group,
        ROUND(EXTRACT(EPOCH FROM (s.order_timestamp - f.order_timestamp)) / 86400.0, 2) AS days_to_second_order
    FROM customer_order_ranking f
    LEFT JOIN customer_order_ranking s ON s.customer_key = f.customer_key AND s.rn = 2
    WHERE f.rn = 1)

SELECT 
    on_time, 
    rating_group, 
    COUNT(*) AS first_time_buyers,
    COUNT(days_to_second_order) AS made_second_order,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 60) / NULLIF(COUNT(*), 0), 1) AS pct_second_within_60d
FROM first_order_experience
GROUP BY 1, 2
ORDER BY 1 DESC NULLS LAST, 2;


-- weekly retention
WITH weekly_order_info_per_user AS (
    SELECT DISTINCT customer_key, DATE_TRUNC('week', order_timestamp)::date AS week
    FROM fact_orders
    WHERE order_status = 'Delivered'
    ORDER BY 2 DESC),
    
weekly_accounting AS (
    SELECT 
        customer_key, 
        week,
        LAG(week) OVER (PARTITION BY customer_key ORDER BY week) AS prev_active
    FROM weekly_order_info_per_user),
    
weekly_retention AS (
    SELECT week,
           COUNT(*) FILTER (WHERE prev_active = (week - INTERVAL '1 week')::date) AS retained,
           COUNT(*) AS active_total
    FROM weekly_accounting
    GROUP BY week)

SELECT 
    week, 
    retained, 
    LAG(active_total) OVER (ORDER BY week) AS prior_week_active,
    ROUND(100.0 * retained / NULLIF(LAG(active_total) OVER (ORDER BY week), 0), 1) AS wow_retention_pct
FROM weekly_retention
ORDER BY week;
