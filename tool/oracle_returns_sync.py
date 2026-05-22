from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal

import oracledb

from oracle_financial_sync_common import (
    INITIAL_SYNC_START_DATE,
    apply_financial_sync,
    authenticate_supabase_session,
    create_financial_sync_run,
    fetch_oracle_rows,
    get_sync_window,
    init_oracle_client_if_available,
    require_env,
    stage_financial_rows,
)
from supabase_sync_common import (
    begin_sync_run,
    insert_rows,
    invoke_rpc,
    mark_sync_run_failed,
    set_sync_run_rows_staged,
)


SNAPSHOT_TYPE = "D"

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


def stage_return_detail_rows(
    session,
    run_id: str,
    rows: list[ReturnDetailRow],
) -> int:
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
            "run_id": run_id,
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
    return insert_rows(session, "etl_stg_return_order_items", payload)


def apply_return_items_sync(session, run_id: str) -> dict[str, object]:
    response = invoke_rpc(
        session,
        "apply_return_items_sync",
        {"p_run_id": run_id},
    )
    if not isinstance(response, dict):
        return {}
    return {str(key): value for key, value in response.items()}


def main() -> None:
    scope_type, sync_start_date, sync_end_date = get_sync_window()
    if sync_start_date < INITIAL_SYNC_START_DATE:
        sync_start_date = INITIAL_SYNC_START_DATE

    financial_rows = fetch_oracle_rows(
        SNAPSHOT_TYPE,
        ORACLE_FINANCIAL_QUERY,
        sync_start_date,
    )
    detail_rows = fetch_return_detail_rows(sync_start_date)
    session = authenticate_supabase_session(require_env)

    financial_run_id = create_financial_sync_run(
        session,
        job_name="oracle_returns_financial_sync",
        scope_type=scope_type,
        window_start=sync_start_date,
        window_end=sync_end_date,
    )
    detail_run_id = begin_sync_run(
        session,
        job_name="oracle_return_items_sync",
        target_name="app_return_order_items",
        scope_type=scope_type,
        window_start=sync_start_date.isoformat(),
        window_end=sync_end_date.isoformat(),
    )

    try:
        staged_financial_count = stage_financial_rows(
            session,
            financial_run_id,
            financial_rows,
        )
        set_sync_run_rows_staged(session, financial_run_id, staged_financial_count)
        financial_apply_result = apply_financial_sync(session, financial_run_id)

        staged_detail_count = stage_return_detail_rows(
            session,
            detail_run_id,
            detail_rows,
        )
        set_sync_run_rows_staged(session, detail_run_id, staged_detail_count)
        detail_apply_result = apply_return_items_sync(session, detail_run_id)
    except Exception as error:
        mark_sync_run_failed(session, financial_run_id, str(error))
        mark_sync_run_failed(session, detail_run_id, str(error))
        raise

    total_faturamento = sum(row.faturamento for row in financial_rows)
    total_volume = sum(row.volume for row in financial_rows)
    print(
        json.dumps(
            {
                "snapshot_type": SNAPSHOT_TYPE,
                "scope_type": scope_type,
                "sync_start_date": sync_start_date.isoformat(),
                "sync_end_date": sync_end_date.isoformat(),
                "financial_rows": len(financial_rows),
                "detail_rows": len(detail_rows),
                "staged_financial": staged_financial_count,
                "staged_detail": staged_detail_count,
                "financial_inserted": financial_apply_result.get("rows_inserted", 0),
                "financial_updated": financial_apply_result.get("rows_updated", 0),
                "financial_deleted": financial_apply_result.get("rows_deleted", 0),
                "detail_inserted": detail_apply_result.get("rows_inserted", 0),
                "detail_updated": detail_apply_result.get("rows_updated", 0),
                "detail_deleted": detail_apply_result.get("rows_deleted", 0),
                "total_faturamento": round(total_faturamento, 2),
                "total_volume": round(total_volume, 4),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
