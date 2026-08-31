SET search_path TO 'analytics';

-- Monthly cohort retention analysis for 12 months
WITH first_order_for_each_customer AS (
    SELECT 
        customer_key, 
        DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort_month
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_key),
    
customer_activity AS (
    SELECT DISTINCT 
        o.customer_key, 
        f.cohort_month,
        (EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', o.order_timestamp), f.cohort_month)) * 12
            + 
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_timestamp), f.cohort_month)))::int AS month_index
    FROM fact_orders AS o
    JOIN first_order_for_each_customer AS f 
        ON o.customer_key = f.customer_key
     WHERE order_status = 'Delivered'),
   
cohort_size AS (
    SELECT 
        cohort_month, 
        COUNT(*) AS size
    FROM first_order_for_each_customer
    GROUP BY cohort_month)

SELECT 
    a.cohort_month, 
    cs.size AS cohort_size, 
    a.month_index,
    COUNT(*) AS active_customers,
    ROUND(100.0 * COUNT(*) / cs.size, 1) AS retention_pct
FROM customer_activity AS a
JOIN cohort_size AS cs 
    ON a.cohort_month = cs.cohort_month
WHERE a.month_index <= 12
GROUP BY 1, 2, 3
ORDER BY 1, 3;


-- Monthly cohort gov analysis for 12 months
WITH first_order_for_each_customer AS (
    SELECT 
        customer_key, 
        DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort_month
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_key),
    
customer_activity AS (
    SELECT 
        f.cohort_month,
        (EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', o.order_timestamp), f.cohort_month)) * 12
          + 
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_timestamp), f.cohort_month)))::int AS month_index,
        SUM(o.gov) AS gov
    FROM fact_orders AS o
    JOIN first_order_for_each_customer AS f 
        ON o.customer_key = f.customer_key 
    WHERE o.order_status = 'Delivered'
    GROUP BY 1, DATE_TRUNC('month', o.order_timestamp)),

cohort_size AS (
    SELECT cohort_month, COUNT(*) AS size
    FROM first_order_for_each_customer
    GROUP BY cohort_month
)

SELECT 
    a.cohort_month, 
    a.month_index, 
    cs.size AS cohort_size, 
    a.gov,
    ROUND(SUM(a.gov) OVER (PARTITION BY a.cohort_month ORDER BY a.month_index) / cs.size, 2) AS cumulative_gov_per_acquired_customer
FROM customer_activity AS a
JOIN cohort_size AS cs 
    ON a.cohort_month = cs.cohort_month 
WHERE a.month_index <= 12
ORDER BY 1, 2;

-- Cohorts by acquisition channel 
WITH first_order_for_each_customer AS (
    SELECT 
        o.customer_key, 
        c.marketing_channel,
        DATE_TRUNC('month', MIN(o.order_timestamp))::date AS cohort_month
    FROM fact_orders AS o
    JOIN dim_customer AS c 
        ON c.customer_key = o.customer_key
    WHERE o.order_status = 'Delivered'
    GROUP BY 1, 2),
    
customer_activity AS (
    SELECT DISTINCT 
        o.customer_key, 
        f.marketing_channel, 
        f.cohort_month,
        (EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', o.order_timestamp), f.cohort_month)) * 12
          + 
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_timestamp), f.cohort_month)))::int AS month_index
    FROM fact_orders AS o
    JOIN first_order_for_each_customer AS f 
        ON o.customer_key = f.customer_key 
    WHERE o.order_status = 'Delivered'),

cohort_size AS (
    SELECT 
        marketing_channel, 
        cohort_month, COUNT(*) AS size
    FROM first_order_for_each_customer
    GROUP BY 1, 2
)

SELECT 
    a.marketing_channel, 
    a.cohort_month, 
    a.month_index, 
    cs.size AS cohort_size,
    COUNT(*) AS active_customers,
    ROUND(100.0 * COUNT(*) / NULLIF(cs.size, 0), 1) AS retention_pct
FROM customer_activity AS a
JOIN cohort_size AS cs
  ON cs.marketing_channel = a.marketing_channel AND 
     cs.cohort_month = a.cohort_month
WHERE a.month_index IN (1, 3, 6)
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3;

-- cohort by signup vs first_order
WITH first_order_for_each_customer AS (
    SELECT 
        customer_key, 
        DATE_TRUNC('month', MIN(order_timestamp))::date AS first_order_month
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY 1),

signup_cohorts AS (
    SELECT 
        c.customer_key, 
        DATE_TRUNC('month', c.signup_date)::date AS signup_month,
        f.first_order_month
    FROM dim_customer AS c
    LEFT JOIN first_order_for_each_customer AS f 
        ON f.customer_key = c.customer_key)

SELECT 
    signup_month, 
    COUNT(*) AS signups,
    COUNT(first_order_month) AS customers_who_ordered,
    ROUND(100.0 * COUNT(first_order_month) / NULLIF(COUNT(*), 0), 1) AS signup_to_first_order_pct
FROM signup_cohorts
GROUP BY 1
ORDER BY 1;
