SET search_path TO analytics;

-- ============================================================
-- Indexes for the analytics star schema.
--
-- PostgreSQL automatically creates a unique index for every
-- PRIMARY KEY and UNIQUE constraint (defined in 01/02), so those
-- columns are NOT re-indexed here.
--
-- PostgreSQL does NOT automatically index FOREIGN KEY columns.
-- The fact tables are the largest and are constantly joined to
-- dimensions and filtered by date / status, so their FK and
-- common filter columns are the primary index targets. A handful
-- of high-selectivity dimension columns are indexed for the
-- typical slice-and-dice filters used by the dashboard.
--
-- Idempotent: CREATE INDEX IF NOT EXISTS lets this script re-run.
-- ============================================================


-- ------------------------------------------------------------
-- Dimension foreign keys + common filter columns
-- ------------------------------------------------------------

-- dim_customer
CREATE INDEX IF NOT EXISTS idx_customer_city_key
    ON dim_customer (city_key);
CREATE INDEX IF NOT EXISTS idx_customer_persona
    ON dim_customer (persona);
CREATE INDEX IF NOT EXISTS idx_customer_marketing_channel
    ON dim_customer (marketing_channel);
CREATE INDEX IF NOT EXISTS idx_customer_signup_date
    ON dim_customer (signup_date);
CREATE INDEX IF NOT EXISTS idx_customer_is_gold_member
    ON dim_customer (is_gold_member);

-- dim_restaurant
CREATE INDEX IF NOT EXISTS idx_restaurant_city_key
    ON dim_restaurant (city_key);
CREATE INDEX IF NOT EXISTS idx_restaurant_cuisine
    ON dim_restaurant (cuisine);
CREATE INDEX IF NOT EXISTS idx_restaurant_price_tier
    ON dim_restaurant (price_tier);

-- dim_delivery_partner
CREATE INDEX IF NOT EXISTS idx_delivery_partner_city_key
    ON dim_delivery_partner (city_key);

-- dim_menu_item
CREATE INDEX IF NOT EXISTS idx_menu_item_restaurant_key
    ON dim_menu_item (restaurant_key);
CREATE INDEX IF NOT EXISTS idx_menu_item_category
    ON dim_menu_item (category);


-- ------------------------------------------------------------
-- fact_orders  (largest fact — index every FK + hot filters)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_customer_key
    ON fact_orders (customer_key);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_key
    ON fact_orders (restaurant_key);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_partner_key
    ON fact_orders (delivery_partner_key);
CREATE INDEX IF NOT EXISTS idx_orders_city_key
    ON fact_orders (city_key);
CREATE INDEX IF NOT EXISTS idx_orders_date_key
    ON fact_orders (date_key);

CREATE INDEX IF NOT EXISTS idx_orders_order_timestamp
    ON fact_orders (order_timestamp);
CREATE INDEX IF NOT EXISTS idx_orders_order_status
    ON fact_orders (order_status);
CREATE INDEX IF NOT EXISTS idx_orders_daypart
    ON fact_orders (daypart);
CREATE INDEX IF NOT EXISTS idx_orders_payment_method
    ON fact_orders (payment_method);

-- Composite: time-series of orders for a given city (dashboard trend charts)
CREATE INDEX IF NOT EXISTS idx_orders_city_date
    ON fact_orders (city_key, date_key);


-- ------------------------------------------------------------
-- fact_order_items
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_order_items_order_key
    ON fact_order_items (order_key);
CREATE INDEX IF NOT EXISTS idx_order_items_menu_item_key
    ON fact_order_items (menu_item_key);
CREATE INDEX IF NOT EXISTS idx_order_items_restaurant_key
    ON fact_order_items (restaurant_key);
-- order_id is not unique here (one row per line item), but is used to join back
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON fact_order_items (order_id);


-- ------------------------------------------------------------
-- fact_sessions  (funnel / conversion analysis)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_sessions_customer_key
    ON fact_sessions (customer_key);
CREATE INDEX IF NOT EXISTS idx_sessions_city_key
    ON fact_sessions (city_key);
CREATE INDEX IF NOT EXISTS idx_sessions_date_key
    ON fact_sessions (date_key);

CREATE INDEX IF NOT EXISTS idx_sessions_session_start
    ON fact_sessions (session_start);
CREATE INDEX IF NOT EXISTS idx_sessions_reached_stage
    ON fact_sessions (reached_stage);
CREATE INDEX IF NOT EXISTS idx_sessions_converted
    ON fact_sessions (converted);


-- ------------------------------------------------------------
-- fact_app_events  (event stream — high volume)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_app_events_session_key
    ON fact_app_events (session_key);
CREATE INDEX IF NOT EXISTS idx_app_events_customer_key
    ON fact_app_events (customer_key);
CREATE INDEX IF NOT EXISTS idx_app_events_city_key
    ON fact_app_events (city_key);
CREATE INDEX IF NOT EXISTS idx_app_events_restaurant_key
    ON fact_app_events (restaurant_key);
CREATE INDEX IF NOT EXISTS idx_app_events_date_key
    ON fact_app_events (date_key);

CREATE INDEX IF NOT EXISTS idx_app_events_event_timestamp
    ON fact_app_events (event_timestamp);
CREATE INDEX IF NOT EXISTS idx_app_events_event_type
    ON fact_app_events (event_type);


-- ------------------------------------------------------------
-- Verify: list all indexes in the analytics schema.
-- ------------------------------------------------------------
SELECT
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'analytics'
ORDER BY tablename, indexname;
