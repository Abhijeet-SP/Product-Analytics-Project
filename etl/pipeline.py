import logging
import sys
import time
import psycopg2
from etl import extract, transform, load
from etl.config import DATABASE_URL, EXPECTED_ROWS

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)

log = logging.getLogger("etl.pipeline")


VALIDATIONS = {
    "row_counts": """
        SELECT COUNT(*) FROM (
            SELECT 'fact_orders' t, COUNT(*) n FROM analytics.fact_orders
            UNION ALL
            SELECT 'fact_order_items', COUNT(*) FROM analytics.fact_order_items
            UNION ALL
            SELECT 'fact_sessions', COUNT(*) FROM analytics.fact_sessions
            UNION ALL
            SELECT 'fact_app_events', COUNT(*) FROM analytics.fact_app_events
        ) x
        WHERE n = 0
    """,

    "gov_identity": """
        SELECT COUNT(*) FROM analytics.fact_orders
        WHERE ABS(gov - (food_subtotal + delivery_fee + platform_fee)) > 0.01
    """,

    "nov_identity": """
        SELECT COUNT(*) FROM analytics.fact_orders
        WHERE ABS(nov - (gov - total_discount)) > 0.01
    """,

    "orphan_session_orders": """
        SELECT COUNT(*)
        FROM analytics.fact_sessions s
        LEFT JOIN analytics.fact_orders o
            ON o.order_id = s.order_id
        WHERE s.order_id IS NOT NULL
          AND o.order_id IS NULL
    """,

    "conversion_consistency": """
        SELECT COUNT(*)
        FROM analytics.fact_sessions
        WHERE converted <> (order_id IS NOT NULL)
    """,
}


def validate() -> list[str]:
    failures = []

    with psycopg2.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for name, sql in VALIDATIONS.items():
            cur.execute(sql)
            bad = cur.fetchone()[0]

            if bad:
                failures.append(f"{name}: {bad:,} offending rows")
                log.error(
                    "VALIDATION FAILED %s (%s rows)",
                    name,
                    f"{bad:,}",
                )
            else:
                log.info("validation passed: %s", name)

    return failures


def main() -> int:
    t0 = time.perf_counter()

    try:
        sources = extract.verify_sources()
        sources = transform.run(sources)
        load.run(sources)
        failures = validate()

    except Exception as e:
        log.error("pipeline aborted: %s", e)
        return 1

    if failures:
        log.error(
            "pipeline completed load but FAILED validation: %s",
            failures,
        )
        return 1

    log.info(
        "pipeline succeeded in %.1fs",
        time.perf_counter() - t0,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())