SET search_path TO analytics;

TRUNCATE
    dim_city,
    dim_date,
    dim_customer,
    dim_restaurant,
    dim_delivery_partner,
    dim_menu_item,
    fact_orders,
    fact_order_items,
    fact_sessions,
    fact_app_events
CASCADE;

-- Dimensions (dim_city and dim_date first: others reference them)
\copy dim_city FROM 'data/dim_city.csv' WITH (FORMAT csv, HEADER true)
\copy dim_date FROM 'data/dim_date.csv' WITH (FORMAT csv, HEADER true)
\copy dim_customer FROM 'data/dim_customer.csv' WITH (FORMAT csv, HEADER true)
\copy dim_restaurant FROM 'data/dim_restaurant.csv' WITH (FORMAT csv, HEADER true)
\copy dim_delivery_partner FROM 'data/dim_delivery_partner.csv' WITH (FORMAT csv, HEADER true)
\copy dim_menu_item FROM 'data/dim_menu_item.csv' WITH (FORMAT csv, HEADER true)

-- Facts (fact_orders before fact_order_items; fact_sessions before fact_app_events)
\copy fact_orders FROM 'data/fact_orders.csv' WITH (FORMAT csv, HEADER true)
\copy fact_order_items FROM 'data/fact_order_items.csv' WITH (FORMAT csv, HEADER true)
\copy fact_sessions FROM 'data/fact_sessions.csv' WITH (FORMAT csv, HEADER true)
\copy fact_app_events FROM 'data/fact_app_events.csv' WITH (FORMAT csv, HEADER true)

-- Verify: row count per table
SELECT 'dim_city' AS table_name, COUNT(*) FROM dim_city
UNION ALL SELECT 'dim_date', COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_restaurant', COUNT(*) FROM dim_restaurant
UNION ALL SELECT 'dim_delivery_partner', COUNT(*) FROM dim_delivery_partner
UNION ALL SELECT 'dim_menu_item', COUNT(*) FROM dim_menu_item
UNION ALL SELECT 'fact_orders', COUNT(*) FROM fact_orders
UNION ALL SELECT 'fact_order_items', COUNT(*) FROM fact_order_items
UNION ALL SELECT 'fact_sessions', COUNT(*) FROM fact_sessions
UNION ALL SELECT 'fact_app_events', COUNT(*) FROM fact_app_events
ORDER BY table_name;
