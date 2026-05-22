from __future__ import annotations

import json

from oracle_financial_sync_common import (
    apply_financial_sync,
    authenticate_supabase_session,
    create_financial_sync_run,
    fetch_oracle_rows,
    get_sync_window,
    require_env,
    stage_financial_rows,
)
from supabase_sync_common import mark_sync_run_failed, set_sync_run_rows_staged


SNAPSHOT_TYPE = "F"

ORACLE_QUERY = """
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
    SUM(pcmov.qt * pcmov.custofin) AS custo,
    SUM(pcmov.qt * pcmov.punit)
      + SUM(pcmov.qt * NVL(pcmov.vloutros, 0)) AS faturamento,
    COUNT(DISTINCT pcmov.codprod) AS mix,
    SUM(pcmov.qt / NULLIF(pcprodut.qtunitcx, 0)) AS volume,
    SUM(pcmov.qt * pcmov.punit) - SUM(pcmov.qt * pcmov.custofin) AS lucro
FROM pcmov
JOIN pcnfsaid
    ON pcmov.numtransvenda = pcnfsaid.numtransvenda
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
  AND pcmov.codoper NOT IN ('SR', 'SO')
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


def main() -> None:
    scope_type, sync_start_date, sync_end_date = get_sync_window()
    rows = fetch_oracle_rows(SNAPSHOT_TYPE, ORACLE_QUERY, sync_start_date)
    session = authenticate_supabase_session(require_env)
    run_id = create_financial_sync_run(
        session,
        job_name="oracle_billing_sync",
        scope_type=scope_type,
        window_start=sync_start_date,
        window_end=sync_end_date,
    )

    try:
        staged_count = stage_financial_rows(session, run_id, rows)
        set_sync_run_rows_staged(session, run_id, staged_count)
        apply_result = apply_financial_sync(session, run_id)
    except Exception as error:
        mark_sync_run_failed(session, run_id, str(error))
        raise

    total_faturamento = sum(row.faturamento for row in rows)
    total_volume = sum(row.volume for row in rows)
    print(
        json.dumps(
            {
                "snapshot_type": SNAPSHOT_TYPE,
                "scope_type": scope_type,
                "sync_start_date": sync_start_date.isoformat(),
                "sync_end_date": sync_end_date.isoformat(),
                "rows": len(rows),
                "rows_staged": staged_count,
                "rows_inserted": apply_result.get("rows_inserted", 0),
                "rows_updated": apply_result.get("rows_updated", 0),
                "rows_deleted": apply_result.get("rows_deleted", 0),
                "total_faturamento": round(total_faturamento, 2),
                "total_volume": round(total_volume, 4),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
