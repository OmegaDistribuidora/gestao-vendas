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
OPEN_DAY_OVERLAP_DAYS = 0
CLOSED_DAY_OVERLAP_DAYS = 1
BATCH_SIZE = 1000

ORACLE_QUERY = """
SELECT
  pcpedi.numped,
  TRUNC(pcpedc.data) AS data,
  pcpedi.codcli,
  pcpedi.codusur,
  pcusuari.codsupervisor,
  pcsuperv.codgerente,
  CASE
    WHEN pcprodut.codfornec IN (1535, 1968) THEN 1968
    WHEN pcprodut.codfornec IN (1443, 967) THEN 967
    WHEN pcprodut.codfornec IN (1630, 2445) THEN 1630
    ELSE pcprodut.codfornec
  END AS codfornec,
  SUM(pcpedi.qt * pcpedi.pvenda) AS venda,
  SUM(pcpedi.qt / NULLIF(pcprodut.qtunitcx, 0)) AS volume
FROM pcpedi
JOIN pcpedc
  ON pcpedi.numped = pcpedc.numped
JOIN pcprodut
  ON pcpedi.codprod = pcprodut.codprod
JOIN pcusuari
  ON pcpedi.codusur = pcusuari.codusur
JOIN pcsuperv
  ON pcusuari.codsupervisor = pcsuperv.codsupervisor
WHERE pcpedi.data >= :sync_start_date
  AND pcpedi.data < TRUNC(SYSDATE) + 1
  AND pcpedc.codfilial IN (1, 3, 4)
  AND pcpedc.condvenda = 1
  AND pcpedc.dtcancel IS NULL
GROUP BY
  pcpedi.numped,
  TRUNC(pcpedc.data),
  pcpedi.codcli,
  pcpedi.codusur,
  pcusuari.codsupervisor,
  pcsuperv.codgerente,
  CASE
    WHEN pcprodut.codfornec IN (1535, 1968) THEN 1968
    WHEN pcprodut.codfornec IN (1443, 967) THEN 967
    WHEN pcprodut.codfornec IN (1630, 2445) THEN 1630
    ELSE pcprodut.codfornec
  END
ORDER BY
  data,
  pcpedi.codusur,
  pcpedi.numped,
  codfornec
"""


@dataclass(frozen=True)
class SalesRow:
    sales_date: str
    numped: str
    codcli: str
    codusur: str
    codsupervisor: str
    codgerente: str
    codfornec: str
    venda: float
    volume: float
    imported_at: str


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def _to_float(value: Decimal | float | int | None) -> float:
    if value is None:
        return 0.0
    return float(value)


def _normalize_text(value: object | None) -> str:
    return str(value or "").strip()


def _init_oracle_client_if_available() -> None:
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
    supabase_url = _require_env("SUPABASE_URL")
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")
    admin_email = _require_env("SUPABASE_ADMIN_EMAIL")
    admin_password = _require_env("SUPABASE_ADMIN_PASSWORD")

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


def get_sync_start_date() -> date:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.get(
        f"{supabase_url}/rest/v1/app_sales_daily_snapshots",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
        },
        params={
            "select": "sales_date",
            "order": "sales_date.desc",
            "limit": "1",
        },
        timeout=60,
    )
    response.raise_for_status()
    rows = response.json()
    if not rows:
        return INITIAL_SYNC_START_DATE

    last_date_raw = str(rows[0].get("sales_date") or "").strip()
    if not last_date_raw:
        return INITIAL_SYNC_START_DATE

    last_date = date.fromisoformat(last_date_raw)
    today = date.today()
    overlap_days = (
        OPEN_DAY_OVERLAP_DAYS if last_date >= today else CLOSED_DAY_OVERLAP_DAYS
    )
    sync_start_date = last_date - timedelta(days=overlap_days)
    if sync_start_date < INITIAL_SYNC_START_DATE:
        sync_start_date = INITIAL_SYNC_START_DATE
    return sync_start_date


def fetch_oracle_rows(sync_start_date: date) -> list[SalesRow]:
    oracle_user = _require_env("ORACLE_USER")
    oracle_password = _require_env("ORACLE_PASSWORD")
    oracle_dsn = _require_env("ORACLE_DSN")

    _init_oracle_client_if_available()
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
                ORACLE_QUERY,
                sync_start_date=datetime.combine(sync_start_date, datetime.min.time()),
            )
            rows = []
            for (
                numped,
                sales_date,
                codcli,
                codusur,
                codsupervisor,
                codgerente,
                codfornec,
                venda,
                volume,
            ) in cursor:
                rows.append(
                    SalesRow(
                        sales_date=sales_date.strftime("%Y-%m-%d"),
                        numped=_normalize_text(numped),
                        codcli=_normalize_text(codcli),
                        codusur=_normalize_text(codusur),
                        codsupervisor=_normalize_text(codsupervisor),
                        codgerente=_normalize_text(codgerente),
                        codfornec=_normalize_text(codfornec),
                        venda=_to_float(venda),
                        volume=_to_float(volume),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


def upsert_supabase_rows(rows: Iterable[SalesRow]) -> int:
    deduped_rows: dict[tuple[str, str, str, str, str], SalesRow] = {}
    for row in rows:
        deduped_rows[
            (row.sales_date, row.numped, row.codcli, row.codusur, row.codfornec)
        ] = row

    payload = [
        {
            "sales_date": row.sales_date,
            "numped": row.numped,
            "codcli": row.codcli,
            "codusur": row.codusur,
            "codsupervisor": row.codsupervisor,
            "codgerente": row.codgerente,
            "codfornec": row.codfornec,
            "venda": row.venda,
            "volume": row.volume,
            "imported_at": row.imported_at,
        }
        for row in deduped_rows.values()
    ]

    if not payload:
        return 0

    supabase_url, access_token = authenticate_supabase()
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")

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
                f"{supabase_url}/rest/v1/app_sales_daily_snapshots"
                "?on_conflict=sales_date,numped,codcli,codusur,codfornec"
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


def main() -> None:
    sync_start_date = get_sync_start_date()
    rows = fetch_oracle_rows(sync_start_date)
    upserted_count = upsert_supabase_rows(rows)
    total_venda = sum(row.venda for row in rows)
    total_volume = sum(row.volume for row in rows)
    print(
        json.dumps(
            {
                "sync_start_date": sync_start_date.isoformat(),
                "rows": len(rows),
                "upserted": upserted_count,
                "total_venda": round(total_venda, 2),
                "total_volume": round(total_volume, 2),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
