from __future__ import annotations

import csv
import io
import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime

import requests

from performance_sync_common import (
    INITIAL_SYNC_START_MONTH,
    get_current_month_start,
    get_sync_window,
    normalize_owner_code,
    normalize_supplier_code,
    normalize_text,
    parse_decimal_pt_br,
    parse_int_pt_br,
    parse_month_start,
    purge_month_window,
    upsert_rows,
)


SPREADSHEET_ID = "1ahpP8TDBnb207IJQUtUckFq7N_TDhUiBF6aXOhbzkig"
TARGETS_TABLE_NAME = "app_performance_targets"
TARGETS_ON_CONFLICT = "profile_slug,owner_code,codfornec,month_start"


@dataclass(frozen=True)
class SheetConfig:
    profile_slug: str
    source_sheet: str
    gid: str
    owner_column: str


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


SHEETS = (
    SheetConfig(
        profile_slug="vendedor",
        source_sheet="MtV",
        gid="1842567442",
        owner_column="CODUSUR",
    ),
    SheetConfig(
        profile_slug="supervisor",
        source_sheet="MtS",
        gid="1149766167",
        owner_column="CODSUP",
    ),
    SheetConfig(
        profile_slug="coordenador",
        source_sheet="MtC",
        gid="0",
        owner_column="CODCOORD",
    ),
)


def _sheet_export_url(gid: str) -> str:
    return (
        f"https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/export"
        f"?format=csv&gid={gid}"
    )


def _fetch_sheet_rows(config: SheetConfig) -> list[dict[str, str]]:
    response = requests.get(_sheet_export_url(config.gid), timeout=120)
    response.raise_for_status()
    text = response.content.decode("utf-8-sig")
    return [
        {key.strip(): value.strip() for key, value in row.items()}
        for row in csv.DictReader(io.StringIO(text))
    ]


def _build_target_rows(
    config: SheetConfig,
    *,
    start_month,
    end_month,
    imported_at: str,
) -> list[PerformanceTargetRow]:
    rows = _fetch_sheet_rows(config)
    merged_rows: dict[tuple[str, str, str, str], dict[str, object]] = {}

    for row in rows:
        owner_code = normalize_owner_code(row.get(config.owner_column))
        codfornec = normalize_supplier_code(row.get("CODFORNEC"))
        month_start = parse_month_start(
            year_value=row.get("ANO"),
            month_value=row.get("MES"),
        )
        if not owner_code or not codfornec or month_start is None:
            continue
        if month_start < start_month or month_start > end_month:
            continue

        meta_fin = parse_decimal_pt_br(row.get("META_FIN"))
        meta_pos = parse_int_pt_br(row.get("META_POS"))
        meta_sku = parse_int_pt_br(row.get("META_SKU"))
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
    if force_full_sync in {"1", "true", "TRUE", "yes", "YES"}:
        sync_start_month = INITIAL_SYNC_START_MONTH
        sync_end_month = get_current_month_start()
    else:
        sync_start_month, sync_end_month = get_sync_window(TARGETS_TABLE_NAME)
    imported_at = datetime.now(UTC).isoformat(timespec="seconds").replace(
        "+00:00",
        "Z",
    )

    all_rows = []
    row_counts_by_sheet: dict[str, int] = {}
    for config in SHEETS:
        target_rows = _build_target_rows(
            config,
            start_month=sync_start_month,
            end_month=sync_end_month,
            imported_at=imported_at,
        )
        all_rows.extend(target.to_payload() for target in target_rows)
        row_counts_by_sheet[config.source_sheet] = len(target_rows)

    purged_count = purge_month_window(
        TARGETS_TABLE_NAME,
        start_month=sync_start_month,
        end_month=sync_end_month,
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
