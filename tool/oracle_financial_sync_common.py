from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Iterable

import oracledb
import requests


INITIAL_SYNC_START_DATE = date(2026, 1, 1)
DEFAULT_OPEN_DAY_OVERLAP_DAYS = 0
DEFAULT_CLOSED_DAY_OVERLAP_DAYS = 7
DEFAULT_MIN_RETROACTIVE_DAYS = 30
BATCH_SIZE = 1000


@dataclass(frozen=True)
class FinancialRow:
    snapshot_type: str
    snapshot_date: str
    numped: str
    codcli: str
    codusur: str
    codsupervisor: str
    codgerente: str
    codfornec: str
    faturamento: float
    volume: float
    custo: float
    lucro: float
    mix: float
    imported_at: str


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def get_overlap_days(*, is_open_day: bool) -> int:
    env_name = (
        "OPEN_DAY_OVERLAP_DAYS"
        if is_open_day
        else "CLOSED_DAY_OVERLAP_DAYS"
    )
    default_value = (
        DEFAULT_OPEN_DAY_OVERLAP_DAYS
        if is_open_day
        else DEFAULT_CLOSED_DAY_OVERLAP_DAYS
    )
    raw_value = os.getenv(env_name, "").strip()
    if not raw_value:
        return default_value

    try:
        return max(0, int(raw_value))
    except ValueError:
        return default_value


def get_min_retroactive_days() -> int:
    raw_value = os.getenv("MIN_RETROACTIVE_DAYS", "").strip()
    if not raw_value:
        return DEFAULT_MIN_RETROACTIVE_DAYS

    try:
        return max(0, int(raw_value))
    except ValueError:
        return DEFAULT_MIN_RETROACTIVE_DAYS


def init_oracle_client_if_available() -> None:
    candidates = [
        os.getenv("ORACLE_CLIENT_LIB_DIR", "").strip(),
        r"C:\instantclient_23_7",
        r"C:\Program Files\Oracle Client for Microsoft Tools",
        r"C:\Program Files (x86)\Oracle Client for Microsoft Tools",
    ]

    for candidate in candidates:
        if not candidate:
            continue
        if Path(candidate).exists():
            try:
                oracledb.init_oracle_client(lib_dir=candidate)
                return
            except oracledb.ProgrammingError:
                return
            except Exception:
                continue


def authenticate_supabase() -> tuple[str, str]:
    supabase_url = require_env("SUPABASE_URL")
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")
    admin_email = require_env("SUPABASE_ADMIN_EMAIL")
    admin_password = require_env("SUPABASE_ADMIN_PASSWORD")

    response = requests.post(
        f"{supabase_url}/auth/v1/token?grant_type=password",
        headers={
            "apikey": publishable_key,
            "Content-Type": "application/json",
        },
        json={
            "email": admin_email,
            "password": admin_password,
        },
        timeout=60,
    )
    response.raise_for_status()
    access_token = response.json()["access_token"]
    return supabase_url, access_token


def get_sync_start_date(snapshot_type: str) -> date:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.get(
        f"{supabase_url}/rest/v1/app_financial_snapshots",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
        },
        params={
            "select": "snapshot_date",
            "snapshot_type": f"eq.{snapshot_type}",
            "order": "snapshot_date.desc",
            "limit": "1",
        },
        timeout=60,
    )
    response.raise_for_status()
    rows = response.json()
    if not rows:
        return INITIAL_SYNC_START_DATE

    last_date_raw = str(rows[0].get("snapshot_date") or "").strip()
    if not last_date_raw:
        return INITIAL_SYNC_START_DATE

    last_date = date.fromisoformat(last_date_raw)
    today = date.today()
    overlap_days = get_overlap_days(is_open_day=last_date >= today)
    retroactive_days = get_min_retroactive_days()
    overlap_start_date = last_date - timedelta(days=overlap_days)
    retroactive_start_date = today - timedelta(days=retroactive_days)
    sync_start_date = min(overlap_start_date, retroactive_start_date)
    if sync_start_date < INITIAL_SYNC_START_DATE:
        sync_start_date = INITIAL_SYNC_START_DATE
    return sync_start_date


def purge_supabase_window(snapshot_type: str, sync_start_date: date) -> int:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.delete(
        f"{supabase_url}/rest/v1/app_financial_snapshots",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Prefer": "return=representation",
        },
        params={
            "snapshot_type": f"eq.{snapshot_type}",
            "snapshot_date": f"gte.{sync_start_date.isoformat()}",
        },
        timeout=300,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase purge failed: {response.status_code} {response.text}"
        )

    deleted_rows = response.json() if response.text.strip() else []
    return len(deleted_rows) if isinstance(deleted_rows, list) else 0


def fetch_oracle_rows(snapshot_type: str, query: str, sync_start_date: date) -> list[FinancialRow]:
    oracle_user = require_env("ORACLE_USER")
    oracle_password = require_env("ORACLE_PASSWORD")
    oracle_dsn = require_env("ORACLE_DSN")

    init_oracle_client_if_available()
    connection = oracledb.connect(
        user=oracle_user,
        password=oracle_password,
        dsn=oracle_dsn,
    )

    imported_at = datetime.now(UTC).isoformat(timespec="seconds").replace(
        "+00:00",
        "Z",
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                query,
                sync_start_date=datetime.combine(sync_start_date, datetime.min.time()),
            )
            rows: list[FinancialRow] = []
            for (
                numped,
                snapshot_date,
                codcli,
                codusur,
                codsupervisor,
                codgerente,
                codfornec,
                custo,
                faturamento,
                mix,
                volume,
                lucro,
            ) in cursor:
                rows.append(
                    FinancialRow(
                        snapshot_type=snapshot_type,
                        snapshot_date=snapshot_date.strftime("%Y-%m-%d"),
                        numped=normalize_text(numped),
                        codcli=normalize_text(codcli),
                        codusur=normalize_text(codusur),
                        codsupervisor=normalize_text(codsupervisor),
                        codgerente=normalize_text(codgerente),
                        codfornec=normalize_text(codfornec),
                        custo=to_float(custo),
                        faturamento=to_float(faturamento),
                        mix=to_float(mix),
                        volume=to_float(volume),
                        lucro=to_float(lucro),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


def upsert_supabase_rows(rows: Iterable[FinancialRow]) -> int:
    deduped_rows: dict[tuple[str, str, str, str, str, str], FinancialRow] = {}
    for row in rows:
        deduped_rows[
            (
                row.snapshot_type,
                row.snapshot_date,
                row.numped,
                row.codcli,
                row.codusur,
                row.codfornec,
            )
        ] = row

    payload = [
        {
            "snapshot_type": row.snapshot_type,
            "snapshot_date": row.snapshot_date,
            "numped": row.numped,
            "codcli": row.codcli,
            "codusur": row.codusur,
            "codsupervisor": row.codsupervisor,
            "codgerente": row.codgerente,
            "codfornec": row.codfornec,
            "faturamento": row.faturamento,
            "volume": row.volume,
            "custo": row.custo,
            "lucro": row.lucro,
            "mix": row.mix,
            "imported_at": row.imported_at,
        }
        for row in deduped_rows.values()
    ]

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
            (
                f"{supabase_url}/rest/v1/app_financial_snapshots"
                "?on_conflict=snapshot_type,snapshot_date,numped,codcli,codusur,codfornec"
            ),
            headers=headers,
            data=json.dumps(chunk),
            timeout=300,
        )
        if not response.ok:
            raise RuntimeError(
                f"Supabase upsert failed on batch starting at {start}: "
                f"{response.status_code} {response.text}"
            )
    return len(payload)


def normalize_text(value: object | None) -> str:
    return str(value or "").strip()


def to_float(value: Decimal | float | int | None) -> float:
    if value is None:
        return 0.0
    return float(value)
