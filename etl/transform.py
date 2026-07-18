import logging
from pathlib import Path
import pandas as pd
from etl.config import DATA_DIR

log = logging.getLogger("etl.transform")
PROCESSED_DIR = DATA_DIR / "processed"

def transform_app_events(src: Path) -> Path:
    out = PROCESSED_DIR / src.name
    PROCESSED_DIR.mkdir(exist_ok=True)
    df = pd.read_csv(src, dtype={"restaurant_key": "Int64"})
    df.to_csv(out, index=False)
    log.info("fact_app_events: restaurant_key cast to nullable Int64 "
        "(%s nulls preserved)", f"{df['restaurant_key'].isna().sum():,}")
    return out

def run(sources: dict[str, Path]) -> dict[str, Path]:
    cleaned = dict(sources)
    cleaned["fact_app_events"] = transform_app_events(sources["fact_app_events"])
    return cleaned