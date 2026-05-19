from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, date, datetime

import oracledb
import requests

from oracle_financial_sync_common import (
    authenticate_supabase,
    init_oracle_client_if_available,
    require_env,
)
from performance_sync_common import (
    INITIAL_SYNC_START_MONTH,
    get_current_month_start,
    get_previous_month_start,
    get_sync_window,
    purge_month_window,
    upsert_rows,
)


SKU_TABLE_NAME = "app_performance_sku_monthly"
SKU_ON_CONFLICT = "profile_slug,owner_code,codfornec,month_start,metric_source"

ORACLE_QUERY_VENDA = """
WITH base_rows AS (
    SELECT
        TRUNC(pcpedc.data, 'MM') AS month_start,
        pcpedi.codprod,
        pcpedi.codusur,
        pcusuari.codsupervisor,
        pcsuperv.codgerente,
        CASE
            WHEN pcprodut.codfornec IN (1535, 1968) THEN 1968
            WHEN pcprodut.codfornec IN (1443, 967) THEN 967
            WHEN pcprodut.codfornec IN (1630, 2445) THEN 1630
            ELSE pcprodut.codfornec
        END AS codfornec
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
)
SELECT
    profile_slug,
    owner_code,
    codfornec,
    month_start,
    COUNT(DISTINCT codprod) AS sku_count
FROM (
    SELECT
        'vendedor' AS profile_slug,
        TO_CHAR(codusur) AS owner_code,
        TO_CHAR(codfornec) AS codfornec,
        month_start,
        codprod
    FROM base_rows

    UNION ALL

    SELECT
        'vendedor' AS profile_slug,
        TO_CHAR(codusur) AS owner_code,
        '1' AS codfornec,
        month_start,
        codprod
    FROM base_rows

    UNION ALL

    SELECT
        'supervisor' AS profile_slug,
        TO_CHAR(codsupervisor) AS owner_code,
        TO_CHAR(codfornec) AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codsupervisor IS NOT NULL

    UNION ALL

    SELECT
        'supervisor' AS profile_slug,
        TO_CHAR(codsupervisor) AS owner_code,
        '1' AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codsupervisor IS NOT NULL

    UNION ALL

    SELECT
        'coordenador' AS profile_slug,
        TO_CHAR(codgerente) AS owner_code,
        TO_CHAR(codfornec) AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codgerente IS NOT NULL

    UNION ALL

    SELECT
        'coordenador' AS profile_slug,
        TO_CHAR(codgerente) AS owner_code,
        '1' AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codgerente IS NOT NULL
) grouped_rows
GROUP BY
    profile_slug,
    owner_code,
    codfornec,
    month_start
ORDER BY
    month_start,
    profile_slug,
    owner_code,
    codfornec
"""

ORACLE_QUERY_FATURAMENTO = """
WITH base_rows AS (
    SELECT
        TRUNC(pcmov.dtmov, 'MM') AS month_start,
        pcmov.codprod,
        pcmov.codusur,
        pcpedc.codsupervisor,
        pcsuperv.codgerente,
        CASE
            WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
            WHEN pcfornec.codfornec IN (1443, 967) THEN 967
            WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
            ELSE pcfornec.codfornec
        END AS codfornec
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
)
SELECT
    profile_slug,
    owner_code,
    codfornec,
    month_start,
    COUNT(DISTINCT codprod) AS sku_count
FROM (
    SELECT
        'vendedor' AS profile_slug,
        TO_CHAR(codusur) AS owner_code,
        TO_CHAR(codfornec) AS codfornec,
        month_start,
        codprod
    FROM base_rows

    UNION ALL

    SELECT
        'vendedor' AS profile_slug,
        TO_CHAR(codusur) AS owner_code,
        '1' AS codfornec,
        month_start,
        codprod
    FROM base_rows

    UNION ALL

    SELECT
        'supervisor' AS profile_slug,
        TO_CHAR(codsupervisor) AS owner_code,
        TO_CHAR(codfornec) AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codsupervisor IS NOT NULL

    UNION ALL

    SELECT
        'supervisor' AS profile_slug,
        TO_CHAR(codsupervisor) AS owner_code,
        '1' AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codsupervisor IS NOT NULL

    UNION ALL

    SELECT
        'coordenador' AS profile_slug,
        TO_CHAR(codgerente) AS owner_code,
        TO_CHAR(codfornec) AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codgerente IS NOT NULL

    UNION ALL

    SELECT
        'coordenador' AS profile_slug,
        TO_CHAR(codgerente) AS owner_code,
        '1' AS codfornec,
        month_start,
        codprod
    FROM base_rows
    WHERE codgerente IS NOT NULL
) grouped_rows
GROUP BY
    profile_slug,
    owner_code,
    codfornec,
    month_start
ORDER BY
    month_start,
    profile_slug,
    owner_code,
    codfornec
"""


@dataclass(frozen=True)
class PerformanceSkuRow:
    metric_source: str
    profile_slug: str
    owner_code: str
    codfornec: str
    month_start: str
    target_year: int
    target_month: int
    sku_count: int
    imported_at: str

    def to_payload(self) -> dict[str, object]:
        return {
            "metric_source": self.metric_source,
            "profile_slug": self.profile_slug,
            "owner_code": self.owner_code,
            "codfornec": self.codfornec,
            "month_start": self.month_start,
            "target_year": self.target_year,
            "target_month": self.target_month,
            "sku_count": self.sku_count,
            "imported_at": self.imported_at,
        }


def _has_metric_source_rows(metric_source: str) -> bool:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")
    response = requests.get(
        f"{supabase_url}/rest/v1/{SKU_TABLE_NAME}",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
        },
        params={
            "select": "id",
            "metric_source": f"eq.{metric_source}",
            "limit": "1",
        },
        timeout=60,
    )
    response.raise_for_status()
    return bool(response.json())


def get_sku_sync_window() -> tuple[date, date]:
    _, sync_end_month = get_sync_window(SKU_TABLE_NAME)
    if not _has_metric_source_rows("faturamento"):
        return INITIAL_SYNC_START_MONTH, sync_end_month
    return get_previous_month_start(get_current_month_start()), sync_end_month


def fetch_oracle_rows(
    sync_start_month: date,
    *,
    metric_source: str,
    query: str,
) -> list[PerformanceSkuRow]:
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
                sync_start_date=datetime.combine(
                    sync_start_month,
                    datetime.min.time(),
                ),
            )
            rows: list[PerformanceSkuRow] = []
            for (
                profile_slug,
                owner_code,
                codfornec,
                month_start,
                sku_count,
            ) in cursor:
                rows.append(
                    PerformanceSkuRow(
                        metric_source=metric_source,
                        profile_slug=str(profile_slug).strip(),
                        owner_code=str(owner_code).strip(),
                        codfornec=str(codfornec).strip(),
                        month_start=month_start.strftime("%Y-%m-%d"),
                        target_year=month_start.year,
                        target_month=month_start.month,
                        sku_count=int(sku_count or 0),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


def main() -> None:
    sync_start_month, sync_end_month = get_sku_sync_window()
    rows = [
        *fetch_oracle_rows(
            sync_start_month,
            metric_source="venda",
            query=ORACLE_QUERY_VENDA,
        ),
        *fetch_oracle_rows(
            sync_start_month,
            metric_source="faturamento",
            query=ORACLE_QUERY_FATURAMENTO,
        ),
    ]
    payload = [
        row.to_payload()
        for row in rows
        if row.month_start <= sync_end_month.isoformat()
    ]

    purged_count = purge_month_window(
        SKU_TABLE_NAME,
        start_month=sync_start_month,
        end_month=sync_end_month,
    )
    upserted_count = upsert_rows(
        SKU_TABLE_NAME,
        on_conflict=SKU_ON_CONFLICT,
        rows=payload,
    )

    print(
        json.dumps(
            {
                "sync_start_month": sync_start_month.isoformat(),
                "sync_end_month": sync_end_month.isoformat(),
                "rows": len(rows),
                "rows_by_metric_source": {
                    "venda": len([row for row in rows if row.metric_source == "venda"]),
                    "faturamento": len(
                        [row for row in rows if row.metric_source == "faturamento"]
                    ),
                },
                "payload_rows": len(payload),
                "purged": purged_count,
                "upserted": upserted_count,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
