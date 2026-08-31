SET search_path TO 'analytics';

-- session funnel analysis
WITH stage_order (stage, ord) AS (
    VALUES 
        ('app_open', 1), 
        ('search', 2), 
        ('restaurant_view', 3), 
        ('menu_view', 4),
        ('add_to_cart', 5), 
        ('checkout_start', 6), 
        ('order_placed', 7)),

session_reached AS (
    SELECT 
        so.stage, 
        so.ord,
        SUM(COUNT(*)) OVER(ORDER BY so.ord DESC) AS sessions_reaching
    FROM fact_sessions AS s
    JOIN stage_order AS so 
        ON so.stage = s.reached_stage
    GROUP BY so.stage, so.ord)

SELECT 
    stage, 
    sessions_reaching,
    ROUND(100.0 * sessions_reaching / FIRST_VALUE(sessions_reaching) OVER(ORDER BY ord), 2) AS pct_of_sessions,
    ROUND(100.0 * sessions_reaching / LAG(sessions_reaching) OVER(ORDER BY ord), 2) AS step_conversion_pct
FROM session_reached
ORDER BY ord;

-- device type session funnel analysis
WITH stage_order (stage, ord) AS (
    VALUES 
        ('app_open', 1), 
        ('search', 2), 
        ('restaurant_view', 3), 
        ('menu_view', 4),
        ('add_to_cart', 5), 
        ('checkout_start', 6), 
        ('order_placed', 7)),

session_reached AS (
    SELECT 
        so.stage, 
        so.ord, 
        s.device,
        SUM(COUNT(*)) OVER(PARTITION BY s.device ORDER BY so.ord DESC) AS sessions_reaching
    FROM fact_sessions AS s
    JOIN stage_order AS so 
        ON so.stage = s.reached_stage
    GROUP BY so.stage, so.ord, s.device)

SELECT 
    device, 
    stage, 
    sessions_reaching,
    ROUND(100.0 * sessions_reaching / FIRST_VALUE(sessions_reaching) OVER(PARTITION BY device ORDER BY ord), 2) AS pct_of_device_sessions,
    ROUND(100.0 * sessions_reaching / LAG(sessions_reaching) OVER(PARTITION BY device ORDER BY ord), 2) AS step_conversion_pct
FROM session_reached
ORDER BY device, ord;

-- event funnel cross-check
WITH stage_order (stage, ord) AS (
    VALUES 
        ('app_open', 1), 
        ('search', 2), 
        ('restaurant_view', 3), 
        ('menu_view', 4),
        ('add_to_cart', 5), 
        ('checkout_start', 6), 
        ('order_placed', 7)),

events AS (
    SELECT
        so.stage, 
        so.ord, 
        COUNT(DISTINCT e.session_key) AS sessions_reaching
    FROM stage_order AS so
    LEFT JOIN fact_app_events AS e 
        ON e.event_type = so.stage
    GROUP BY so.stage, so.ord)

SELECT 
    stage, 
    sessions_reaching,
    ROUND(100.0 * sessions_reaching / FIRST_VALUE(sessions_reaching) OVER(ORDER BY ord), 2) AS pct_of_sessions,
    ROUND(100.0 * sessions_reaching / LAG(sessions_reaching) OVER(ORDER BY ord), 2) AS step_conversion_pct
FROM events
ORDER BY ord;

-- engagement depth versus conversion
WITH d AS (
    SELECT 
        converted, 
        screens_viewed,
        NTILE(10) OVER(ORDER BY duration_seconds) AS duration_decile
    FROM fact_sessions)

SELECT 
    duration_decile, 
    COUNT(*) AS sessions,
    ROUND(100.0 * COUNT(*) FILTER(WHERE converted) / COUNT(*), 1) AS conversion_pct,
    ROUND(AVG(screens_viewed), 1) AS avg_screens
FROM d
GROUP BY duration_decile
ORDER BY duration_decile;

-- abandoned add-to-cart and checkout sessions
WITH abandonment AS (
    SELECT 
        s.device, 
        ci.tier, 
        c.is_gold_member, 
        s.reached_stage,
        CASE 
            WHEN EXTRACT(HOUR FROM s.session_start) BETWEEN 6 AND 10 THEN 'breakfast'
            WHEN EXTRACT(HOUR FROM s.session_start) BETWEEN 11 AND 14 THEN 'lunch'
            WHEN EXTRACT(HOUR FROM s.session_start) BETWEEN 15 AND 17 THEN 'snacks'
            WHEN EXTRACT(HOUR FROM s.session_start) BETWEEN 18 AND 22 THEN 'dinner'
            ELSE 'late_night' 
        END AS daypart
    FROM fact_sessions AS s
    JOIN dim_customer AS c 
        ON c.customer_key = s.customer_key
    JOIN dim_city AS ci 
        ON ci.city_key = s.city_key
    WHERE s.reached_stage IN ('add_to_cart', 'checkout_start')
      AND NOT s.converted)

SELECT 
    device, 
    tier, 
    is_gold_member, 
    daypart, 
    reached_stage, 
    COUNT(*) AS abandoned_sessions
FROM abandonment
GROUP BY device, tier, is_gold_member, daypart, reached_stage
ORDER BY abandoned_sessions DESC;

-- time to convert by device
SELECT 
    device, 
    COUNT(*) AS converted_sessions,
    PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY duration_seconds) AS p50_duration_seconds,
    PERCENTILE_CONT(0.9) WITHIN GROUP(ORDER BY duration_seconds) AS p90_duration_seconds,
    ROUND(AVG(screens_viewed), 1) AS avg_screens_viewed
FROM fact_sessions
WHERE converted
GROUP BY device
ORDER BY device;
