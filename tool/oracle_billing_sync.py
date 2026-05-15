from __future__ import annotations

import json

from oracle_financial_sync_common import (
    fetch_oracle_rows,
    get_sync_start_date,
    purge_supabase_window,
    upsert_supabase_rows,
)


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
    sync_start_date = get_sync_start_date(SNAPSHOT_TYPE)
    rows = fetch_oracle_rows(SNAPSHOT_TYPE, ORACLE_QUERY, sync_start_date)
    purged_count = purge_supabase_window(SNAPSHOT_TYPE, sync_start_date)
    upserted_count = upsert_supabase_rows(rows)
    total_faturamento = sum(row.faturamento for row in rows)
    total_volume = sum(row.volume for row in rows)
    print(
        json.dumps(
            {
                "snapshot_type": SNAPSHOT_TYPE,
                "sync_start_date": sync_start_date.isoformat(),
                "rows": len(rows),
                "purged": purged_count,
                "upserted": upserted_count,
                "total_faturamento": round(total_faturamento, 2),
                "total_volume": round(total_volume, 4),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
