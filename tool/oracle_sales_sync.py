from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from typing import Iterable

import oracledb
import requests


ORACLE_QUERY = """
SELECT
  base.numped,
  base.data,
  base.codcli,
  base.codusur,
  SUM(base.venda) AS venda,
  SUM(base.volume) AS volume
FROM (
  SELECT
    pcpedi.numped,
    TRUNC(pcpedc.data) AS data,
    pcpedi.codcli,
    pcpedi.codusur,
    SUM(pcpedi.qt * pcpedi.pvenda) AS venda,
    SUM(pcpedi.qt / NULLIF(pcprodut.qtunitcx, 0)) AS volume
  FROM pcpedi
  JOIN pcpedc
    ON pcpedi.numped = pcpedc.numped
  JOIN pcprodut
    ON pcpedi.codprod = pcprodut.codprod
  WHERE TRUNC(pcpedi.data) = TRUNC(SYSDATE)
    AND pcpedc.codfilial IN (1, 3, 4)
    AND pcpedc.condvenda = 1
    AND pcpedc.dtcancel IS NULL
  GROUP BY
    pcpedi.numped,
    TRUNC(pcpedc.data),
    pcpedi.codcli,
    pcpedi.codusur,
    pcpedi.posicao,
    CASE
      WHEN pcprodut.codfornec IN (1535, 1968) THEN 1968
      WHEN pcprodut.codfornec IN (1443, 967) THEN 967
      WHEN pcprodut.codfornec IN (1630, 2445) THEN 1630
      ELSE pcprodut.codfornec
    END,
    pcprodut.codsec,
    pcpedi.codprod,
    pcpedi.pvenda,
    pcpedi.ptabela,
    pcpedi.codcombo,
    pcpedi.perdesc,
    pcpedi.qt
) base
GROUP BY
  base.numped,
  base.data,
  base.codcli,
  base.codusur
ORDER BY
  base.data,
  base.codusur,
  base.numped
"""


@dataclass(frozen=True)
class SalesRow:
    sales_date: str
    numped: str
    codcli: str
    codusur: str
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


def fetch_oracle_rows() -> list[SalesRow]:
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
            cursor.execute(ORACLE_QUERY)
            rows = []
            for numped, sales_date, codcli, codusur, venda, volume in cursor:
                rows.append(
                    SalesRow(
                        sales_date=sales_date.strftime("%Y-%m-%d"),
                        numped=str(numped),
                        codcli=str(codcli),
                        codusur=str(codusur),
                        venda=_to_float(venda),
                        volume=_to_float(volume),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


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


def upsert_supabase_rows(rows: Iterable[SalesRow]) -> int:
    payload = [
        {
            "sales_date": row.sales_date,
            "numped": row.numped,
            "codcli": row.codcli,
            "codusur": row.codusur,
            "venda": row.venda,
            "volume": row.volume,
            "imported_at": row.imported_at,
        }
        for row in rows
    ]

    if not payload:
        return 0

    supabase_url, access_token = authenticate_supabase()
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.post(
        (
            f"{supabase_url}/rest/v1/app_sales_daily_snapshots"
            "?on_conflict=sales_date,numped,codcli,codusur"
        ),
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
        data=json.dumps(payload),
        timeout=120,
    )
    response.raise_for_status()
    return len(payload)


def main() -> None:
    rows = fetch_oracle_rows()
    upserted_count = upsert_supabase_rows(rows)
    total_venda = sum(row.venda for row in rows)
    total_volume = sum(row.volume for row in rows)
    print(
        json.dumps(
            {
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
