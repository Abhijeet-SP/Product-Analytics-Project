SET search_path TO analytics;

-- Cascade - Relation for auto deletion b/w parent and child table.

DROP TABLE IF EXISTS dim_city CASCADE;
CREATE TABLE dim_city (
    city_key INTEGER PRIMARY KEY,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    tier VARCHAR(10) NOT NULL,
    region VARCHAR(50) NOT NULL,
    timezone VARCHAR(50) NOT NULL,
    is_metro BOOLEAN NOT NULL,
    CONSTRAINT chk_city_tier
        CHECK (tier IN ('Metro', 'Tier 1', 'Tier 2')));

COMMENT ON TABLE dim_city IS
'Stores city master data.';


DROP TABLE IF EXISTS dim_date CASCADE;
CREATE TABLE dim_date (

    date_key            INTEGER PRIMARY KEY,
    date                DATE NOT NULL UNIQUE,
    day                 SMALLINT NOT NULL,
    week                SMALLINT NOT NULL,
    month               SMALLINT NOT NULL,
    quarter             SMALLINT NOT NULL,
    year                SMALLINT NOT NULL,
    weekday             VARCHAR(15) NOT NULL,
    is_weekend          BOOLEAN NOT NULL,

    CONSTRAINT chk_day
        CHECK (day BETWEEN 1 AND 31),

    CONSTRAINT chk_week
        CHECK (week BETWEEN 1 AND 53),

    CONSTRAINT chk_month
        CHECK (month BETWEEN 1 AND 12),

    CONSTRAINT chk_quarter
        CHECK (quarter BETWEEN 1 AND 4),

    CONSTRAINT chk_year
        CHECK (year BETWEEN 2000 AND 2100));


COMMENT ON TABLE dim_date IS
'Stores 4 year date master data, from 2022-2026.';

DROP TABLE IF EXISTS dim_customer CASCADE;
CREATE TABLE dim_customer (

    customer_key           INTEGER PRIMARY KEY,
    customer_id            VARCHAR(50) NOT NULL UNIQUE,
    signup_date            DATE NOT NULL,
    gender                 VARCHAR(20) NOT NULL,
    age_group              VARCHAR(20) NOT NULL,
    city_key               INTEGER NOT NULL,
    city                   VARCHAR(100) NOT NULL,
    persona                VARCHAR(50) NOT NULL,
    is_gold_member         BOOLEAN NOT NULL,
    device_preference      VARCHAR(30) NOT NULL,
    marketing_channel      VARCHAR(50) NOT NULL,

    CONSTRAINT chk_customer_gender
        CHECK (gender IN ('Male', 'Female', 'Other')),

    CONSTRAINT chk_customer_age_group
        CHECK (
            age_group IN (
                '18-24',
                '25-34',
                '35-44',
                '45-54',
                '55+')));

COMMENT ON TABLE dim_customer IS
'Stores master data of all the customer, company have.';

DROP TABLE IF EXISTS dim_restaurant CASCADE;
CREATE TABLE dim_restaurant (
    restaurant_key INTEGER PRIMARY KEY,
    restaurant_id VARCHAR(50) NOT NULL UNIQUE,
    restaurant_name VARCHAR(150) NOT NULL,
    cuisine VARCHAR(100) NOT NULL,
    city_key INTEGER NOT NULL,
    price_tier VARCHAR(10) NOT NULL,
    price_symbol VARCHAR(5) NOT NULL,
    rating NUMERIC(3,2) NOT NULL,
    num_ratings INTEGER NOT NULL,
    commission_rate NUMERIC(6,3) NOT NULL,
    avg_prep_time_mins SMALLINT NOT NULL,
    is_pure_veg BOOLEAN NOT NULL,

    CONSTRAINT chk_restaurant_price_tier
        CHECK (price_tier IN ('Budget', 'Mid', 'Premium')),

    CONSTRAINT chk_restaurant_rating
        CHECK (rating BETWEEN 0 AND 5),

    CONSTRAINT chk_restaurant_num_ratings
        CHECK (num_ratings >= 0),

    CONSTRAINT chk_restaurant_commission
        CHECK (commission_rate >= 0),

    CONSTRAINT chk_restaurant_prep_time
        CHECK (avg_prep_time_mins >= 0));

COMMENT ON TABLE dim_restaurant IS
'Stores master data of all the resturant tied up with company.';

DROP TABLE IF EXISTS dim_delivery_partner CASCADE;
CREATE TABLE dim_delivery_partner (
    delivery_partner_key INTEGER PRIMARY KEY,
    delivery_partner_id VARCHAR(50) NOT NULL UNIQUE,
    partner_name VARCHAR(100) NOT NULL,
    city_key INTEGER NOT NULL,
    vehicle_type VARCHAR(20) NOT NULL,
    joined_date DATE NOT NULL,
    rating NUMERIC(3,2) NOT NULL,

    CONSTRAINT chk_delivery_partner_rating
        CHECK (rating BETWEEN 0 AND 5),

    CONSTRAINT chk_delivery_partner_vehicle
        CHECK (vehicle_type IN ('Motorcycle', 'Electric Scooter', 'Bicycle')));

COMMENT ON TABLE dim_delivery_partner IS
'Stores master data of all the delivery partner tied up with company.';

DROP TABLE IF EXISTS dim_menu_item CASCADE;
CREATE TABLE dim_menu_item (
    menu_item_key INTEGER PRIMARY KEY,
    restaurant_key INTEGER NOT NULL,
    item_name VARCHAR(150) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    is_veg BOOLEAN NOT NULL,

    CONSTRAINT chk_menu_item_price
        CHECK (price >= 0));

COMMENT ON TABLE dim_menu_item IS
'Stores master data of all the resturant menus that are tied up with company.';

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'analytics'
ORDER BY table_name;