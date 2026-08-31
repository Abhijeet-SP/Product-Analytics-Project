SET search_path TO analytics;

DROP TABLE IF EXISTS fact_orders CASCADE;
CREATE TABLE fact_orders (
    order_key INTEGER PRIMARY KEY,
    order_id VARCHAR(50) NOT NULL UNIQUE,
    customer_key INTEGER NOT NULL,
    restaurant_key INTEGER NOT NULL,
    delivery_partner_key INTEGER NOT NULL,
    city_key INTEGER NOT NULL,
    date_key INTEGER NOT NULL,
    order_timestamp TIMESTAMP NOT NULL,
    daypart VARCHAR(20) NOT NULL,
    item_count SMALLINT NOT NULL,
    food_subtotal NUMERIC(10,2) NOT NULL,
    delivery_fee NUMERIC(10,2) NOT NULL,
    platform_fee NUMERIC(10,2) NOT NULL,
    gov NUMERIC(10,2) NOT NULL,
    restaurant_funded_discount NUMERIC(10,2) NOT NULL,
    platform_funded_discount NUMERIC(10,2) NOT NULL,
    total_discount NUMERIC(10,2) NOT NULL,
    nov NUMERIC(10,2) NOT NULL,
    commission_rate NUMERIC(6,3) NOT NULL,
    commission_income NUMERIC(10,2) NOT NULL,
    contribution_margin NUMERIC(10,2) NOT NULL,
    distance_km NUMERIC(5,2) NOT NULL,
    delivery_time_mins SMALLINT,
    promised_time_mins SMALLINT NOT NULL,
    on_time BOOLEAN,
    order_status VARCHAR(30) NOT NULL,
    is_gold_order BOOLEAN NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    rating NUMERIC(2,1),

    CONSTRAINT chk_item_count
        CHECK (item_count > 0),

    CONSTRAINT chk_food_subtotal
        CHECK (food_subtotal >= 0),

    CONSTRAINT chk_delivery_fee
        CHECK (delivery_fee >= 0),

    CONSTRAINT chk_platform_fee
        CHECK (platform_fee >= 0),

    CONSTRAINT chk_gov
        CHECK (gov >= 0),

    CONSTRAINT chk_restaurant_discount
        CHECK (restaurant_funded_discount >= 0),

    CONSTRAINT chk_platform_discount
        CHECK (platform_funded_discount >= 0),

    CONSTRAINT chk_total_discount
        CHECK (total_discount >= 0),

    CONSTRAINT chk_nov
        CHECK (nov >= 0),

    CONSTRAINT chk_commission_rate
        CHECK (commission_rate >= 0),

    CONSTRAINT chk_commission_income
        CHECK (commission_income >= 0),

    -- contribution_margin can be negative: loss-making orders (discounts +
    -- delivery cost exceed revenue) are legitimate, so no lower-bound check.

    CONSTRAINT chk_distance
        CHECK (distance_km >= 0),

    CONSTRAINT chk_delivery_time
        CHECK (delivery_time_mins >= 0),

    CONSTRAINT chk_promised_time
        CHECK (promised_time_mins >= 0),

    CONSTRAINT chk_rating
        CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),

    CONSTRAINT chk_order_status
        CHECK (
            order_status IN (
                'Delivered',
                'Cancelled by Customer',
                'Cancelled by Restaurant'
            )
        ),

    CONSTRAINT chk_payment_method
        CHECK (
            payment_method IN (
                'UPI',
                'Credit Card',
                'Debit Card',
                'Net Banking',
                'Cash on Delivery',
                'Wallet')));

COMMENT ON TABLE fact_orders IS
'Stores all orders data from the customers.';

DROP TABLE IF EXISTS fact_order_items CASCADE;
CREATE TABLE fact_order_items (
    order_item_key INTEGER PRIMARY KEY,
    order_key INTEGER NOT NULL,
    order_id VARCHAR(50) NOT NULL,
    menu_item_key INTEGER NOT NULL,
    restaurant_key INTEGER NOT NULL,
    item_name VARCHAR(150) NOT NULL,
    category VARCHAR(50) NOT NULL,
    quantity SMALLINT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    line_amount NUMERIC(10,2) NOT NULL,

    CONSTRAINT chk_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_unit_price
        CHECK (unit_price >= 0),

    CONSTRAINT chk_line_amount
        CHECK (line_amount >= 0));

COMMENT ON TABLE fact_order_items IS
'Stores all order items data from the customers orders.';

DROP TABLE IF EXISTS fact_sessions CASCADE;
CREATE TABLE fact_sessions (
    session_key INTEGER PRIMARY KEY,
    session_id VARCHAR(50) NOT NULL UNIQUE,
    customer_key INTEGER NOT NULL,
    city_key INTEGER NOT NULL,
    date_key INTEGER NOT NULL,
    session_start TIMESTAMP NOT NULL,
    session_end TIMESTAMP NOT NULL,
    duration_seconds INTEGER NOT NULL,
    screens_viewed SMALLINT NOT NULL,
    reached_stage VARCHAR(30) NOT NULL,
    converted BOOLEAN NOT NULL,
    order_id VARCHAR(50),
    device VARCHAR(30) NOT NULL,

    CONSTRAINT chk_duration
        CHECK (duration_seconds >= 0),

    CONSTRAINT chk_screens_viewed
        CHECK (screens_viewed >= 0),

    CONSTRAINT chk_reached_stage
        CHECK (
            reached_stage IN (
                'app_open',
                'search',
                'restaurant_view',
                'menu_view',
                'add_to_cart',
                'checkout_start',
                'order_placed')),

    CONSTRAINT chk_device
        CHECK (
            device IN (
                'Android',
                'iOS',
                'Web')));

COMMENT ON TABLE fact_sessions IS
'Stores user funnel.';

DROP TABLE IF EXISTS fact_app_events CASCADE;
CREATE TABLE fact_app_events (
    event_key INTEGER PRIMARY KEY,
    session_key INTEGER NOT NULL,
    customer_key INTEGER NOT NULL,
    city_key INTEGER NOT NULL,
    restaurant_key INTEGER,
    date_key INTEGER NOT NULL,
    event_timestamp TIMESTAMP NOT NULL,
    event_type VARCHAR(50) NOT NULL,

    CONSTRAINT chk_event_type
        CHECK (
            event_type IN (
                'app_open',
                'search',
                'restaurant_view',
                'menu_view',
                'add_to_cart',
                'checkout_start',
                'order_placed')));

COMMENT ON TABLE fact_app_events IS
'Stores user funnel.';

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'analytics'
ORDER BY table_name;
