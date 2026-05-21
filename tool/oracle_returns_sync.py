from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import oracledb
import requests

from oracle_financial_sync_common import (
    INITIAL_SYNC_START_DATE,
    authenticate_supabase,
    fetch_oracle_rows,
    get_overlap_days,
    get_min_retroactive_days,
    get_sync_start_date,
    init_oracle_client_if_available,
    purge_supabase_window,
    require_env,
    upsert_supabase_rows,
)


SNAPSHOT_TYPE = "D"
BATCH_SIZE = 1000

ORACLE_FINANCIAL_QUERY = """
SELECT
    pcmov.numped,
    TRUNC(pcmov.dtmov) AS data,
    pcmov.codcli,
    pcmov.codusur,
    pcpedc.codsupervisor,
    pcsuperv.codgerente,
    CASE
        WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
        WHEN pcfornec.codfornec IN (1443, 967) THEN 967
        WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
        ELSE pcfornec.codfornec
    END AS codfornec,
    SUM(pcmov.qt * pcmov.custofin) * -1 AS custo,
    (SUM(pcmov.qt * pcmov.punit) + SUM(pcmov.qt * NVL(pcmov.vloutros, 0))) * -1 AS faturamento,
    0 AS mix,
    SUM(pcmov.qt / NULLIF(pcprodut.qtunitcx, 0)) * -1 AS volume,
    (SUM(pcmov.qt * pcmov.punit) - SUM(pcmov.qt * pcmov.custofin)) * -1 AS lucro
FROM pcmov
JOIN pcnfent
    ON pcmov.numtransent = pcnfent.numtransent
JOIN pcpedc
    ON pcmov.numped = pcpedc.numped
JOIN pcusuari
    ON pcmov.codusur = pcusuari.codusur
JOIN pcsuperv
    ON pcpedc.codsupervisor = pcsuperv.codsupervisor
JOIN pcprodut
    ON pcmov.codprod = pcprodut.codprod
JOIN pcfornec
    ON pcprodut.codfornec = pcfornec.codfornec
WHERE pcmov.dtmov >= :sync_start_date
  AND pcmov.dtmov < TRUNC(SYSDATE) + 1
  AND pcpedc.codfilial IN (1, 3, 4)
  AND pcpedc.condvenda IN (1)
  AND pcmov.dtcancel IS NULL
  AND pcmov.codoper IN ('E', 'ED')
GROUP BY
    pcmov.numped,
    TRUNC(pcmov.dtmov),
    pcmov.codcli,
    pcmov.codusur,
    pcpedc.codsupervisor,
    pcsuperv.codgerente,
    CASE
        WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
        WHEN pcfornec.codfornec IN (1443, 967) THEN 967
        WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
        ELSE pcfornec.codfornec
    END
ORDER BY
    TRUNC(pcmov.dtmov),
    pcmov.codusur,
    pcmov.numped,
    codfornec
"""

ORACLE_DETAIL_QUERY = """
SELECT
    pcmov.numped,
    TRUNC(pcmov.dtmov) AS data,
    pcpedc.codcli,
    INITCAP(pcclient.cliente) AS cliente,
    pcusuari.codusur,
    pcusuari.codsupervisor,
    pcsuperv.codgerente,
    CASE
        WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
        WHEN pcfornec.codfornec IN (1443, 967) THEN 967
        WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
        ELSE pcfornec.codfornec
    END AS codfornec,
    INITCAP(pctabdev.motivo) AS motivo,
    pcmov.codprod,
    INITCAP(pcprodut.descricao) AS descricao,
    (
        SUM(pcmov.qt * pcmov.punit)
        + SUM(pcmov.qt * NVL(pcmov.vloutros, 0))
    ) AS valor,
    SUM(pcmov.qt) AS qt,
    SUM(pcmov.qt / NULLIF(pcprodut.qtunitcx, 0)) AS volume
FROM pcmov
JOIN pcnfent
    ON pcmov.numtransent = pcnfent.numtransent
JOIN pcpedc
    ON pcmov.numped = pcpedc.numped
JOIN pcusuari
    ON pcmov.codusur = pcusuari.codusur
JOIN pcsuperv
    ON pcusuari.codsupervisor = pcsuperv.codsupervisor
JOIN pcprodut
    ON pcmov.codprod = pcprodut.codprod
JOIN pcfornec
    ON pcprodut.codfornec = pcfornec.codfornec
JOIN pctabdev
    ON pctabdev.coddevol = pcnfent.coddevol
JOIN pcclient
    ON pcpedc.codcli = pcclient.codcli
WHERE pcmov.dtmov >= :sync_start_date
  AND pcmov.dtmov < TRUNC(SYSDATE) + 1
  AND pcpedc.codfilial IN (1, 3, 4)
  AND pcpedc.condvenda = 1
  AND pcpedc.dtcancel IS NULL
  AND pcmov.codoper IN ('E', 'ED')
GROUP BY
    pcmov.numped,
    TRUNC(pcmov.dtmov),
    pcpedc.codcli,
    INITCAP(pcclient.cliente),
    pcusuari.codusur,
    pcusuari.codsupervisor,
    pcsuperv.codgerente,
    CASE
        WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
        WHEN pcfornec.codfornec IN (1443, 967) THEN 967
        WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
        ELSE pcfornec.codfornec
    END,
    INITCAP(pctabdev.motivo),
    pcmov.codprod,
    INITCAP(pcprodut.descricao)
ORDER BY
    TRUNC(pcmov.dtmov) DESC,
    pcmov.numped,
    pcmov.codprod
"""


@dataclass(frozen=True)
class ReturnDetailRow:
    return_date: str
    numped: str
    codcli: str
    client_name: str
    codusur: str
    codsupervisor: str
    codgerente: str
    codfornec: str
    return_reason: str
    codprod: str
    product_name: str
    item_value: float
    quantity: float
    volume: float
    imported_at: str


def _normalize_text(value: object | None) -> str:
    return str(value or "").strip()


def _to_float(value: Decimal | float | int | None) -> float:
    if value is None:
        return 0.0
    return float(value)


def fetch_return_detail_rows(sync_start_date: date) -> list[ReturnDetailRow]:
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
                ORACLE_DETAIL_QUERY,
                sync_start_date=datetime.combine(sync_start_date, datetime.min.time()),
            )
            rows: list[ReturnDetailRow] = []
            for (
                numped,
                return_date,
                codcli,
                client_name,
                codusur,
                codsupervisor,
                codgerente,
                codfornec,
                return_reason,
                codprod,
                product_name,
                item_value,
                quantity,
                volume,
            ) in cursor:
                rows.append(
                    ReturnDetailRow(
                        return_date=return_date.strftime("%Y-%m-%d"),
                        numped=_normalize_text(numped),
                        codcli=_normalize_text(codcli),
                        client_name=_normalize_text(client_name),
                        codusur=_normalize_text(codusur),
                        codsupervisor=_normalize_text(codsupervisor),
                        codgerente=_normalize_text(codgerente),
                        codfornec=_normalize_text(codfornec),
                        return_reason=_normalize_text(return_reason),
                        codprod=_normalize_text(codprod),
                        product_name=_normalize_text(product_name),
                        item_value=_to_float(item_value),
                        quantity=_to_float(quantity),
                        volume=_to_float(volume),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


def purge_return_detail_window(sync_start_date: date) -> int:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.delete(
        f"{supabase_url}/rest/v1/app_return_order_items",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Prefer": "return=representation",
        },
        params={
            "return_date": f"gte.{sync_start_date.isoformat()}",
        },
        timeout=300,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase return detail purge failed: {response.status_code} {response.text}"
        )

    deleted_rows = response.json() if response.text.strip() else []
    return len(deleted_rows) if isinstance(deleted_rows, list) else 0


def get_return_detail_sync_start_date() -> date:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.get(
        f"{supabase_url}/rest/v1/app_return_order_items",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
        },
        params={
            "select": "return_date",
            "order": "return_date.desc",
            "limit": "1",
        },
        timeout=60,
    )
    response.raise_for_status()
    rows = response.json()
    if not rows:
        return INITIAL_SYNC_START_DATE

    last_date_raw = str(rows[0].get("return_date") or "").strip()
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


def upsert_return_detail_rows(rows: list[ReturnDetailRow]) -> int:
    deduped_rows: dict[tuple[str, str, str, str, str, str], ReturnDetailRow] = {}
    for row in rows:
        deduped_rows[
            (
                row.return_date,
                row.numped,
                row.codprod,
                row.codfornec,
                row.codusur,
                row.return_reason,
            )
        ] = row

    payload = [
        {
            "return_date": row.return_date,
            "numped": row.numped,
            "codcli": row.codcli,
            "client_name": row.client_name,
            "codusur": row.codusur,
            "codsupervisor": row.codsupervisor,
            "codgerente": row.codgerente,
            "codfornec": row.codfornec,
            "return_reason": row.return_reason,
            "codprod": row.codprod,
            "product_name": row.product_name,
            "item_value": row.item_value,
            "quantity": row.quantity,
            "volume": row.volume,
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
                f"{supabase_url}/rest/v1/app_return_order_items"
                "?on_conflict=return_date,numped,codprod,codfornec,codusur,return_reason"
            ),
            headers=headers,
            data=json.dumps(chunk),
            timeout=300,
        )
        if not response.ok:
            raise RuntimeError(
                f"Supabase return detail upsert failed on batch starting at {start}: "
                f"{response.status_code} {response.text}"
            )
    return len(payload)


def main() -> None:
    sync_start_date = get_sync_start_date(SNAPSHOT_TYPE)
    detail_sync_start_date = get_return_detail_sync_start_date()
    financial_rows = fetch_oracle_rows(
        SNAPSHOT_TYPE,
        ORACLE_FINANCIAL_QUERY,
        sync_start_date,
    )
    detail_rows = fetch_return_detail_rows(detail_sync_start_date)
    purged_financial_count = purge_supabase_window(SNAPSHOT_TYPE, sync_start_date)
    purged_detail_count = purge_return_detail_window(detail_sync_start_date)
    upserted_financial_count = upsert_supabase_rows(financial_rows)
    upserted_detail_count = upsert_return_detail_rows(detail_rows)
    total_faturamento = sum(row.faturamento for row in financial_rows)
    total_volume = sum(row.volume for row in financial_rows)
    print(
        json.dumps(
            {
                "snapshot_type": SNAPSHOT_TYPE,
                "sync_start_date": sync_start_date.isoformat(),
                "detail_sync_start_date": detail_sync_start_date.isoformat(),
                "financial_rows": len(financial_rows),
                "detail_rows": len(detail_rows),
                "purged_financial": purged_financial_count,
                "purged_detail": purged_detail_count,
                "upserted_financial": upserted_financial_count,
                "upserted_detail": upserted_detail_count,
                "total_faturamento": round(total_faturamento, 2),
                "total_volume": round(total_volume, 4),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
