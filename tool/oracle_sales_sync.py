from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Iterable

import oracledb

from oracle_financial_sync_common import get_sync_window, require_env
from supabase_sync_common import (
    SupabaseSession,
    authenticate_supabase,
    begin_sync_run,
    insert_rows,
    invoke_rpc,
    mark_sync_run_failed,
    set_sync_run_rows_staged,
)


INITIAL_SYNC_START_DATE = date(2026, 1, 1)

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


def fetch_oracle_rows(sync_start_date: date) -> list[SalesRow]:
    oracle_user = require_env("ORACLE_USER")
    oracle_password = require_env("ORACLE_PASSWORD")
    oracle_dsn = require_env("ORACLE_DSN")

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


def stage_sales_rows(
    session: SupabaseSession,
    run_id: str,
    rows: Iterable[SalesRow],
) -> int:
    deduped_rows: dict[tuple[str, str, str, str, str], SalesRow] = {}
    for row in rows:
        deduped_rows[
            (row.sales_date, row.numped, row.codcli, row.codusur, row.codfornec)
        ] = row

    payload = [
        {
            "run_id": run_id,
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

    return insert_rows(session, "etl_stg_sales_daily_snapshots", payload)


def apply_sales_sync(session: SupabaseSession, run_id: str) -> dict[str, object]:
    response = invoke_rpc(
        session,
        "apply_sales_sync",
        {"p_run_id": run_id},
    )
    if not isinstance(response, dict):
        return {}
    return {str(key): value for key, value in response.items()}


def main() -> None:
    scope_type, sync_start_date, sync_end_date = get_sync_window()
    rows = fetch_oracle_rows(sync_start_date)
    session = authenticate_supabase(require_env)
    run_id = begin_sync_run(
        session,
        job_name="oracle_sales_sync",
        target_name="app_sales_daily_snapshots",
        scope_type=scope_type,
        window_start=sync_start_date.isoformat(),
        window_end=sync_end_date.isoformat(),
    )

    try:
        staged_count = stage_sales_rows(session, run_id, rows)
        set_sync_run_rows_staged(session, run_id, staged_count)
        apply_result = apply_sales_sync(session, run_id)
    except Exception as error:
        mark_sync_run_failed(session, run_id, str(error))
        raise

    total_venda = sum(row.venda for row in rows)
    total_volume = sum(row.volume for row in rows)
    print(
        json.dumps(
            {
                "scope_type": scope_type,
                "sync_start_date": sync_start_date.isoformat(),
                "sync_end_date": sync_end_date.isoformat(),
                "rows": len(rows),
                "rows_staged": staged_count,
                "rows_inserted": apply_result.get("rows_inserted", 0),
                "rows_updated": apply_result.get("rows_updated", 0),
                "rows_deleted": apply_result.get("rows_deleted", 0),
                "total_venda": round(total_venda, 2),
                "total_volume": round(total_volume, 2),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
