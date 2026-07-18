"""Synthetic analytics-warehouse generator for a food-delivery marketplace (Zomato / Eternal).

Produces a star-schema warehouse as CSV for import into PostgreSQL and downstream
SQL / BI / product-analytics work. The schema and metric vocabulary are deliberately
aligned with how Eternal (parent of Zomato) reports its food-delivery business, so the
dataset doubles as a way to reason in their terms.

Core metric spine (all queryable off ``fact_orders``):
  * GOV   -- Gross Order Value (what the customer would pay pre-discount)
  * NOV   -- Net Order Value = GOV - discounts (Eternal's current headline metric)
  * AOV   -- Average Order Value
  * MTU   -- Monthly Transacting Users (derivable from orders x customer x date)
  * take rate, commission income, per-order contribution margin, delivery SLA

Design notes
------------
* **Orders are the complete spine.** Every order is generated from a per-customer
  behavioural simulation (persona x engagement x tenure), so money metrics, cohorts and
  CLV are fully populated.
* **Funnel is real.** ``fact_sessions`` covers converting *and* abandoning sessions
  (session-level funnel via ``reached_stage`` / ``converted``), and ``fact_app_events``
  is the event-level trail joined on the integer ``session_key`` surrogate. Converting
  sessions link to their order via ``fact_sessions.order_id``.
* **Distributions, not uniform noise:** restaurant popularity ~ Zipf long tail, order
  frequency ~ log-normal, engagement ~ exponential decay, signups ~ growth + seasonality,
  daypart/day-of-week seasonality on order timestamps.
* **Reproducible:** ``random`` / ``numpy`` / ``Faker`` seeded; business ids use
  deterministic ``uuid5``.

Libraries: pandas, numpy, faker, tqdm (+ stdlib). Output: CSV only.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass
from datetime import date, datetime, time as dtime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from faker import Faker
from tqdm import tqdm

# ======================================================================================
# CONFIGURATION
# ======================================================================================


@dataclass(frozen=True)
class Config:
    """Tunable knobs. Two instances below; flip :data:`FULL_SCALE` to switch."""

    seed: int = 42
    as_of_date: date = date(2026, 6, 30)          # no timestamp may exceed this
    date_start: date = date(2023, 1, 1)           # dim_date span (may exceed as_of)
    date_end: date = date(2026, 12, 31)

    # Exact-size dimensions.
    n_customers: int = 12_000
    n_restaurants: int = 1_500
    n_delivery_partners: int = 2_500
    n_cities: int = 50

    # Emergent-size targets (tune distributions; not hard counts).
    target_orders: int = 150_000
    session_conversion: float = 0.55              # order-sessions / all sessions
    mean_items_per_order: float = 2.2
    event_sample_rate: float = 0.5                # share of sessions with a granular
    #                                               event trail in fact_app_events
    #   (fact_sessions is always complete; the event log is a representative sample,
    #    mirroring how real warehouses expose full transactions + sampled clickstream)

    output_dir: Path = Path("data")


DEFAULT_CONFIG = Config()

FULL_SCALE_CONFIG = Config(
    n_customers=120_000,
    n_restaurants=8_000,
    n_delivery_partners=20_000,
    target_orders=1_500_000,
    output_dir=Path("data_full"),
)

# Flip to True for the full-scale dataset (large CSVs -> use Git LFS / keep out of repo).
FULL_SCALE = False

_UUID_NS = uuid.uuid5(uuid.NAMESPACE_DNS, "zomato-delivery-warehouse")
CURRENCY = "INR"


# --------------------------------------------------------------------------------------
# Reference data (scale-independent).
# --------------------------------------------------------------------------------------

# Customer personas drive frequency, price tier, discount sensitivity, daypart, Gold.
# weight       : share of base
# freq_mult    : relative order volume
# tier_pref    : (budget, mid, premium) preference over restaurant price tiers -> drives AOV
# disc_sens    : discount sensitivity (0..1) -> bigger platform-funded discounts
# gold_prob    : probability of Zomato Gold membership
# rating_prob  : probability of rating a delivered order
# daypart_w    : (breakfast, lunch, snacks, dinner, late_night) weights
# decay_mean   : engagement half-life driver (higher => more retained)
# churn_prob   : probability of going inactive before as_of
PERSONAS: Dict[str, Dict[str, object]] = {
    "habitual_regular": {
        "weight": 0.22, "freq_mult": 1.9, "tier_pref": (0.35, 0.45, 0.20),
        "disc_sens": 0.35, "gold_prob": 0.45, "rating_prob": 0.28,
        "daypart_w": (0.10, 0.34, 0.14, 0.38, 0.04), "decay_mean": 430.0, "churn_prob": 0.22,
    },
    "value_seeker": {
        "weight": 0.28, "freq_mult": 1.0, "tier_pref": (0.62, 0.31, 0.07),
        "disc_sens": 0.85, "gold_prob": 0.12, "rating_prob": 0.22,
        "daypart_w": (0.08, 0.30, 0.18, 0.40, 0.04), "decay_mean": 220.0, "churn_prob": 0.45,
    },
    "premium_foodie": {
        "weight": 0.12, "freq_mult": 1.2, "tier_pref": (0.10, 0.35, 0.55),
        "disc_sens": 0.20, "gold_prob": 0.60, "rating_prob": 0.45,
        "daypart_w": (0.07, 0.26, 0.13, 0.46, 0.08), "decay_mean": 460.0, "churn_prob": 0.25,
    },
    "occasional": {
        "weight": 0.26, "freq_mult": 0.45, "tier_pref": (0.42, 0.40, 0.18),
        "disc_sens": 0.50, "gold_prob": 0.10, "rating_prob": 0.20,
        "daypart_w": (0.09, 0.28, 0.15, 0.42, 0.06), "decay_mean": 180.0, "churn_prob": 0.55,
    },
    "night_owl": {
        "weight": 0.12, "freq_mult": 1.1, "tier_pref": (0.40, 0.42, 0.18),
        "disc_sens": 0.55, "gold_prob": 0.22, "rating_prob": 0.24,
        "daypart_w": (0.03, 0.14, 0.13, 0.40, 0.30), "decay_mean": 260.0, "churn_prob": 0.40,
    },
}

# 50 Indian cities: (city, state, tier, region, demand weight). Metros dominate demand.
CITY_DATA: List[Tuple[str, str, str, str, float]] = [
    ("Bengaluru", "Karnataka", "Metro", "South", 10.0),
    ("Delhi", "Delhi", "Metro", "North", 9.5),
    ("Mumbai", "Maharashtra", "Metro", "West", 9.0),
    ("Hyderabad", "Telangana", "Metro", "South", 7.5),
    ("Pune", "Maharashtra", "Metro", "West", 6.5),
    ("Chennai", "Tamil Nadu", "Metro", "South", 6.0),
    ("Kolkata", "West Bengal", "Metro", "East", 5.5),
    ("Gurugram", "Haryana", "Metro", "North", 5.0),
    ("Noida", "Uttar Pradesh", "Metro", "North", 4.5),
    ("Ahmedabad", "Gujarat", "Metro", "West", 4.0),
    ("Jaipur", "Rajasthan", "Tier 1", "North", 3.2),
    ("Lucknow", "Uttar Pradesh", "Tier 1", "North", 2.8),
    ("Chandigarh", "Chandigarh", "Tier 1", "North", 2.6),
    ("Kochi", "Kerala", "Tier 1", "South", 2.4),
    ("Indore", "Madhya Pradesh", "Tier 1", "Central", 2.4),
    ("Coimbatore", "Tamil Nadu", "Tier 1", "South", 2.1),
    ("Nagpur", "Maharashtra", "Tier 1", "Central", 2.0),
    ("Surat", "Gujarat", "Tier 1", "West", 2.0),
    ("Bhubaneswar", "Odisha", "Tier 1", "East", 1.8),
    ("Vadodara", "Gujarat", "Tier 1", "West", 1.7),
    ("Visakhapatnam", "Andhra Pradesh", "Tier 1", "South", 1.7),
    ("Bhopal", "Madhya Pradesh", "Tier 1", "Central", 1.6),
    ("Nashik", "Maharashtra", "Tier 1", "West", 1.5),
    ("Kanpur", "Uttar Pradesh", "Tier 1", "North", 1.5),
    ("Thiruvananthapuram", "Kerala", "Tier 1", "South", 1.5),
    ("Mysuru", "Karnataka", "Tier 2", "South", 1.2),
    ("Mangaluru", "Karnataka", "Tier 2", "South", 1.1),
    ("Guwahati", "Assam", "Tier 2", "East", 1.1),
    ("Ranchi", "Jharkhand", "Tier 2", "East", 1.0),
    ("Raipur", "Chhattisgarh", "Tier 2", "Central", 1.0),
    ("Dehradun", "Uttarakhand", "Tier 2", "North", 1.0),
    ("Amritsar", "Punjab", "Tier 2", "North", 1.0),
    ("Ludhiana", "Punjab", "Tier 2", "North", 1.0),
    ("Jodhpur", "Rajasthan", "Tier 2", "North", 0.9),
    ("Udaipur", "Rajasthan", "Tier 2", "North", 0.9),
    ("Varanasi", "Uttar Pradesh", "Tier 2", "North", 0.9),
    ("Agra", "Uttar Pradesh", "Tier 2", "North", 0.9),
    ("Madurai", "Tamil Nadu", "Tier 2", "South", 0.9),
    ("Vijayawada", "Andhra Pradesh", "Tier 2", "South", 0.9),
    ("Guntur", "Andhra Pradesh", "Tier 2", "South", 0.8),
    ("Rajkot", "Gujarat", "Tier 2", "West", 0.8),
    ("Siliguri", "West Bengal", "Tier 2", "East", 0.8),
    ("Warangal", "Telangana", "Tier 2", "South", 0.8),
    ("Jalandhar", "Punjab", "Tier 2", "North", 0.8),
    ("Aurangabad", "Maharashtra", "Tier 2", "West", 0.8),
    ("Patna", "Bihar", "Tier 2", "East", 0.9),
    ("Kota", "Rajasthan", "Tier 2", "North", 0.7),
    ("Gwalior", "Madhya Pradesh", "Tier 2", "Central", 0.7),
    ("Jamshedpur", "Jharkhand", "Tier 2", "East", 0.7),
    ("Meerut", "Uttar Pradesh", "Tier 2", "North", 0.7),
]

# Delivery-speed proxy by city tier (metros faster due to density; congestion nets out).
TIER_PARTNER_SPEED = {"Metro": 1.12, "Tier 1": 1.0, "Tier 2": 0.9}

# Cuisines with demand weights and a small dish pool for realistic item names.
CUISINE_DISHES: Dict[str, List[str]] = {
    "North Indian": ["Paneer Butter Masala", "Dal Makhani", "Butter Naan", "Chicken Curry",
                     "Chole Bhature", "Rajma Chawal", "Shahi Paneer", "Tandoori Roti"],
    "South Indian": ["Masala Dosa", "Idli Sambar", "Medu Vada", "Filter Coffee",
                     "Uttapam", "Curd Rice", "Rava Dosa", "Pongal"],
    "Chinese": ["Veg Hakka Noodles", "Chilli Chicken", "Veg Manchurian", "Fried Rice",
                "Chicken Momos", "Schezwan Noodles", "Spring Roll", "Chilli Paneer"],
    "Biryani": ["Chicken Biryani", "Veg Biryani", "Mutton Biryani", "Egg Biryani",
                "Hyderabadi Dum Biryani", "Chicken 65", "Boneless Biryani"],
    "Fast Food": ["Veg Burger", "French Fries", "Cheese Sandwich", "Veg Wrap",
                  "Peri Peri Fries", "Chicken Burger", "Nuggets"],
    "Pizza": ["Margherita Pizza", "Farmhouse Pizza", "Peppy Paneer Pizza",
              "Chicken Supreme Pizza", "Garlic Bread", "Cheese Burst Pizza"],
    "Rolls": ["Chicken Roll", "Paneer Roll", "Egg Roll", "Veg Frankie", "Double Egg Roll"],
    "Desserts": ["Gulab Jamun", "Chocolate Brownie", "Rasmalai", "Ice Cream Tub",
                 "Choco Lava Cake", "Gajar Halwa"],
    "Beverages": ["Cold Coffee", "Mango Lassi", "Masala Chai", "Fresh Lime Soda",
                  "Cold Drink", "Buttermilk"],
    "Cafe": ["Cappuccino", "Veg Sandwich", "Pasta Alfredo", "Chocolate Shake",
             "Croissant", "Club Sandwich"],
    "Mughlai": ["Chicken Korma", "Mutton Rogan Josh", "Seekh Kebab", "Galouti Kebab"],
    "Street Food": ["Pav Bhaji", "Vada Pav", "Samosa", "Pani Puri", "Dahi Puri", "Kachori"],
    "Healthy": ["Quinoa Salad", "Grilled Chicken Bowl", "Fruit Bowl", "Sprout Salad"],
}
CUISINES = list(CUISINE_DISHES.keys())
CUISINE_WEIGHTS = np.array([
    0.16, 0.11, 0.12, 0.13, 0.10, 0.08, 0.05, 0.06, 0.04, 0.05, 0.03, 0.05, 0.02,
])[: len(CUISINES)]

# Price tiers: base per-item price band (INR) and demand weight.
PRICE_TIERS = {
    "Budget":  {"symbol": "\u20b9",    "band": (60, 150),  "w": 0.40},
    "Mid":     {"symbol": "\u20b9\u20b9", "band": (110, 260), "w": 0.45},
    "Premium": {"symbol": "\u20b9\u20b9\u20b9", "band": (240, 520), "w": 0.15},
}
TIER_NAMES = list(PRICE_TIERS.keys())

PAYMENT_METHODS = ["UPI", "Credit Card", "Debit Card", "Wallet", "Cash on Delivery", "Net Banking"]
PAYMENT_METHOD_WEIGHTS = np.array([0.55, 0.11, 0.08, 0.10, 0.11, 0.05])

MARKETING_CHANNELS = ["Organic", "Google Ads", "Instagram Ads", "Referral", "Push Notification", "Offers/CRM"]
MARKETING_CHANNEL_WEIGHTS = np.array([0.32, 0.18, 0.16, 0.14, 0.10, 0.10])

DEVICE_PREFS = ["Android", "iOS", "Web"]
DEVICE_PREF_WEIGHTS = np.array([0.68, 0.26, 0.06])

GENDERS = ["Male", "Female", "Other"]
GENDER_WEIGHTS = np.array([0.55, 0.43, 0.02])
AGE_GROUPS = ["18-24", "25-34", "35-44", "45-54", "55+"]
AGE_GROUP_WEIGHTS = np.array([0.26, 0.42, 0.19, 0.09, 0.04])

ORDER_STATUSES = ["Delivered", "Cancelled by Customer", "Cancelled by Restaurant"]
ORDER_STATUS_WEIGHTS = np.array([0.955, 0.030, 0.015])

VEHICLE_TYPES = ["Motorcycle", "Bicycle", "Electric Scooter"]
VEHICLE_TYPE_WEIGHTS = np.array([0.78, 0.10, 0.12])

# Dayparts: index -> (label, hour_start, hour_end).
DAYPARTS = [
    ("Breakfast", 6, 10),
    ("Lunch", 11, 15),
    ("Snacks", 15, 18),
    ("Dinner", 18, 23),
    ("Late Night", 23, 30),  # wraps past midnight (mod 24 applied later)
]
# Day-of-week weights (Mon=0). Weekends lift.
DOW_WEIGHTS = np.array([0.92, 0.90, 0.94, 1.00, 1.18, 1.35, 1.28])

# Fast hour -> daypart label lookup (24 entries).
DAYPART_BY_HOUR = np.array(
    ["Late Night"] * 6 + ["Breakfast"] * 5 + ["Lunch"] * 4 +
    ["Snacks"] * 3 + ["Dinner"] * 5 + ["Late Night"] * 1
)

# App funnel stages in order; a session reaches up to some stage then converts or abandons.
FUNNEL_STAGES = ["app_open", "search", "restaurant_view", "menu_view",
                 "add_to_cart", "checkout_start", "order_placed"]
# Abandonment stage weights for NON-converting sessions (most drop early).
ABANDON_STAGE_W = np.array([0.10, 0.22, 0.26, 0.18, 0.14, 0.10])  # over stages 0..5


# ======================================================================================
# HELPERS
# ======================================================================================


def make_rng(seed: int) -> np.random.Generator:
    random.seed(seed)
    np.random.seed(seed)
    Faker.seed(seed)
    return np.random.default_rng(seed)


def business_id(prefix: str, key: int) -> str:
    return f"{prefix}-{uuid.uuid5(_UUID_NS, f'{prefix}:{key}')}"


def to_date_key(ts: datetime) -> int:
    return ts.year * 10_000 + ts.month * 100 + ts.day


def wchoice(rng: np.random.Generator, weights: np.ndarray, size: int) -> np.ndarray:
    p = weights / weights.sum()
    return rng.choice(len(weights), size=size, p=p)


# ======================================================================================
# DIMENSION BUILDERS
# ======================================================================================


def build_dim_date(cfg: Config) -> pd.DataFrame:
    dates = pd.date_range(cfg.date_start, cfg.date_end, freq="D")
    iso = dates.isocalendar()
    return pd.DataFrame({
        "date_key": dates.year * 10_000 + dates.month * 100 + dates.day,
        "date": dates.date,
        "day": dates.day,
        "week": iso["week"].to_numpy(),
        "month": dates.month,
        "quarter": dates.quarter,
        "year": dates.year,
        "weekday": dates.day_name(),
        "is_weekend": dates.dayofweek >= 5,
    })


def build_dim_city(cfg: Config) -> pd.DataFrame:
    rows = []
    for i, (city, state, tier, region, w) in enumerate(CITY_DATA[: cfg.n_cities], start=1):
        rows.append({
            "city_key": i, "city": city, "state": state, "tier": tier,
            "region": region, "timezone": "Asia/Kolkata", "is_metro": tier == "Metro",
            "_weight": w,
        })
    return pd.DataFrame(rows)


def build_dim_delivery_partner(cfg: Config, faker: Faker, rng: np.random.Generator,
                               dim_city: pd.DataFrame) -> pd.DataFrame:
    n = cfg.n_delivery_partners
    city_w = dim_city["_weight"].to_numpy()
    city_pos = wchoice(rng, city_w, n)
    join_offset = rng.integers(0, (cfg.as_of_date - cfg.date_start).days, size=n)
    rows = []
    for i in range(n):
        rows.append({
            "delivery_partner_key": i + 1,
            "delivery_partner_id": business_id("DP", i + 1),
            "partner_name": faker.name(),
            "city_key": int(dim_city["city_key"].iloc[int(city_pos[i])]),
            "vehicle_type": VEHICLE_TYPES[int(wchoice(rng, VEHICLE_TYPE_WEIGHTS, 1)[0])],
            "joined_date": cfg.date_start + timedelta(days=int(join_offset[i])),
            "rating": round(float(np.clip(rng.normal(4.5, 0.35), 3.0, 5.0)), 2),
        })
    return pd.DataFrame(rows)


def build_dim_restaurant_and_menu(
    cfg: Config, faker: Faker, rng: np.random.Generator, dim_city: pd.DataFrame,
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Restaurant dimension (with latent popularity/quality) and its menu-item dimension."""
    n = cfg.n_restaurants
    city_w = dim_city["_weight"].to_numpy()
    city_pos = wchoice(rng, city_w, n)
    cuisine_idx = wchoice(rng, CUISINE_WEIGHTS, n)

    # Price tier depends on the restaurant's city tier: metros skew premium, tier-2 skews
    # budget. This is what makes metro AOV > tier-2 AOV emerge from real menu prices.
    base_tier_w = np.array([PRICE_TIERS[t]["w"] for t in TIER_NAMES])  # Budget, Mid, Premium
    CITY_TIER_FACTOR = {
        "Metro":  np.array([0.8, 1.0, 1.6]),
        "Tier 1": np.array([1.0, 1.0, 1.0]),
        "Tier 2": np.array([1.35, 1.0, 0.55]),
    }
    rest_city_tier = dim_city["tier"].to_numpy()[city_pos]
    tier_idx = np.empty(n, dtype=int)
    for i in range(n):
        w = base_tier_w * CITY_TIER_FACTOR[rest_city_tier[i]]
        tier_idx[i] = int(rng.choice(len(TIER_NAMES), p=w / w.sum()))

    # Latent quality -> rating; popularity ~ Zipf long tail (quality-influenced ranking).
    quality = np.clip(rng.beta(5, 3, size=n), 0.05, 0.99)
    rank_score = quality + rng.random(n) * 0.3
    order = np.argsort(-rank_score)
    zipf_w = 1.0 / np.arange(1, n + 1)
    popularity = np.empty(n)
    popularity[order] = zipf_w
    popularity /= popularity.sum()

    name_suffixes = ["Kitchen", "Restaurant", "Dhaba", "Cafe", "House", "Corner",
                     "Express", "Junction", "Foods", "Biryani House", "Point"]
    rest_rows: List[Dict[str, object]] = []
    menu_rows: List[Dict[str, object]] = []
    menu_key = 0
    for i in range(n):
        cuisine = CUISINES[int(cuisine_idx[i])]
        tier = TIER_NAMES[int(tier_idx[i])]
        band = PRICE_TIERS[tier]["band"]
        rating = float(np.clip(rng.normal(2.9 + 2.1 * quality[i], 0.3), 1.5, 5.0))
        city_key = int(dim_city["city_key"].iloc[int(city_pos[i])])
        rest_key = i + 1
        rest_rows.append({
            "restaurant_key": rest_key,
            "restaurant_id": business_id("RST", rest_key),
            "restaurant_name": f"{faker.last_name()} {cuisine.split()[0]} {rng.choice(name_suffixes)}",
            "cuisine": cuisine,
            "city_key": city_key,
            "price_tier": tier,
            "price_symbol": PRICE_TIERS[tier]["symbol"],
            "rating": round(rating, 2),
            "num_ratings": int(popularity[i] * cfg.n_customers * rng.uniform(0.8, 1.6)),
            "commission_rate": round(float(np.clip(rng.normal(0.21, 0.03), 0.15, 0.28)), 3),
            "avg_prep_time_mins": int(np.clip(rng.normal(18, 6), 6, 40)),
            "is_pure_veg": bool(rng.random() < 0.28),
            "_popularity": float(popularity[i]),
        })
        # Menu: sample dishes from the cuisine pool (+ a couple of beverages/desserts).
        n_items = int(rng.integers(6, 19))
        pool = list(CUISINE_DISHES[cuisine])
        pool += CUISINE_DISHES["Beverages"][:3] + CUISINE_DISHES["Desserts"][:2]
        chosen = rng.choice(len(pool), size=min(n_items, len(pool)), replace=False)
        for c in chosen:
            menu_key += 1
            price = round(float(rng.uniform(*band)) / 5) * 5  # round to nearest 5
            menu_rows.append({
                "menu_item_key": menu_key,
                "restaurant_key": rest_key,
                "item_name": pool[int(c)],
                "category": "Beverage" if pool[int(c)] in CUISINE_DISHES["Beverages"]
                            else ("Dessert" if pool[int(c)] in CUISINE_DISHES["Desserts"] else "Main"),
                "price": price,
                "is_veg": bool(rng.random() < 0.6),
            })
    return pd.DataFrame(rest_rows), pd.DataFrame(menu_rows)


def _signup_weights(cfg: Config) -> Tuple[np.ndarray, np.ndarray]:
    """Daily signup weights: growth trend + festive/seasonal bumps."""
    days = pd.date_range(cfg.date_start, cfg.as_of_date, freq="D")
    n = len(days)
    t = np.arange(n) / n
    trend = 0.5 + 1.6 * t
    month = days.month.to_numpy()
    seasonal = np.ones(n)
    seasonal[np.isin(month, [10, 11])] += 0.4   # festive season
    seasonal[np.isin(month, [1])] += 0.2        # new-year
    seasonal[np.isin(month, [4, 5])] -= 0.15    # summer dip
    w = trend * seasonal
    return days.to_numpy(), w / w.sum()


def build_dim_customer(
    cfg: Config, faker: Faker, rng: np.random.Generator, dim_city: pd.DataFrame,
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Customer dimension + parallel latent frame driving the order simulation."""
    n = cfg.n_customers
    pnames = list(PERSONAS.keys())
    pw = np.array([PERSONAS[p]["weight"] for p in pnames])
    persona = np.array(pnames)[wchoice(rng, pw, n)]

    sdays, sw = _signup_weights(cfg)
    signup_dt = pd.to_datetime(sdays[rng.choice(len(sdays), size=n, p=sw)])

    city_w = dim_city["_weight"].to_numpy()
    city_pos = wchoice(rng, city_w, n)
    city_key = dim_city["city_key"].to_numpy()[city_pos]
    city_name = dim_city["city"].to_numpy()[city_pos]
    city_tier = dim_city["tier"].to_numpy()[city_pos]

    gold_prob = np.array([PERSONAS[p]["gold_prob"] for p in persona])
    is_gold = rng.random(n) < gold_prob

    # Frequency weight -> multinomial share of total orders.
    freq_mult = np.array([PERSONAS[p]["freq_mult"] for p in persona])
    act = rng.random(n)
    activity_mult = np.where(act < 0.12, 0.06, np.where(act < 0.72, 0.6, 1.7))
    noise = rng.lognormal(0.0, 0.6, size=n)

    churn_prob = np.array([PERSONAS[p]["churn_prob"] for p in persona])
    churned = rng.random(n) < churn_prob
    max_days = np.maximum([(cfg.as_of_date - d.date()).days for d in signup_dt], 1)
    life = rng.exponential(150.0, size=n).astype(int) + 7
    active_days = np.where(churned, np.minimum(life, max_days), max_days)
    tenure_factor = np.sqrt(active_days / 30.0)

    freq_weight = np.maximum(freq_mult * activity_mult * noise * tenure_factor, 1e-6)

    decay_mean = np.array([PERSONAS[p]["decay_mean"] for p in persona])
    decay_half_life = np.maximum(rng.normal(decay_mean, decay_mean * 0.3), 20.0)

    keys = np.arange(1, n + 1)
    public = pd.DataFrame({
        "customer_key": keys,
        "customer_id": [business_id("CUST", int(k)) for k in keys],
        "signup_date": [d.date() for d in signup_dt],
        "gender": np.array(GENDERS)[wchoice(rng, GENDER_WEIGHTS, n)],
        "age_group": np.array(AGE_GROUPS)[wchoice(rng, AGE_GROUP_WEIGHTS, n)],
        "city_key": city_key,
        "city": city_name,
        "persona": persona,
        "is_gold_member": is_gold,
        "device_preference": np.array(DEVICE_PREFS)[wchoice(rng, DEVICE_PREF_WEIGHTS, n)],
        "marketing_channel": np.array(MARKETING_CHANNELS)[wchoice(rng, MARKETING_CHANNEL_WEIGHTS, n)],
    })
    latent = pd.DataFrame({
        "customer_key": keys, "persona": persona, "signup_dt": signup_dt,
        "city_key": city_key, "city_tier": city_tier, "is_gold": is_gold,
        "freq_weight": freq_weight, "active_days": active_days,
        "decay_half_life": decay_half_life,
    })
    return public, latent


# ======================================================================================
# PER-CUSTOMER SIMULATION
# ======================================================================================


class KeyCounter:
    def __init__(self) -> None:
        self.order = 0
        self.item = 0
        self.session = 0
        self.event = 0

    def next_order(self) -> int:
        self.order += 1
        return self.order

    def next_item(self) -> int:
        self.item += 1
        return self.item

    def next_session(self) -> int:
        self.session += 1
        return self.session

    def next_event(self) -> int:
        self.event += 1
        return self.event


def _order_timestamps(cfg: Config, rng: np.random.Generator, signup_dt: datetime,
                      active_days: int, decay_half_life: float, daypart_w: np.ndarray,
                      n_orders: int) -> List[datetime]:
    """Sample order timestamps in the active window with decay + daypart/DOW seasonality."""
    if n_orders <= 0:
        return []
    end = min(signup_dt + timedelta(days=int(active_days)),
              datetime.combine(cfg.as_of_date, dtime(23, 59, 59)))
    total_days = max((end - signup_dt).days, 1)
    idx = np.arange(total_days)
    day_dates = [signup_dt + timedelta(days=int(d)) for d in idx]
    dow = np.array([d.weekday() for d in day_dates])
    decay = np.exp(-np.log(2) * idx / max(decay_half_life, 1.0))
    day_w = DOW_WEIGHTS[dow] * decay
    day_w /= day_w.sum()
    chosen = rng.choice(total_days, size=n_orders, p=day_w)

    dp = daypart_w / daypart_w.sum()
    out: List[datetime] = []
    for c in chosen:
        base = signup_dt + timedelta(days=int(c))
        di = int(rng.choice(len(DAYPARTS), p=dp))
        _, h0, h1 = DAYPARTS[di]
        hour = int(rng.integers(h0, h1)) % 24
        ts = base.replace(hour=hour, minute=int(rng.integers(0, 60)),
                          second=int(rng.integers(0, 60)), microsecond=0)
        ts = min(max(ts, signup_dt + timedelta(minutes=int(rng.integers(1, 90)))), end)
        out.append(ts)
    out.sort()
    return out


def _make_funnel_events(rng: np.random.Generator, keys: KeyCounter, cust_key: int,
                        city_key: int, session_key: int, start: datetime, as_of_ts: datetime,
                        reach_stage: int, restaurant_key: Optional[int],
                        buf_events: List[Dict[str, object]], emit: bool) -> Tuple[datetime, int, str]:
    """Compute funnel timing up to ``reach_stage``; emit granular event rows only if ``emit``.

    ``screens_viewed`` and ``session_end`` are computed regardless, so ``fact_sessions``
    stays complete even when this session's events are not sampled into ``fact_app_events``.
    """
    t = start
    n_ev = 0
    last = start
    for s in range(reach_stage + 1):
        if t > as_of_ts:
            break
        stage = FUNNEL_STAGES[s]
        rk = restaurant_key if stage in ("restaurant_view", "menu_view", "add_to_cart",
                                          "checkout_start", "order_placed") else None
        if emit:
            buf_events.append({
                "event_key": keys.next_event(),
                "session_key": session_key,
                "customer_key": cust_key,
                "city_key": city_key,
                "restaurant_key": rk,
                "date_key": to_date_key(t),
                "event_timestamp": t,
                "event_type": stage,
            })
        n_ev += 1
        last = t
        t = t + timedelta(seconds=int(rng.integers(5, 90)))
    reached = FUNNEL_STAGES[reach_stage]
    return last, n_ev, reached


def simulate_customer(cfg: Config, rng: np.random.Generator, keys: KeyCounter,
                      cust: pd.Series, n_orders: int,
                      rest_commission: np.ndarray, rest_prep: np.ndarray, rest_rating: np.ndarray,
                      rest_tier_rank: np.ndarray,
                      city_to_rest: Dict[int, np.ndarray], rest_pop_by_city: Dict[int, np.ndarray],
                      menu_by_rest: Dict[int, Dict[str, np.ndarray]], city_partners: Dict[int, np.ndarray],
                      buffers: Dict[str, List[Dict[str, object]]]) -> None:
    """Simulate one customer's order history + the sessions/events funnel around it."""
    cust_key = int(cust["customer_key"])
    signup_dt: datetime = cust["signup_dt"].to_pydatetime() if hasattr(cust["signup_dt"], "to_pydatetime") else cust["signup_dt"]
    home_city = int(cust["city_key"])
    tier = str(cust["city_tier"])
    is_gold = bool(cust["is_gold"])
    persona = str(cust["persona"])
    pmeta = PERSONAS[persona]
    as_of_ts = datetime.combine(cfg.as_of_date, dtime(23, 59, 59))

    daypart_w = np.array(pmeta["daypart_w"])
    order_ts = _order_timestamps(cfg, rng, signup_dt, int(cust["active_days"]),
                                 float(cust["decay_half_life"]), daypart_w, n_orders)

    # Restaurant selection weight: popularity x persona's price-tier preference.
    # This makes AOV emerge by persona (premium_foodie -> pricier restaurants) while
    # keeping every order's food_subtotal consistent with real menu prices.
    home_rests = city_to_rest.get(home_city, np.array([], dtype=int))
    home_pop = rest_pop_by_city.get(home_city)
    tier_pref = np.array(pmeta["tier_pref"])
    favourites: List[int] = []
    sel_p = None
    if len(home_rests) > 0:
        sel_w = home_pop * tier_pref[rest_tier_rank[home_rests - 1]]
        sel_p = sel_w / sel_w.sum()
        k = min(len(home_rests), int(rng.integers(2, 6)))
        favourites = list(rng.choice(home_rests, size=k, replace=False, p=sel_p))

    disc_sens = float(pmeta["disc_sens"])
    partners = city_partners.get(home_city, np.array([], dtype=int))

    for o_i, ots in enumerate(order_ts):
        # Restaurant: usually a favourite (reorder), else discover a new one (tier-weighted).
        if favourites and rng.random() < 0.68:
            rest_key = int(rng.choice(favourites))
        elif len(home_rests) > 0:
            rest_key = int(rng.choice(home_rests, p=sel_p))
        else:
            rest_key = 1

        menu = menu_by_rest.get(rest_key)
        if menu is None or len(menu["price"]) == 0:
            continue

        # Items: choose 1..5 items; index numpy arrays (fast).
        m_n = len(menu["price"])
        n_items = int(np.clip(rng.poisson(cfg.mean_items_per_order - 1) + 1, 1, 6))
        pick = rng.choice(m_n, size=min(n_items, m_n), replace=False)
        food_subtotal = 0.0
        order_key = keys.next_order()
        order_id = business_id("ORD", order_key)
        for pidx in pick:
            pidx = int(pidx)
            qty = int(np.clip(rng.poisson(0.2) + 1, 1, 4))
            unit_price = float(menu["price"][pidx])
            line = unit_price * qty
            food_subtotal += line
            buffers["order_items"].append({
                "order_item_key": keys.next_item(),
                "order_key": order_key,
                "order_id": order_id,
                "menu_item_key": int(menu["key"][pidx]),
                "restaurant_key": rest_key,
                "item_name": menu["name"][pidx],
                "category": menu["cat"][pidx],
                "quantity": qty,
                "unit_price": unit_price,
                "line_amount": round(line, 2),
            })
        food_subtotal = round(food_subtotal, 2)

        # Fees. Gold -> free delivery. Platform fee small and grows slightly over time.
        distance_km = round(float(np.clip(rng.lognormal(0.9, 0.5), 0.4, 12.0)), 2)
        if is_gold or rng.random() < 0.15:
            delivery_fee = 0.0
        else:
            delivery_fee = float(round(20 + distance_km * rng.uniform(3, 7)))
        platform_fee = 6.0 if ots.year <= 2024 else (8.0 if ots.year == 2025 else 10.0)

        gov = round(food_subtotal + delivery_fee + platform_fee, 2)

        # Discounts: restaurant-funded + platform-funded (acquisition/promo, first orders heavier).
        first_order_boost = 0.5 if o_i == 0 else 0.0
        promo_prob = np.clip(0.25 + 0.5 * disc_sens + first_order_boost, 0, 0.95)
        platform_disc = 0.0
        rest_disc = 0.0
        if rng.random() < promo_prob:
            rate = rng.choice([0.10, 0.15, 0.20, 0.30, 0.40], p=[0.30, 0.28, 0.22, 0.14, 0.06])
            platform_disc = round(min(food_subtotal * rate * (0.6 + 0.8 * disc_sens),
                                      food_subtotal * 0.5), 2)
        if rng.random() < 0.35:
            rest_disc = round(food_subtotal * rng.choice([0.05, 0.10, 0.15]), 2)
        total_disc = round(min(platform_disc + rest_disc, food_subtotal * 0.6), 2)
        nov = round(gov - total_disc, 2)

        commission_rate = float(rest_commission[rest_key - 1])
        commission_income = round(commission_rate * food_subtotal, 2)

        # Delivery time: prep + distance + city congestion; drives on-time + rating.
        prep = int(rest_prep[rest_key - 1])
        speed = TIER_PARTNER_SPEED.get(tier, 1.0)
        delivery_time = int(np.clip(rng.normal(prep + distance_km * 3.2 / speed + 8, 6), 12, 80))
        promised = int(delivery_time * rng.uniform(0.85, 1.05)) + 3
        on_time = delivery_time <= promised

        status = str(rng.choice(ORDER_STATUSES, p=ORDER_STATUS_WEIGHTS))
        cancelled = status != "Delivered"

        # Rating: only some delivered orders; higher for good restaurants + on-time.
        rating = None
        if not cancelled and rng.random() < float(pmeta["rating_prob"]):
            base_r = float(rest_rating[rest_key - 1])
            r = base_r + (0.3 if on_time else -0.6) + rng.normal(0, 0.4)
            rating = round(float(np.clip(round(r * 2) / 2, 1.0, 5.0)), 1)

        partner_key = int(rng.choice(partners)) if len(partners) > 0 else None

        # Per-order contribution margin (revenue - variable costs). Often thin/negative.
        last_mile_cost = round(35 + distance_km * rng.uniform(5, 9), 2)
        pg_charge = round(nov * 0.015, 2)
        support_cost = round(rng.uniform(0, 6), 2)
        revenue = commission_income + delivery_fee + platform_fee
        contribution_margin = round(revenue - last_mile_cost - platform_disc - pg_charge - support_cost, 2)

        if cancelled:
            nov = 0.0
            delivery_time = None
            rating = None
            contribution_margin = round(-(platform_disc + pg_charge * 0), 2)

        buffers["orders"].append({
            "order_key": order_key,
            "order_id": order_id,
            "customer_key": cust_key,
            "restaurant_key": rest_key,
            "delivery_partner_key": partner_key,
            "city_key": home_city,
            "date_key": to_date_key(ots),
            "order_timestamp": ots,
            "daypart": str(DAYPART_BY_HOUR[ots.hour]),
            "item_count": len(pick),
            "food_subtotal": food_subtotal,
            "delivery_fee": delivery_fee,
            "platform_fee": platform_fee,
            "gov": gov,
            "restaurant_funded_discount": rest_disc,
            "platform_funded_discount": platform_disc,
            "total_discount": total_disc,
            "nov": nov,
            "commission_rate": commission_rate,
            "commission_income": commission_income,
            "contribution_margin": contribution_margin,
            "distance_km": distance_km,
            "delivery_time_mins": delivery_time,
            "promised_time_mins": promised,
            "on_time": (None if cancelled else on_time),
            "order_status": status,
            "is_gold_order": is_gold,
            "payment_method": ("Cash on Delivery"
                               if (not is_gold and rng.random() < 0.13)
                               else str(rng.choice(PAYMENT_METHODS, p=PAYMENT_METHOD_WEIGHTS))),
            "rating": rating,
        })

        # Converting session + funnel events leading to this order.
        s_key = keys.next_session()
        s_id = business_id("SESS", s_key)
        sess_start = ots - timedelta(seconds=int(rng.integers(120, 900)))
        if sess_start < signup_dt:
            sess_start = signup_dt
        emit = rng.random() < cfg.event_sample_rate
        last_ts, n_ev, _ = _make_funnel_events(rng, keys, cust_key, home_city, s_key,
                                               sess_start, as_of_ts, len(FUNNEL_STAGES) - 1,
                                               rest_key, buffers["events"], emit)
        buffers["sessions"].append({
            "session_key": s_key, "session_id": s_id, "customer_key": cust_key,
            "city_key": home_city, "date_key": to_date_key(sess_start),
            "session_start": sess_start, "session_end": max(last_ts, ots),
            "duration_seconds": int((max(last_ts, ots) - sess_start).total_seconds()),
            "screens_viewed": n_ev, "reached_stage": "order_placed",
            "converted": True, "order_id": order_id,
            "device": str(cust.get("device_preference", "Android")),
        })

    # Non-converting browse sessions so the funnel has real drop-off.
    if n_orders > 0 and cfg.session_conversion < 1.0:
        n_browse = int(rng.poisson(n_orders * (1.0 / cfg.session_conversion - 1.0)))
        browse_ts = _order_timestamps(cfg, rng, signup_dt, int(cust["active_days"]),
                                      float(cust["decay_half_life"]), daypart_w, n_browse)
        for bts in browse_ts:
            s_key = keys.next_session()
            s_id = business_id("SESS", s_key)
            reach = int(wchoice(rng, ABANDON_STAGE_W, 1)[0])  # 0..5 (never order_placed)
            rk = None
            if reach >= 2 and len(home_rests) > 0:
                rk = int(rng.choice(home_rests, p=sel_p))
            emit = rng.random() < cfg.event_sample_rate
            last_ts, n_ev, reached = _make_funnel_events(rng, keys, cust_key, home_city, s_key,
                                                         bts, as_of_ts, reach, rk, buffers["events"], emit)
            buffers["sessions"].append({
                "session_key": s_key, "session_id": s_id, "customer_key": cust_key,
                "city_key": home_city, "date_key": to_date_key(bts),
                "session_start": bts, "session_end": last_ts,
                "duration_seconds": int((last_ts - bts).total_seconds()),
                "screens_viewed": n_ev, "reached_stage": reached,
                "converted": False, "order_id": None,
                "device": str(cust.get("device_preference", "Android")),
            })


# ======================================================================================
# ORCHESTRATION
# ======================================================================================


def generate_facts(cfg: Config, rng: np.random.Generator, cust_latent: pd.DataFrame,
                   cust_public: pd.DataFrame, dim_restaurant: pd.DataFrame,
                   dim_menu: pd.DataFrame, dim_partner: pd.DataFrame,
                   dim_city: pd.DataFrame) -> Dict[str, pd.DataFrame]:
    # Allocate exact target_orders across customers by frequency weight.
    w = cust_latent["freq_weight"].to_numpy()
    order_counts = rng.multinomial(cfg.target_orders, w / w.sum())

    # Pre-index restaurants / partners / menus for fast (numpy) lookup in the hot loop.
    rest_commission = dim_restaurant["commission_rate"].to_numpy()
    rest_prep = dim_restaurant["avg_prep_time_mins"].to_numpy()
    rest_rating = dim_restaurant["rating"].to_numpy()
    _tier_rank_map = {t: i for i, t in enumerate(TIER_NAMES)}  # Budget=0, Mid=1, Premium=2
    rest_tier_rank = dim_restaurant["price_tier"].map(_tier_rank_map).to_numpy()
    city_to_rest: Dict[int, np.ndarray] = {}
    rest_pop_by_city: Dict[int, np.ndarray] = {}
    for ck, grp in dim_restaurant.groupby("city_key"):
        city_to_rest[int(ck)] = grp["restaurant_key"].to_numpy()
        rest_pop_by_city[int(ck)] = grp["_popularity"].to_numpy()
    menu_by_rest: Dict[int, Dict[str, np.ndarray]] = {}
    for rk, gdf in dim_menu.groupby("restaurant_key"):
        menu_by_rest[int(rk)] = {
            "key": gdf["menu_item_key"].to_numpy(),
            "name": gdf["item_name"].to_numpy(),
            "cat": gdf["category"].to_numpy(),
            "price": gdf["price"].to_numpy(),
        }
    city_partners: Dict[int, np.ndarray] = {
        int(ck): g["delivery_partner_key"].to_numpy() for ck, g in dim_partner.groupby("city_key")
    }

    buffers: Dict[str, List[Dict[str, object]]] = {
        "orders": [], "order_items": [], "sessions": [], "events": [],
    }
    keys = KeyCounter()
    latent_records = cust_latent.to_dict("records")
    dev_by_key = dict(zip(cust_public["customer_key"], cust_public["device_preference"]))

    for i in tqdm(range(len(latent_records)), desc="Simulating customers", unit="cust"):
        n_orders = int(order_counts[i])
        if n_orders <= 0:
            continue
        rec = latent_records[i]
        rec["device_preference"] = dev_by_key.get(rec["customer_key"], "Android")
        simulate_customer(cfg, rng, keys, pd.Series(rec), n_orders,
                          rest_commission, rest_prep, rest_rating, rest_tier_rank,
                          city_to_rest, rest_pop_by_city, menu_by_rest, city_partners, buffers)

    fact_orders = pd.DataFrame(buffers["orders"])[[
        "order_key", "order_id", "customer_key", "restaurant_key", "delivery_partner_key",
        "city_key", "date_key", "order_timestamp", "daypart", "item_count",
        "food_subtotal", "delivery_fee", "platform_fee", "gov",
        "restaurant_funded_discount", "platform_funded_discount", "total_discount", "nov",
        "commission_rate", "commission_income", "contribution_margin",
        "distance_km", "delivery_time_mins", "promised_time_mins", "on_time",
        "order_status", "is_gold_order", "payment_method", "rating",
    ]]
    fact_order_items = pd.DataFrame(buffers["order_items"])[[
        "order_item_key", "order_key", "order_id", "menu_item_key", "restaurant_key",
        "item_name", "category", "quantity", "unit_price", "line_amount",
    ]]
    fact_sessions = pd.DataFrame(buffers["sessions"])[[
        "session_key", "session_id", "customer_key", "city_key", "date_key",
        "session_start", "session_end", "duration_seconds", "screens_viewed",
        "reached_stage", "converted", "order_id", "device",
    ]]
    fact_app_events = pd.DataFrame(buffers["events"])[[
        "event_key", "session_key", "customer_key", "city_key", "restaurant_key",
        "date_key", "event_timestamp", "event_type",
    ]]
    return {
        "fact_orders": fact_orders,
        "fact_order_items": fact_order_items,
        "fact_sessions": fact_sessions,
        "fact_app_events": fact_app_events,
    }


def save_tables(tables: Dict[str, pd.DataFrame], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        df.to_csv(out_dir / f"{name}.csv", index=False)


def main(cfg: Optional[Config] = None) -> None:
    """Generate the food-delivery warehouse and write all CSV files."""
    cfg = cfg or (FULL_SCALE_CONFIG if FULL_SCALE else DEFAULT_CONFIG)
    rng = make_rng(cfg.seed)
    faker = Faker("en_IN")
    Faker.seed(cfg.seed)

    print(f"Generating Zomato-style warehouse "
          f"(customers={cfg.n_customers:,}, restaurants={cfg.n_restaurants:,}, "
          f"target_orders={cfg.target_orders:,})")

    dim_date = build_dim_date(cfg)
    dim_city = build_dim_city(cfg)
    dim_partner = build_dim_delivery_partner(cfg, faker, rng, dim_city)
    dim_restaurant, dim_menu = build_dim_restaurant_and_menu(cfg, faker, rng, dim_city)
    dim_customer_public, dim_customer_latent = build_dim_customer(cfg, faker, rng, dim_city)

    facts = generate_facts(cfg, rng, dim_customer_latent, dim_customer_public,
                           dim_restaurant, dim_menu, dim_partner, dim_city)

    tables: Dict[str, pd.DataFrame] = {
        "dim_customer": dim_customer_public,
        "dim_restaurant": dim_restaurant.drop(columns=["_popularity"]),
        "dim_menu_item": dim_menu,
        "dim_delivery_partner": dim_partner,
        "dim_city": dim_city.drop(columns=["_weight"]),
        "dim_date": dim_date,
        **facts,
    }
    save_tables(tables, cfg.output_dir)

    print("\nDone. Row counts:")
    for name, df in tables.items():
        print(f"  {name:<22} {len(df):>10,} rows")


if __name__ == "__main__":
    main()
