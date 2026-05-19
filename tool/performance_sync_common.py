from __future__ import annotations

import json
import re
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Iterable

import requests

from oracle_financial_sync_common import authenticate_supabase, require_env


INITIAL_SYNC_START_MONTH = date(2026, 1, 1)
BATCH_SIZE = 1000

_MONTH_NAME_TO_NUMBER = {
    "jan": 1,
    "fev": 2,
    "mar": 3,
    "abr": 4,
    "mai": 5,
    "jun": 6,
    "jul": 7,
    "ago": 8,
    "set": 9,
    "out": 10,
    "nov": 11,
    "dez": 12,
}

_SUPPLIER_CODE_MAP = {
    1443: 967,
    967: 967,
    1535: 1968,
    1968: 1968,
    1630: 1630,
    2445: 1630,
}


def normalize_text(value: object | None) -> str:
    return str(value or "").strip()


def normalize_owner_code(value: object | None) -> str:
    raw_value = normalize_text(value)
    if not raw_value:
        return ""
    digits = re.findall(r"\d+", raw_value)
    if not digits:
        return ""
    return digits[0].lstrip("0") or "0"


def normalize_supplier_code(value: object | None) -> str:
    raw_value = normalize_text(value)
    if not raw_value:
        return ""

    numbers = [int(match) for match in re.findall(r"\d+", raw_value)]
    if not numbers:
        return ""

    normalized_numbers = []
    for number in numbers:
        normalized_number = _SUPPLIER_CODE_MAP.get(number, number)
        if normalized_number not in normalized_numbers:
            normalized_numbers.append(normalized_number)

    return str(normalized_numbers[-1])


def parse_month_start(*, year_value: object | None, month_value: object | None) -> date | None:
    raw_year = normalize_text(year_value)
    raw_month = normalize_text(month_value).lower()[:3]
    if not raw_year or not raw_month:
        return None

    try:
        year = int(raw_year)
    except ValueError:
        return None

    month = _MONTH_NAME_TO_NUMBER.get(raw_month)
    if month is None:
        return None

    return date(year, month, 1)


def parse_decimal_pt_br(value: object | None) -> float:
    raw_value = normalize_text(value)
    if not raw_value:
        return 0.0

    normalized = raw_value.replace(".", "").replace(",", ".")
    try:
        return float(Decimal(normalized))
    except (InvalidOperation, ValueError):
        return 0.0


def parse_int_pt_br(value: object | None) -> int | None:
    raw_value = normalize_text(value)
    if not raw_value:
        return None

    normalized = raw_value.replace(".", "")
    try:
        return int(Decimal(normalized))
    except (InvalidOperation, ValueError):
        return None


def get_current_month_start(today: date | None = None) -> date:
    reference_date = today or date.today()
    return date(reference_date.year, reference_date.month, 1)


def get_previous_month_start(current_month_start: date) -> date:
    if current_month_start.month == 1:
        return date(current_month_start.year - 1, 12, 1)
    return date(current_month_start.year, current_month_start.month - 1, 1)


def get_sync_window(table_name: str, *, month_column: str = "month_start") -> tuple[date, date]:
    current_month_start = get_current_month_start()
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.get(
        f"{supabase_url}/rest/v1/{table_name}",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
        },
        params={
            "select": month_column,
            "order": f"{month_column}.desc",
            "limit": "1",
        },
        timeout=60,
    )
    response.raise_for_status()
    rows = response.json()
    if not rows:
        return INITIAL_SYNC_START_MONTH, current_month_start

    return get_previous_month_start(current_month_start), current_month_start


def purge_month_window(
    table_name: str,
    *,
    start_month: date,
    end_month: date,
    month_column: str = "month_start",
) -> int:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.delete(
        f"{supabase_url}/rest/v1/{table_name}",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Prefer": "return=representation",
        },
        params={
            "and": (
                f"({month_column}.gte.{start_month.isoformat()},"
                f"{month_column}.lte.{end_month.isoformat()})"
            ),
        },
        timeout=300,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase purge failed for {table_name}: "
            f"{response.status_code} {response.text}"
        )

    deleted_rows = response.json() if response.text.strip() else []
    return len(deleted_rows) if isinstance(deleted_rows, list) else 0


def upsert_rows(
    table_name: str,
    *,
    on_conflict: str,
    rows: Iterable[dict[str, object]],
) -> int:
    payload = list(rows)
    if not payload:
        return 0

    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")
    headers = {
        "apikey": publishable_key,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }

    for start in range(0, len(payload), BATCH_SIZE):
        chunk = payload[start : start + BATCH_SIZE]
        response = requests.post(
            f"{supabase_url}/rest/v1/{table_name}?on_conflict={on_conflict}",
            headers=headers,
            data=json.dumps(chunk),
            timeout=300,
        )
        if not response.ok:
            raise RuntimeError(
                f"Supabase upsert failed for {table_name} on batch {start}: "
                f"{response.status_code} {response.text}"
            )

    return len(payload)
