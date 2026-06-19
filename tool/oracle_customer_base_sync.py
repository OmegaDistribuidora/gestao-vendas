from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Iterable

import oracledb

from oracle_financial_sync_common import require_env
from supabase_sync_common import (
    SupabaseSession,
    authenticate_supabase,
    begin_sync_run,
    insert_rows,
    invoke_rpc,
    mark_sync_run_failed,
    set_sync_run_rows_staged,
)


CUSTOMER_BASE_QUERY = """
SELECT
    pc.codcli,
    pc.codusur1 AS codusur,
    CASE
        WHEN pc.bloqueio = 'N' THEN 'Desbloqueado'
        ELSE 'Bloqueado'
    END AS status_cliente
FROM pcclient pc
WHERE pc.codusur1 IS NOT NULL

UNION ALL

SELECT
    pc.codcli,
    pc.codusur2 AS codusur,
    CASE
        WHEN pc.bloqueio = 'N' THEN 'Desbloqueado'
        ELSE 'Bloqueado'
    END AS status_cliente
FROM pcclient pc
WHERE pc.codusur2 IS NOT NULL
"""

CUSTOMERS_QUERY = """
SELECT
    pc.codcli,
    INITCAP(pc.cliente) AS cliente,
    pc.codcli || ' - ' || INITCAP(pc.cliente) AS cod_cliente,
    INITCAP(pc.fantasia) AS fantasia,
    pc.codcli || ' - ' || INITCAP(pc.fantasia) AS cod_fantasia,
    INITCAP(pc.enderent) || ', ' || pc.numeroent AS end_compl,
    INITCAP(pc.bairroent) AS bairro,
    INITCAP(pc.municent) AS cidade,
    SUBSTR(REGEXP_REPLACE(pc.cepent, '[^0-9]'), 1, 2) || '.' ||
    SUBSTR(REGEXP_REPLACE(pc.cepent, '[^0-9]'), 3, 3) || '-' ||
    SUBSTR(REGEXP_REPLACE(pc.cepent, '[^0-9]'), 6, 3) AS cep,
    pc.codatv1 AS codatv,
    pc.codcidade,
    NVL(pc.codrede, 31) AS codrede,
    pc.codpraca,
    pc.estent AS uf,
    pc.limcred,
    pc.codusur1,
    pc.codusur2,
    pc.codmunicipio AS codibge,
    CASE
        WHEN pc.bloqueio = 'N' THEN 'Desbloqueado'
        ELSE 'Bloqueado'
    END AS status,
    INITCAP(pc.obs) AS motivo_bloq,
    pc.dtultcomp,
    pc.dtbloq,
    REGEXP_REPLACE(pc.cgcent, '[^0-9]') AS cnpj
FROM pcclient pc
"""


@dataclass(frozen=True)
class CustomerBaseRow:
    codcli: str
    codusur: str
    status_cliente: str
    imported_at: str


@dataclass(frozen=True)
class CustomerRow:
    codcli: str
    cliente: str
    cod_cliente: str
    fantasia: str
    cod_fantasia: str
    end_compl: str
    bairro: str
    cidade: str
    cep: str
    codatv: str
    codcidade: str
    codrede: str
    codpraca: str
    uf: str
    limcred: float
    codusur1: str
    codusur2: str
    codibge: str
    status: str
    motivo_bloq: str
    dtultcomp: str | None
    dtbloq: str | None
    cnpj: str
    imported_at: str


def _normalize_text(value: object | None) -> str:
    return str(value or "").replace("\x00", "").strip()


def _to_float(value: Decimal | float | int | None) -> float:
    if value is None:
        return 0.0
    return float(value)


def _to_date_string(value: object | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    parsed = str(value).strip()
    return parsed or None


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


def fetch_oracle_rows() -> tuple[list[CustomerRow], list[CustomerBaseRow]]:
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
            cursor.execute(CUSTOMERS_QUERY)
            customers = [
                CustomerRow(
                    codcli=_normalize_text(codcli),
                    cliente=_normalize_text(cliente),
                    cod_cliente=_normalize_text(cod_cliente),
                    fantasia=_normalize_text(fantasia),
                    cod_fantasia=_normalize_text(cod_fantasia),
                    end_compl=_normalize_text(end_compl),
                    bairro=_normalize_text(bairro),
                    cidade=_normalize_text(cidade),
                    cep=_normalize_text(cep),
                    codatv=_normalize_text(codatv),
                    codcidade=_normalize_text(codcidade),
                    codrede=_normalize_text(codrede),
                    codpraca=_normalize_text(codpraca),
                    uf=_normalize_text(uf),
                    limcred=_to_float(limcred),
                    codusur1=_normalize_text(codusur1),
                    codusur2=_normalize_text(codusur2),
                    codibge=_normalize_text(codibge),
                    status=_normalize_text(status),
                    motivo_bloq=_normalize_text(motivo_bloq),
                    dtultcomp=_to_date_string(dtultcomp),
                    dtbloq=_to_date_string(dtbloq),
                    cnpj=_normalize_text(cnpj),
                    imported_at=imported_at,
                )
                for (
                    codcli,
                    cliente,
                    cod_cliente,
                    fantasia,
                    cod_fantasia,
                    end_compl,
                    bairro,
                    cidade,
                    cep,
                    codatv,
                    codcidade,
                    codrede,
                    codpraca,
                    uf,
                    limcred,
                    codusur1,
                    codusur2,
                    codibge,
                    status,
                    motivo_bloq,
                    dtultcomp,
                    dtbloq,
                    cnpj,
                ) in cursor
                if _normalize_text(codcli)
            ]

            cursor.execute(CUSTOMER_BASE_QUERY)
            base_rows = [
                CustomerBaseRow(
                    codcli=_normalize_text(codcli),
                    codusur=_normalize_text(codusur),
                    status_cliente=_normalize_text(status_cliente),
                    imported_at=imported_at,
                )
                for codcli, codusur, status_cliente in cursor
                if _normalize_text(codcli) and _normalize_text(codusur)
            ]

            return customers, base_rows
    finally:
        connection.close()


def stage_customer_rows(
    session: SupabaseSession,
    run_id: str,
    rows: Iterable[CustomerRow],
) -> int:
    deduped_rows = {row.codcli: row for row in rows}
    payload = [
        {
            "run_id": run_id,
            "codcli": row.codcli,
            "cliente": row.cliente,
            "cod_cliente": row.cod_cliente,
            "fantasia": row.fantasia,
            "cod_fantasia": row.cod_fantasia,
            "end_compl": row.end_compl,
            "bairro": row.bairro,
            "cidade": row.cidade,
            "cep": row.cep,
            "codatv": row.codatv,
            "codcidade": row.codcidade,
            "codrede": row.codrede,
            "codpraca": row.codpraca,
            "uf": row.uf,
            "limcred": row.limcred,
            "codusur1": row.codusur1,
            "codusur2": row.codusur2,
            "codibge": row.codibge,
            "status": row.status,
            "motivo_bloq": row.motivo_bloq,
            "dtultcomp": row.dtultcomp,
            "dtbloq": row.dtbloq,
            "cnpj": row.cnpj,
            "imported_at": row.imported_at,
        }
        for row in deduped_rows.values()
    ]
    return insert_rows(session, "etl_stg_customers", payload)


def stage_customer_base_rows(
    session: SupabaseSession,
    run_id: str,
    rows: Iterable[CustomerBaseRow],
) -> int:
    deduped_rows = {(row.codcli, row.codusur): row for row in rows}
    payload = [
        {
            "run_id": run_id,
            "codcli": row.codcli,
            "codusur": row.codusur,
            "status_cliente": row.status_cliente,
            "imported_at": row.imported_at,
        }
        for row in deduped_rows.values()
    ]
    return insert_rows(session, "etl_stg_customer_seller_bases", payload)


def apply_customer_base_sync(
    session: SupabaseSession,
    run_id: str,
) -> dict[str, object]:
    response = invoke_rpc(
        session,
        "apply_customer_base_sync",
        {"p_run_id": run_id},
    )
    if not isinstance(response, dict):
        return {}
    return {str(key): value for key, value in response.items()}


def main() -> None:
    customers, base_rows = fetch_oracle_rows()
    session = authenticate_supabase(require_env)
    today = date.today()
    run_id = begin_sync_run(
        session,
        job_name="oracle_customer_base_sync",
        target_name="app_customers",
        scope_type="fast",
        window_start=today.isoformat(),
        window_end=today.isoformat(),
    )

    try:
        staged_customers = stage_customer_rows(session, run_id, customers)
        staged_base_rows = stage_customer_base_rows(session, run_id, base_rows)
        set_sync_run_rows_staged(session, run_id, staged_customers + staged_base_rows)
        apply_result = apply_customer_base_sync(session, run_id)
    except Exception as error:
        mark_sync_run_failed(session, run_id, str(error))
        raise

    print(
        json.dumps(
            {
                "scope_type": "fast",
                "customers": len(customers),
                "base_rows": len(base_rows),
                "staged_customers": staged_customers,
                "staged_base_rows": staged_base_rows,
                **apply_result,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
