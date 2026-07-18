SET search_path TO analytics;

-- ------------------------------------------------------------
-- Dimension -> Dimensions
-- ------------------------------------------------------------

-- city key relation
ALTER TABLE dim_customer
    DROP CONSTRAINT IF EXISTS fk_customer_city;
ALTER TABLE dim_customer
    ADD CONSTRAINT fk_customer_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key);

ALTER TABLE dim_restaurant
    DROP CONSTRAINT IF EXISTS fk_restaurant_city;
ALTER TABLE dim_restaurant
    ADD CONSTRAINT fk_restaurant_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key);

ALTER TABLE dim_delivery_partner
    DROP CONSTRAINT IF EXISTS fk_delivery_partner_city;
ALTER TABLE dim_delivery_partner
    ADD CONSTRAINT fk_delivery_partner_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key);

-- resturant key relation
ALTER TABLE dim_menu_item
    DROP CONSTRAINT IF EXISTS fk_menu_item_restaurant;
ALTER TABLE dim_menu_item
    ADD CONSTRAINT fk_menu_item_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dim_restaurant (restaurant_key);

-- ------------------------------------------------------------
-- fact_orders -> dimensions
-- ------------------------------------------------------------

-- customer key relation
ALTER TABLE fact_orders
    DROP CONSTRAINT IF EXISTS fk_orders_customer;
ALTER TABLE fact_orders
    ADD CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_key) REFERENCES dim_customer (customer_key);

-- order key relation
ALTER TABLE fact_orders
    DROP CONSTRAINT IF EXISTS fk_orders_restaurant;
ALTER TABLE fact_orders
    ADD CONSTRAINT fk_orders_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dim_restaurant (restaurant_key);

-- delivery partner key relation
ALTER TABLE fact_orders
    DROP CONSTRAINT IF EXISTS fk_orders_delivery_partner;
ALTER TABLE fact_orders
    ADD CONSTRAINT fk_orders_delivery_partner
        FOREIGN KEY (delivery_partner_key) REFERENCES dim_delivery_partner (delivery_partner_key);

-- city key relation
ALTER TABLE fact_orders
    DROP CONSTRAINT IF EXISTS fk_orders_city;
ALTER TABLE fact_orders
    ADD CONSTRAINT fk_orders_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key);
-- date key relation
ALTER TABLE fact_orders
    DROP CONSTRAINT IF EXISTS fk_orders_date;
ALTER TABLE fact_orders
    ADD CONSTRAINT fk_orders_date
        FOREIGN KEY (date_key) REFERENCES dim_date (date_key);

-- ------------------------------------------------------------
-- fact_order_items -> fact_orders / Dimensions
-- ------------------------------------------------------------

ALTER TABLE fact_order_items
    DROP CONSTRAINT IF EXISTS fk_order_items_order;
ALTER TABLE fact_order_items
    ADD CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_key) REFERENCES fact_orders (order_key);

ALTER TABLE fact_order_items
    DROP CONSTRAINT IF EXISTS fk_order_items_menu_item;
ALTER TABLE fact_order_items
    ADD CONSTRAINT fk_order_items_menu_item
        FOREIGN KEY (menu_item_key) REFERENCES dim_menu_item (menu_item_key);

ALTER TABLE fact_order_items
    DROP CONSTRAINT IF EXISTS fk_order_items_restaurant;
ALTER TABLE fact_order_items
    ADD CONSTRAINT fk_order_items_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dim_restaurant (restaurant_key);


-- ------------------------------------------------------------
-- fact_sessions -> Dimensions
-- ------------------------------------------------------------

ALTER TABLE fact_sessions
    DROP CONSTRAINT IF EXISTS fk_sessions_customer;
ALTER TABLE fact_sessions
    ADD CONSTRAINT fk_sessions_customer
        FOREIGN KEY (customer_key) REFERENCES dim_customer (customer_key);

ALTER TABLE fact_sessions
    DROP CONSTRAINT IF EXISTS fk_sessions_city;
ALTER TABLE fact_sessions
    ADD CONSTRAINT fk_sessions_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key);

ALTER TABLE fact_sessions
    DROP CONSTRAINT IF EXISTS fk_sessions_date;
ALTER TABLE fact_sessions
    ADD CONSTRAINT fk_sessions_date
        FOREIGN KEY (date_key) REFERENCES dim_date (date_key);


-- ------------------------------------------------------------
-- fact_app_events -> fact_sessions / Dimensions
-- ------------------------------------------------------------

ALTER TABLE fact_app_events
    DROP CONSTRAINT IF EXISTS fk_app_events_session;
ALTER TABLE fact_app_events
    ADD CONSTRAINT fk_app_events_session
        FOREIGN KEY (session_key) REFERENCES fact_sessions (session_key);

ALTER TABLE fact_app_events
    DROP CONSTRAINT IF EXISTS fk_app_events_customer;
ALTER TABLE fact_app_events
    ADD CONSTRAINT fk_app_events_customer
        FOREIGN KEY (customer_key) REFERENCES dim_customer (customer_key);

ALTER TABLE fact_app_events
    DROP CONSTRAINT IF EXISTS fk_app_events_city;
ALTER TABLE fact_app_events
    ADD CONSTRAINT fk_app_events_city
        FOREIGN KEY (city_key) REFERENCES dim_city (city_key);

ALTER TABLE fact_app_events
    DROP CONSTRAINT IF EXISTS fk_app_events_restaurant;
ALTER TABLE fact_app_events
    ADD CONSTRAINT fk_app_events_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dim_restaurant (restaurant_key);

ALTER TABLE fact_app_events
    DROP CONSTRAINT IF EXISTS fk_app_events_date;
ALTER TABLE fact_app_events
    ADD CONSTRAINT fk_app_events_date
        FOREIGN KEY (date_key) REFERENCES dim_date (date_key);


-- ------------------------------------------------------------
-- Verify: list all foreign keys in the analytics schema.
-- ------------------------------------------------------------
SELECT
    tc.table_name,
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name  AS references_table,
    ccu.column_name AS references_column
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema    = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema    = 'analytics'
ORDER BY tc.table_name, tc.constraint_name;

