import os 
from pathlib import Path 

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / 'data'
SQL_DIR = PROJECT_ROOT / 'sql'

DATABASE_URL = os.environ.get(
"DATABASE_URL",
"postgresql://postgres:010506@localhost:5432/postgres"
)

EXPECTED_ROWS = {
    "dim_city": 50,
    "dim_customer": 12_000,
    "dim_date": 1_461,
    "dim_delivery_partner": 2_500,
    "dim_menu_item": 15_547,
    "dim_restaurant": 1_500,
    "fact_order_items": 330_270,
    "fact_sessions": 273_257,
    "fact_app_events": 730_651,
    }

LOAD_ORDER = [
    "dim_city", 
    "dim_date", 
    "dim_customer",
    "dim_restaurant",
    "dim_delivery_partner", 
    "dim_menu_item",
    "fact_orders",
    "fact_order_items",
    "fact_sessions", 
    "fact_app_events",
    ]

SQL_FILES = [
    "ddl/00_create_schema.sql",
    "ddl/01_create_dimension.sql",
    "ddl/02_create_facts.sql",
    "ddl/03_constraint.sql",
    "indexes/04_indexes.sql",
    ]