from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal

import psycopg2

from performance_sync_common import (
    INITIAL_SYNC_START_MONTH,
    get_current_month_start,
    get_sync_window,
    normalize_owner_code,
    normalize_supplier_code,
    parse_month_start,
    purge_month_window,
    upsert_rows,
)


TARGETS_TABLE_NAME = "app_performance_targets"
TARGETS_ON_CONFLICT = "profile_slug,owner_code,codfornec,month_start"
POSTGRES_HOST = os.getenv("APP_POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("APP_POSTGRES_PORT", "5432"))
POSTGRES_DB = os.getenv("APP_POSTGRES_DB", "Omega")
POSTGRES_USER = os.getenv("APP_POSTGRES_USER", "PwBi")
POSTGRES_PASSWORD = os.getenv("APP_POSTGRES_PASSWORD", "Om3g@123")
POSTGRES_SCHEMA = os.getenv("APP_POSTGRES_SCHEMA", "filial")


@dataclass(frozen=True)
class TargetSourceConfig:
    profile_slug: str
    source_sheet: str
    owner_column: str
    table_name: str
    meta_sku_column: str | None = None


@dataclass(frozen=True)
class PerformanceTargetRow:
    profile_slug: str
    owner_code: str
    codfornec: str
    month_start: str
    target_year: int
    target_month: int
    meta_fin: float
    meta_pos: int | None
    meta_sku: int | None
    source_sheet: str
    imported_at: str

    def to_payload(self) -> dict[str, object]:
        return {
            "profile_slug": self.profile_slug,
            "owner_code": self.owner_code,
            "codfornec": self.codfornec,
            "month_start": self.month_start,
            "target_year": self.target_year,
            "target_month": self.target_month,
            "meta_fin": self.meta_fin,
            "meta_pos": self.meta_pos,
            "meta_sku": self.meta_sku,
            "source_sheet": self.source_sheet,
            "imported_at": self.imported_at,
        }


TARGET_SOURCES = (
    TargetSourceConfig(
        profile_slug="vendedor",
        source_sheet="MtV",
        owner_column="codusur",
        table_name="fmetavendedor",
        meta_sku_column="meta_sku",
    ),
    TargetSourceConfig(
        profile_slug="supervisor",
        source_sheet="MtS",
        owner_column="codsup",
        table_name="fmetasupervisor",
        meta_sku_column="meta_sku",
    ),
    TargetSourceConfig(
        profile_slug="coordenador",
        source_sheet="MtC",
        owner_column="codcoord",
        table_name="fmetacoordenador",
    ),
)


def _to_positive_int(value: object | None) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, Decimal):
        if value <= 0:
            return None
        return int(value)
    try:
        parsed_value = int(value)
    except (TypeError, ValueError):
        return None
    return parsed_value if parsed_value > 0 else None


def _to_positive_float(value: object | None) -> float:
    if value is None or value == "":
        return 0.0
    if isinstance(value, Decimal):
        return float(value) if value > 0 else 0.0
    try:
        parsed_value = float(value)
    except (TypeError, ValueError):
        return 0.0
    return parsed_value if parsed_value > 0 else 0.0


def _get_postgres_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )


def _fetch_table_rows(config: TargetSourceConfig) -> list[dict[str, object]]:
    selected_columns = [
        config.owner_column,
        "codfornec",
        "meta_fin",
        "meta_pos",
        "mes",
        "ano",
    ]
    if config.meta_sku_column:
        selected_columns.append(config.meta_sku_column)

    query = (
        f"SELECT {', '.join(selected_columns)} "
        f"FROM {POSTGRES_SCHEMA}.{config.table_name}"
    )

    with _get_postgres_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(query)
            column_names = [description[0] for description in cursor.description]
            return [
                dict(zip(column_names, row, strict=False))
                for row in cursor.fetchall()
            ]


def _build_target_rows(
    config: TargetSourceConfig,
    *,
    start_month,
    end_month,
    imported_at: str,
) -> list[PerformanceTargetRow]:
    rows = _fetch_table_rows(config)
    merged_rows: dict[tuple[str, str, str, str], dict[str, object]] = {}

    for row in rows:
        owner_code = normalize_owner_code(row.get(config.owner_column))
        codfornec = normalize_supplier_code(row.get("codfornec"))
        month_start = parse_month_start(
            year_value=row.get("ano"),
            month_value=row.get("mes"),
        )
        if not owner_code or not codfornec or month_start is None:
            continue
        if month_start < start_month or month_start > end_month:
            continue

        meta_fin = _to_positive_float(row.get("meta_fin"))
        meta_pos = _to_positive_int(row.get("meta_pos"))
        meta_sku = _to_positive_int(
            row.get(config.meta_sku_column) if config.meta_sku_column else None
        )
        if meta_fin <= 0 and meta_pos is None and meta_sku is None:
            continue

        target_key = (
            config.profile_slug,
            owner_code,
            codfornec,
            month_start.isoformat(),
        )
        existing = merged_rows.get(target_key)
        if existing is None:
            existing = {
                "profile_slug": config.profile_slug,
                "owner_code": owner_code,
                "codfornec": codfornec,
                "month_start": month_start.isoformat(),
                "target_year": month_start.year,
                "target_month": month_start.month,
                "meta_fin": 0.0,
                "meta_pos": None,
                "meta_sku": None,
                "source_sheet": config.source_sheet,
                "imported_at": imported_at,
            }
            merged_rows[target_key] = existing

        if meta_fin > 0:
            existing["meta_fin"] = meta_fin
        if meta_pos is not None and meta_pos > 0:
            existing["meta_pos"] = meta_pos
        if meta_sku is not None and meta_sku > 0:
            existing["meta_sku"] = meta_sku

    return [
        PerformanceTargetRow(
            profile_slug=str(row["profile_slug"]),
            owner_code=str(row["owner_code"]),
            codfornec=str(row["codfornec"]),
            month_start=str(row["month_start"]),
            target_year=int(row["target_year"]),
            target_month=int(row["target_month"]),
            meta_fin=float(row["meta_fin"]),
            meta_pos=row["meta_pos"] if isinstance(row["meta_pos"], int) else None,
            meta_sku=row["meta_sku"] if isinstance(row["meta_sku"], int) else None,
            source_sheet=str(row["source_sheet"]),
            imported_at=str(row["imported_at"]),
        )
        for row in merged_rows.values()
    ]


def main() -> None:
    force_full_sync = os.getenv("PERFORMANCE_TARGETS_FULL_SYNC", "").strip()
    current_month_start = get_current_month_start()
    if force_full_sync in {"1", "true", "TRUE", "yes", "YES"}:
        sync_start_month = INITIAL_SYNC_START_MONTH
        sync_end_month = current_month_start
    else:
        sync_start_month, sync_end_month = get_sync_window(TARGETS_TABLE_NAME)
    imported_at = datetime.now(UTC).isoformat(timespec="seconds").replace(
        "+00:00",
        "Z",
    )

    all_rows = []
    row_counts_by_sheet: dict[str, int] = {}
    for config in TARGET_SOURCES:
        target_rows = _build_target_rows(
            config,
            start_month=sync_start_month,
            end_month=sync_end_month,
            imported_at=imported_at,
        )
        all_rows.extend(target.to_payload() for target in target_rows)
        row_counts_by_sheet[config.source_sheet] = len(target_rows)

    purge_start_month = sync_start_month if force_full_sync in {"1", "true", "TRUE", "yes", "YES"} else current_month_start
    purged_count = 0
    if purge_start_month >= sync_start_month and purge_start_month <= sync_end_month:
        purged_count = purge_month_window(
            TARGETS_TABLE_NAME,
            start_month=purge_start_month,
            end_month=purge_start_month if purge_start_month == current_month_start else sync_end_month,
        )
    upserted_count = upsert_rows(
        TARGETS_TABLE_NAME,
        on_conflict=TARGETS_ON_CONFLICT,
        rows=all_rows,
    )

    print(
        json.dumps(
            {
                "sync_start_month": sync_start_month.isoformat(),
                "sync_end_month": sync_end_month.isoformat(),
                "rows": len(all_rows),
                "rows_by_sheet": row_counts_by_sheet,
                "purged": purged_count,
                "upserted": upserted_count,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
