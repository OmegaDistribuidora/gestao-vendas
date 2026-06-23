from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import unicodedata
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal, InvalidOperation
from typing import Iterable

import oracledb
import psycopg
from psycopg.types.json import Jsonb

from oracle_financial_sync_common import init_oracle_client_if_available, require_env
from supabase_sync_common import (
    SupabaseSession,
    authenticate_supabase,
    begin_sync_run,
    insert_rows,
    invoke_rpc,
    mark_sync_run_failed,
    set_sync_run_rows_staged,
)


ORACLE_REGISTERED_TAX_IDS_QUERY = """
SELECT DISTINCT
    REGEXP_REPLACE(pc.cgcent, '[^0-9]') AS tax_id
FROM pcclient pc
WHERE LENGTH(REGEXP_REPLACE(pc.cgcent, '[^0-9]')) IN (11, 14)
"""

HENRIQUE_OPPORTUNITIES_QUERY = """
WITH sales_rows AS (
    SELECT
        REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', '', 'g') AS tax_id,
        NULLIF(TRIM(codativ), '') AS activity_code,
        NULLIF(TRIM(atividade), '') AS activity_name,
        NULLIF(TRIM(endereco), '') AS street,
        NULLIF(TRIM(numero), '') AS address_number,
        NULLIF(TRIM(codfornec), '') AS supplier_code,
        COALESCE(
            NULLIF(TRIM(fornecedor_fantasia), ''),
            NULLIF(TRIM(fornecedor), ''),
            NULLIF(TRIM(codfornec), '')
        ) AS supplier_name
    FROM public.fvendas
    WHERE LENGTH(REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', '', 'g'))
          IN (11, 14)
),
sales_by_customer AS (
    SELECT
        tax_id,
        MODE() WITHIN GROUP (ORDER BY activity_code) AS activity_code,
        MODE() WITHIN GROUP (ORDER BY activity_name) AS activity_name,
        MODE() WITHIN GROUP (ORDER BY street) AS sales_street,
        MODE() WITHIN GROUP (ORDER BY address_number) AS address_number,
        COALESCE(
            JSONB_AGG(DISTINCT JSONB_BUILD_OBJECT(
                'code', supplier_code,
                'name', supplier_name
            )) FILTER (WHERE supplier_code IS NOT NULL),
            '[]'::jsonb
        ) AS suppliers
    FROM sales_rows
    GROUP BY tax_id
),
order_line_rows AS (
    SELECT
        REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', '', 'g') AS tax_id,
        NULLIF(TRIM(numped), '') AS order_id,
        data AS order_date,
        CASE
            WHEN CASE
                WHEN TRIM(COALESCE(total_venda, '')) LIKE '%,%'
                    THEN REPLACE(
                        REPLACE(TRIM(total_venda), '.', ''),
                        ',',
                        '.'
                    )
                ELSE TRIM(COALESCE(total_venda, ''))
            END ~ '^-?[0-9]+([.][0-9]+)?$'
            THEN (
                CASE
                    WHEN TRIM(COALESCE(total_venda, '')) LIKE '%,%'
                        THEN REPLACE(
                            REPLACE(TRIM(total_venda), '.', ''),
                            ',',
                            '.'
                        )
                    ELSE TRIM(COALESCE(total_venda, ''))
                END
            )::numeric
            ELSE 0::numeric
        END AS line_total
    FROM public.fvendas
    WHERE LENGTH(REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', '', 'g'))
          IN (11, 14)
      AND NULLIF(TRIM(numped), '') IS NOT NULL
),
order_totals AS (
    SELECT
        tax_id,
        order_id,
        MAX(order_date) AS order_date,
        SUM(line_total) AS order_total
    FROM order_line_rows
    GROUP BY tax_id, order_id
),
ranked_orders AS (
    SELECT
        tax_id,
        order_total,
        ROW_NUMBER() OVER (
            PARTITION BY tax_id
            ORDER BY order_date DESC NULLS LAST, order_id DESC
        ) AS order_rank
    FROM order_totals
),
market_potential_by_customer AS (
    SELECT
        tax_id,
        ROUND(AVG(order_total), 2) AS market_potential,
        COUNT(*)::integer AS market_potential_order_count
    FROM ranked_orders
    WHERE order_rank <= 3
    GROUP BY tax_id
),
customer_rows AS (
    SELECT DISTINCT ON (tax_id)
        tax_id,
        COALESCE(NULLIF(TRIM(codcli), ''), '') AS source_customer_code,
        COALESCE(NULLIF(TRIM(cliente), ''), '') AS client_name,
        COALESCE(NULLIF(TRIM(fantasia), ''), '') AS fantasy_name,
        COALESCE(NULLIF(TRIM(codramo), ''), '') AS fallback_activity_code,
        COALESCE(NULLIF(TRIM(cidade), ''), '') AS city,
        COALESCE(NULLIF(TRIM(estado), ''), '') AS uf,
        COALESCE(NULLIF(TRIM(bairro), ''), '') AS district,
        COALESCE(NULLIF(TRIM(endereco), ''), '') AS street,
        COALESCE(NULLIF(TRIM(cepcob), ''), '') AS postal_code,
        COALESCE(NULLIF(TRIM(limcred), ''), NULLIF(TRIM(limcred2), ''), '0')
            AS credit_limit,
        TRIM(latitude) AS latitude,
        TRIM(longitude) AS longitude
    FROM (
        SELECT
            REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', '', 'g') AS tax_id,
            d.*
        FROM public.dclientes d
    ) source
    WHERE LENGTH(tax_id) IN (11, 14)
    ORDER BY tax_id, source_customer_code
)
SELECT
    c.tax_id,
    c.source_customer_code,
    c.client_name,
    c.fantasy_name,
    COALESCE(s.activity_code, c.fallback_activity_code, '') AS activity_code,
    COALESCE(s.activity_name, '') AS activity_name,
    c.city,
    c.uf,
    c.district,
    COALESCE(NULLIF(c.street, ''), s.sales_street, '') AS street,
    COALESCE(s.address_number, '') AS address_number,
    c.postal_code,
    c.credit_limit,
    p.market_potential,
    COALESCE(p.market_potential_order_count, 0) AS market_potential_order_count,
    c.latitude,
    c.longitude,
    COALESCE(s.suppliers, '[]'::jsonb)::text AS suppliers
FROM customer_rows c
LEFT JOIN sales_by_customer s ON s.tax_id = c.tax_id
LEFT JOIN market_potential_by_customer p ON p.tax_id = c.tax_id
ORDER BY c.tax_id
"""


@dataclass(frozen=True)
class CustomerOpportunityRow:
    tax_id: str
    source_customer_code: str
    client_name: str
    fantasy_name: str
    activity_code: str
    activity_name: str
    city: str
    city_key: str
    uf: str
    district: str
    street: str
    address_number: str
    full_address: str
    postal_code: str
    credit_limit: float
    market_potential: float | None
    market_potential_order_count: int
    latitude: float
    longitude: float
    suppliers: list[dict[str, str]]
    imported_at: str


def _normalize_text(value: object | None) -> str:
    return str(value or "").replace("\x00", "").strip()


def _normalize_tax_id(value: object | None) -> str:
    return re.sub(r"[^0-9]", "", _normalize_text(value))


def _normalize_city_key(value: object | None) -> str:
    normalized = unicodedata.normalize("NFKD", _normalize_text(value))
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]", "", ascii_value.lower())


def _parse_decimal(value: object | None) -> float:
    text = _normalize_text(value)
    if not text:
        return 0.0

    if "," in text:
        text = text.replace(".", "").replace(",", ".")

    try:
        return float(Decimal(text))
    except (InvalidOperation, ValueError):
        return 0.0


def _parse_coordinate(value: object | None) -> float | None:
    text = _normalize_text(value).replace(",", ".")
    try:
        return float(text)
    except ValueError:
        return None


def _normalize_suppliers(value: object | None) -> list[dict[str, str]]:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return []

    if not isinstance(value, list):
        return []

    deduped: dict[str, dict[str, str]] = {}
    for item in value:
        if not isinstance(item, dict):
            continue
        code = _normalize_text(item.get("code"))
        if not code:
            continue
        deduped[code] = {
            "code": code,
            "name": _normalize_text(item.get("name")) or code,
        }

    return sorted(deduped.values(), key=lambda item: (item["name"], item["code"]))


def _build_full_address(street: str, number: str) -> str:
    if street and number:
        return f"{street}, {number}"
    return street or number


def fetch_registered_oracle_tax_ids() -> set[str]:
    tax_ids_file = os.getenv("ORACLE_REGISTERED_TAX_IDS_FILE", "").strip()
    if tax_ids_file:
        with open(tax_ids_file, encoding="utf-8", errors="ignore") as source:
            content = source.read()
        return set(
            re.findall(r"(?m)^\s*(\d{11}|\d{14})\s*$", content)
        )

    sqlplus_path = os.getenv("ORACLE_SQLPLUS_PATH", "").strip()
    if sqlplus_path:
        return _fetch_registered_tax_ids_with_sqlplus(sqlplus_path)

    init_oracle_client_if_available()
    connection = oracledb.connect(
        user=require_env("ORACLE_USER"),
        password=require_env("ORACLE_PASSWORD"),
        dsn=require_env("ORACLE_DSN"),
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute(ORACLE_REGISTERED_TAX_IDS_QUERY)
            return {
                tax_id
                for (raw_tax_id,) in cursor
                if len(tax_id := _normalize_tax_id(raw_tax_id)) in (11, 14)
            }
    finally:
        connection.close()


def _fetch_registered_tax_ids_with_sqlplus(sqlplus_path: str) -> set[str]:
    oracle_user = require_env("ORACLE_USER")
    oracle_password = require_env("ORACLE_PASSWORD")
    oracle_dsn = require_env("ORACLE_DSN")
    if '"' in oracle_user or '"' in oracle_password:
        raise RuntimeError("Oracle credentials cannot contain double quotes.")

    tax_ids: set[str] = set()
    for prefix in "0123456789":
        sql = f"""
connect {oracle_user}/\"{oracle_password}\"@{oracle_dsn}
set heading off feedback off pagesize 0 verify off echo off trimspool on linesize 32767
{ORACLE_REGISTERED_TAX_IDS_QUERY.strip()}
  AND SUBSTR(REGEXP_REPLACE(pc.cgcent, '[^0-9]'), 1, 1) = '{prefix}';
exit
"""
        result = subprocess.run(
            [sqlplus_path, "-S", "/nolog"],
            input=sql,
            capture_output=True,
            text=True,
            check=False,
        )
        if (
            result.returncode != 0
            or "ORA-" in result.stdout
            or "ORA-" in result.stderr
        ):
            details = (result.stderr or result.stdout).strip()[:1000]
            raise RuntimeError(f"SQL*Plus Oracle query failed: {details}")

        tax_ids.update(
            re.findall(
                r"(?m)^\s*(\d{11}|\d{14})\s*$",
                result.stdout,
            )
        )

    return tax_ids


def iter_henrique_rows(
    registered_tax_ids: set[str],
    source_stats: dict[str, int],
) -> Iterable[CustomerOpportunityRow]:
    connection = psycopg.connect(
        host=os.getenv("HENRIQUE_PG_HOST", "localhost").strip() or "localhost",
        port=int(os.getenv("HENRIQUE_PG_PORT", "5432")),
        dbname=os.getenv("HENRIQUE_PG_DATABASE", "Bases Henrique").strip(),
        user=require_env("HENRIQUE_PG_USER"),
        password=require_env("HENRIQUE_PG_PASSWORD"),
    )

    imported_at = datetime.now(UTC).isoformat(timespec="seconds").replace(
        "+00:00",
        "Z",
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "CREATE TEMP TABLE tmp_customer_opportunities "
                "ON COMMIT DROP AS "
                + HENRIQUE_OPPORTUNITIES_QUERY
            )
            cursor.execute(
                "CREATE INDEX ON tmp_customer_opportunities (tax_id)"
            )

            last_tax_id = ""
            while True:
                cursor.execute(
                    """
                    SELECT *
                    FROM tmp_customer_opportunities
                    WHERE tax_id > %s
                    ORDER BY tax_id
                    LIMIT 5000
                    """,
                    (last_tax_id,),
                )
                source_rows = cursor.fetchall()
                if not source_rows:
                    break

                for source_row in source_rows:
                    (
                        raw_tax_id,
                        source_customer_code,
                        client_name,
                        fantasy_name,
                        activity_code,
                        activity_name,
                        city,
                        uf,
                        district,
                        street,
                        address_number,
                        postal_code,
                        credit_limit,
                        market_potential,
                        market_potential_order_count,
                        latitude,
                        longitude,
                        suppliers,
                    ) = source_row

                    tax_id = _normalize_tax_id(raw_tax_id)
                    if tax_id in registered_tax_ids:
                        source_stats["registered_customers"] += 1
                        continue

                    parsed_latitude = _parse_coordinate(latitude)
                    parsed_longitude = _parse_coordinate(longitude)
                    if (
                        parsed_latitude is None
                        or parsed_longitude is None
                        or not -90 <= parsed_latitude <= 90
                        or not -180 <= parsed_longitude <= 180
                    ):
                        source_stats["invalid_coordinates"] += 1
                        continue

                    normalized_street = _normalize_text(street)
                    normalized_number = _normalize_text(address_number)
                    normalized_city = _normalize_text(city)
                    city_key = _normalize_city_key(normalized_city)
                    if not city_key:
                        source_stats["missing_city"] += 1
                        continue

                    yield CustomerOpportunityRow(
                        tax_id=tax_id,
                        source_customer_code=_normalize_text(
                            source_customer_code
                        ),
                        client_name=_normalize_text(client_name),
                        fantasy_name=_normalize_text(fantasy_name),
                        activity_code=_normalize_text(activity_code),
                        activity_name=_normalize_text(activity_name),
                        city=normalized_city,
                        city_key=city_key,
                        uf=_normalize_text(uf),
                        district=_normalize_text(district),
                        street=normalized_street,
                        address_number=normalized_number,
                        full_address=_build_full_address(
                            normalized_street,
                            normalized_number,
                        ),
                        postal_code=_normalize_text(postal_code),
                        credit_limit=_parse_decimal(credit_limit),
                        market_potential=(
                            _parse_decimal(market_potential)
                            if market_potential is not None
                            else None
                        ),
                        market_potential_order_count=int(
                            market_potential_order_count or 0
                        ),
                        latitude=parsed_latitude,
                        longitude=parsed_longitude,
                        suppliers=_normalize_suppliers(suppliers),
                        imported_at=imported_at,
                    )

                last_tax_id = _normalize_tax_id(source_rows[-1][0])
    finally:
        connection.close()


def stage_rows(
    session: SupabaseSession,
    run_id: str,
    rows: Iterable[CustomerOpportunityRow],
) -> int:
    staged_count = 0
    batch: list[dict[str, object]] = []
    for row in rows:
        batch.append(
            {
                "run_id": run_id,
                "tax_id": row.tax_id,
                "source_customer_code": row.source_customer_code,
                "client_name": row.client_name,
                "fantasy_name": row.fantasy_name,
                "activity_code": row.activity_code,
                "activity_name": row.activity_name,
                "city": row.city,
                "city_key": row.city_key,
                "uf": row.uf,
                "district": row.district,
                "street": row.street,
                "address_number": row.address_number,
                "full_address": row.full_address,
                "postal_code": row.postal_code,
                "credit_limit": row.credit_limit,
                "market_potential": row.market_potential,
                "market_potential_order_count": (
                    row.market_potential_order_count
                ),
                "latitude": row.latitude,
                "longitude": row.longitude,
                "suppliers": row.suppliers,
                "imported_at": row.imported_at,
            }
        )
        if len(batch) >= 500:
            staged_count += insert_rows(
                session,
                "etl_stg_customer_opportunities",
                batch,
            )
            batch = []
            if staged_count % 5000 == 0:
                print(
                    json.dumps({"rows_staged_progress": staged_count}),
                    flush=True,
                )

    if batch:
        staged_count += insert_rows(
            session,
            "etl_stg_customer_opportunities",
            batch,
        )
    return staged_count


def stage_rows_direct(
    connection: psycopg.Connection,
    run_id: str,
    rows: Iterable[CustomerOpportunityRow],
) -> int:
    staged_count = 0
    copy_sql = """
        COPY public.etl_stg_customer_opportunities (
            run_id,
            tax_id,
            source_customer_code,
            client_name,
            fantasy_name,
            activity_code,
            activity_name,
            city,
            city_key,
            uf,
            district,
            street,
            address_number,
            full_address,
            postal_code,
            credit_limit,
            market_potential,
            market_potential_order_count,
            latitude,
            longitude,
            suppliers,
            imported_at
        ) FROM STDIN
    """
    with connection.cursor() as cursor:
        with cursor.copy(copy_sql) as copy:
            for row in rows:
                copy.write_row(
                    (
                        run_id,
                        row.tax_id,
                        row.source_customer_code,
                        row.client_name,
                        row.fantasy_name,
                        row.activity_code,
                        row.activity_name,
                        row.city,
                        row.city_key,
                        row.uf,
                        row.district,
                        row.street,
                        row.address_number,
                        row.full_address,
                        row.postal_code,
                        row.credit_limit,
                        row.market_potential,
                        row.market_potential_order_count,
                        row.latitude,
                        row.longitude,
                        Jsonb(row.suppliers),
                        row.imported_at,
                    )
                )
                staged_count += 1
                if staged_count % 5000 == 0:
                    print(
                        json.dumps({"rows_staged_progress": staged_count}),
                        flush=True,
                    )
    return staged_count


def run_direct_sync(
    registered_tax_ids: set[str],
    source_stats: dict[str, int],
) -> tuple[int, dict[str, object]]:
    connection = psycopg.connect(
        require_env("SUPABASE_DB_DSN"),
        password=require_env("SUPABASE_DB_PASSWORD"),
        connect_timeout=30,
    )
    run_id = ""
    today = date.today()
    try:
        run_id = str(
            connection.execute(
                "select public.begin_sync_run(%s, %s, %s, %s, %s)",
                (
                    "customer_opportunities_sync",
                    "app_customer_opportunities",
                    "fast",
                    today,
                    today,
                ),
            ).fetchone()[0]
        )
        connection.commit()

        staged_count = stage_rows_direct(
            connection,
            run_id,
            iter_henrique_rows(registered_tax_ids, source_stats),
        )
        connection.execute(
            "select public.set_sync_run_rows_staged(%s, %s)",
            (run_id, staged_count),
        )
        connection.commit()

        connection.execute("set statement_timeout = '600s'")
        apply_result = connection.execute(
            "select public.apply_customer_opportunities_sync(%s)",
            (run_id,),
        ).fetchone()[0]
        connection.commit()
        return staged_count, dict(apply_result or {})
    except Exception as error:
        connection.rollback()
        if run_id:
            connection.execute(
                "select public.mark_sync_run_failed(%s, %s)",
                (run_id, str(error)[:4000]),
            )
            connection.commit()
        raise
    finally:
        connection.close()


def apply_sync(session: SupabaseSession, run_id: str) -> dict[str, object]:
    response = invoke_rpc(
        session,
        "apply_customer_opportunities_sync",
        {"p_run_id": run_id},
        timeout=600,
    )
    if not isinstance(response, dict):
        return {}
    return {str(key): value for key, value in response.items()}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync customer opportunities from PostgreSQL and Oracle."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Read and compare both sources without writing to Supabase.",
    )
    parser.add_argument(
        "--direct-db",
        action="store_true",
        help=(
            "Write through a direct Supabase PostgreSQL connection instead "
            "of the REST API."
        ),
    )
    args = parser.parse_args()

    registered_tax_ids = fetch_registered_oracle_tax_ids()
    source_stats = {
        "registered_customers": 0,
        "invalid_coordinates": 0,
        "missing_city": 0,
    }
    if args.dry_run:
        opportunity_count = sum(
            1 for _ in iter_henrique_rows(registered_tax_ids, source_stats)
        )
        print(
            json.dumps(
                {
                    "oracle_registered_tax_ids": len(registered_tax_ids),
                    "opportunities": opportunity_count,
                    **source_stats,
                },
                ensure_ascii=False,
            )
        )
        return

    if args.direct_db:
        staged_count, apply_result = run_direct_sync(
            registered_tax_ids,
            source_stats,
        )
        print(
            json.dumps(
                {
                    "oracle_registered_tax_ids": len(registered_tax_ids),
                    "opportunities": staged_count,
                    "rows_staged": staged_count,
                    **source_stats,
                    **apply_result,
                },
                ensure_ascii=False,
            )
        )
        return

    session = authenticate_supabase(require_env)
    today = date.today().isoformat()
    run_id = begin_sync_run(
        session,
        job_name="customer_opportunities_sync",
        target_name="app_customer_opportunities",
        scope_type="fast",
        window_start=today,
        window_end=today,
    )

    try:
        staged_count = stage_rows(
            session,
            run_id,
            iter_henrique_rows(registered_tax_ids, source_stats),
        )
        set_sync_run_rows_staged(session, run_id, staged_count)
        apply_result = apply_sync(session, run_id)
    except Exception as error:
        mark_sync_run_failed(session, run_id, str(error))
        raise

    print(
        json.dumps(
            {
                "oracle_registered_tax_ids": len(registered_tax_ids),
                "opportunities": staged_count,
                "rows_staged": staged_count,
                **source_stats,
                **apply_result,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
