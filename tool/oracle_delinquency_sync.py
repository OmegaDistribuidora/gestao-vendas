from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime

import oracledb
import requests

from oracle_financial_sync_common import (
    BATCH_SIZE,
    authenticate_supabase,
    init_oracle_client_if_available,
    normalize_text,
    require_env,
    to_float,
)


TABLE_NAME = "app_delinquency_items"

ORACLE_QUERY = """
SELECT
    TRUNC(pcprest.dtemissao) AS dtemissao,
    TRUNC(pcprest.dtpag) AS dtpag,
    TRUNC(pcprest.dtvenc) AS dtvenc,
    pcprest.numped,
    pcprest.numtransvenda,
    pcprest.codcli,
    INITCAP(pcclient.cliente) AS client_name,
    pcprest.codusur,
    pcprest.codusur2,
    pcusuari.codsupervisor,
    pcsuperv.codgerente,
    pcprest.prest AS prestacao,
    pcprest.duplic AS duplicata,
    pcprest.codcob,
    CASE
        WHEN pcprest.codcob = 'PERD' THEN 'Perdas'
        ELSE 'Geral'
    END AS tipo,
    pcprest.codcoborig,
    pcprest.codfilial,
    pcprest.status,
    pcprest.valor,
    pcprest.vpago,
    pcprest.valordesc,
    pcprest.valororig
FROM pcprest
LEFT JOIN pcclient
    ON pcprest.codcli = pcclient.codcli
LEFT JOIN pcusuari
    ON pcprest.codusur = pcusuari.codusur
LEFT JOIN pcsuperv
    ON pcusuari.codsupervisor = pcsuperv.codsupervisor
WHERE pcprest.dtvenc BETWEEN TO_DATE(EXTRACT(YEAR FROM SYSDATE) - 5 || '-01-01', 'YYYY-MM-DD')
  AND TO_DATE(EXTRACT(YEAR FROM SYSDATE) || '-12-31', 'YYYY-MM-DD')
  AND pcprest.codcob NOT IN ('BNF')
  AND pcprest.dtpag IS NULL
ORDER BY pcprest.dtvenc DESC
"""


@dataclass(frozen=True)
class DelinquencyRow:
    dtemissao: str
    dtpag: str | None
    dtvenc: str
    numped: str
    numtransvenda: str
    codcli: str
    client_name: str
    codusur: str
    codusur2: str
    codsupervisor: str
    codgerente: str
    prestacao: str
    duplicata: str
    codcob: str
    tipo: str
    codcoborig: str
    codfilial: str
    status: str
    valor: float
    vpago: float
    valordesc: float
    valororig: float
    imported_at: str


def fetch_oracle_rows() -> list[DelinquencyRow]:
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
            cursor.execute(ORACLE_QUERY)
            rows: list[DelinquencyRow] = []
            for (
                dtemissao,
                dtpag,
                dtvenc,
                numped,
                numtransvenda,
                codcli,
                client_name,
                codusur,
                codusur2,
                codsupervisor,
                codgerente,
                prestacao,
                duplicata,
                codcob,
                tipo,
                codcoborig,
                codfilial,
                status,
                valor,
                vpago,
                valordesc,
                valororig,
            ) in cursor:
                rows.append(
                    DelinquencyRow(
                        dtemissao=dtemissao.strftime("%Y-%m-%d"),
                        dtpag=dtpag.strftime("%Y-%m-%d") if dtpag else None,
                        dtvenc=dtvenc.strftime("%Y-%m-%d"),
                        numped=normalize_text(numped),
                        numtransvenda=normalize_text(numtransvenda),
                        codcli=normalize_text(codcli),
                        client_name=normalize_text(client_name),
                        codusur=normalize_text(codusur),
                        codusur2=normalize_text(codusur2),
                        codsupervisor=normalize_text(codsupervisor),
                        codgerente=normalize_text(codgerente),
                        prestacao=normalize_text(prestacao),
                        duplicata=normalize_text(duplicata),
                        codcob=normalize_text(codcob),
                        tipo=normalize_text(tipo) or "Geral",
                        codcoborig=normalize_text(codcoborig),
                        codfilial=normalize_text(codfilial),
                        status=normalize_text(status),
                        valor=to_float(valor),
                        vpago=to_float(vpago),
                        valordesc=to_float(valordesc),
                        valororig=to_float(valororig),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


def purge_supabase_rows() -> int:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.delete(
        f"{supabase_url}/rest/v1/{TABLE_NAME}",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Prefer": "return=representation",
        },
        params={
            "id": "not.is.null",
        },
        timeout=300,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase delinquency purge failed: {response.status_code} {response.text}"
        )

    deleted_rows = response.json() if response.text.strip() else []
    return len(deleted_rows) if isinstance(deleted_rows, list) else 0


def upsert_supabase_rows(rows: list[DelinquencyRow]) -> int:
    deduped_rows: dict[tuple[str, str, str, str, str, str], DelinquencyRow] = {}
    for row in rows:
        deduped_rows[
            (
                row.dtvenc,
                row.numped,
                row.codcli,
                row.codusur,
                row.prestacao,
                row.duplicata,
            )
        ] = row

    payload = [
        {
            "dtemissao": row.dtemissao,
            "dtpag": row.dtpag,
            "dtvenc": row.dtvenc,
            "numped": row.numped,
            "numtransvenda": row.numtransvenda,
            "codcli": row.codcli,
            "client_name": row.client_name,
            "codusur": row.codusur,
            "codusur2": row.codusur2,
            "codsupervisor": row.codsupervisor,
            "codgerente": row.codgerente,
            "prestacao": row.prestacao,
            "duplicata": row.duplicata,
            "codcob": row.codcob,
            "tipo": row.tipo,
            "codcoborig": row.codcoborig,
            "codfilial": row.codfilial,
            "status": row.status,
            "valor": row.valor,
            "vpago": row.vpago,
            "valordesc": row.valordesc,
            "valororig": row.valororig,
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
                f"{supabase_url}/rest/v1/{TABLE_NAME}"
                "?on_conflict=dtvenc,numped,codcli,codusur,prestacao,duplicata"
            ),
            headers=headers,
            data=json.dumps(chunk),
            timeout=300,
        )
        if not response.ok:
            raise RuntimeError(
                f"Supabase delinquency upsert failed on batch {start}: "
                f"{response.status_code} {response.text}"
            )

    return len(payload)


def main() -> None:
    rows = fetch_oracle_rows()
    purged_count = purge_supabase_rows()
    upserted_count = upsert_supabase_rows(rows)
    total_valor = sum(row.valor for row in rows)
    total_orders = len({row.numped for row in rows if row.numped})
    total_clients = len({row.codcli for row in rows if row.codcli})
    print(
        json.dumps(
            {
                "rows": len(rows),
                "purged": purged_count,
                "upserted": upserted_count,
                "total_valor": round(total_valor, 2),
                "total_orders": total_orders,
                "total_clients": total_clients,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
