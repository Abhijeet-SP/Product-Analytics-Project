import logging
import time
import psycopg2
from etl.config import DATABASE_URL, SQL_DIR, SQL_FILES, LOAD_ORDER

log = logging.getLogger("etl.load")


def get_conn():
    return psycopg2.connect(DATABASE_URL)


def run_sql_files(conn) -> None:
    with conn.cursor() as cur:
        for rel in SQL_FILES:
            sql = (SQL_DIR / rel).read_text()
            t0 = time.perf_counter()
            cur.execute(sql)
            log.info("executed %s (%.1fs)", rel, time.perf_counter() - t0)
    conn.commit()


def copy_table(conn, table: str, path) -> int:
    with conn.cursor() as cur, open(path) as f:
        cur.copy_expert(
            f"COPY analytics.{table} FROM STDIN WITH (FORMAT csv, HEADER true)",
            f,
        )
        cur.execute(f"SELECT COUNT(*) FROM analytics.{table}")
        return cur.fetchone()[0]


def run(sources) -> None:
    conn = get_conn()

    try:
        run_sql_files(conn)

        with conn.cursor() as cur:
            cur.execute(
                "TRUNCATE "
                + ", ".join(f"analytics.{t}" for t in reversed(LOAD_ORDER))
            )

        for table in LOAD_ORDER:
            t0 = time.perf_counter()
            n = copy_table(conn, table, sources[table])
            log.info(
                "loaded %s: %s rows (%.1fs)",
                table,
                f"{n:,}",
                time.perf_counter() - t0,
            )

        with conn.cursor() as cur:
            cur.execute("ANALYZE")

        conn.commit()
        log.info("load committed")

    except Exception:
        conn.rollback()
        log.exception("load failed - rolled back, warehouse unchanged")
        raise

    finally:
        conn.close()