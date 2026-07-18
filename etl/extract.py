import csv
import logging 
from pathlib import Path
from etl.config import DATA_DIR, EXPECTED_ROWS

log = logging.getLogger("etl.extract")

class ExtractorError(Exception):
    pass

def count_rows(path: Path) -> int:
    with open(path, newline="") as f:
        return sum(1 for _ in csv.reader(f)) - 1
    
def verify_sources() -> dict[str, Path]:
    sources = {}
    for table, expected in EXPECTED_ROWS.items():
        path = DATA_DIR / f"{table}.csv"
        if not path.exists():
            raise ExtractorError(f"missing source file: {path}")
        actual = count_rows(path)
        if actual != expected:
            raise ExtractorError(
                "f{table}: expected {expected:, } rows, found {actual:,}")
        
        sources[table] = path
        log.info("verified %s (%s rows)", path.name, f"{actual:,}")
    return sources
            
        