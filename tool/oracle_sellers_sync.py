from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import oracledb
import requests


ORACLE_QUERY = """
SELECT
    pcsuperv.CODGERENTE,
    pcgerente.NOMEGERENTE AS Coordenador,
    pcsuperv.CODSUPERVISOR,
    pcsuperv.NOME AS Supervisor,
    pcusuari.CODUSUR AS CodRca,
    pcusuari.NOME AS Rca,
    pcusuari.BLOQUEIO,
    REPLACE(REPLACE(pcusuari.CPF, '.', ''), '-', '') AS CPF
FROM pcusuari
JOIN pcsuperv
    ON pcusuari.CODSUPERVISOR = pcsuperv.CODSUPERVISOR
JOIN pcgerente
    ON pcsuperv.CODGERENTE = pcgerente.CODGERENTE
WHERE pcsuperv.POSICAO = 'A'
  AND pcusuari.DTTERMINO IS NULL
ORDER BY pcsuperv.CODGERENTE, pcsuperv.NOME, pcusuari.CODUSUR
"""


@dataclass(frozen=True)
class SellerRow:
    coordinator_code: str
    coordinator_name: str
    supervisor_code: str
    supervisor_name: str
    seller_code: str
    seller_name: str
    cpf: str


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def _sanitize_digits(value: str) -> str:
    return "".join(char for char in value if char.isdigit())


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


def fetch_oracle_rows() -> list[SellerRow]:
    oracle_user = _require_env("ORACLE_USER")
    oracle_password = _require_env("ORACLE_PASSWORD")
    oracle_dsn = _require_env("ORACLE_DSN")

    _init_oracle_client_if_available()
    connection = oracledb.connect(
        user=oracle_user,
        password=oracle_password,
        dsn=oracle_dsn,
    )

    try:
        with connection.cursor() as cursor:
            cursor.execute(ORACLE_QUERY)
            rows: list[SellerRow] = []
            for (
                coordinator_code,
                coordinator_name,
                supervisor_code,
                supervisor_name,
                seller_code,
                seller_name,
                blocked,
                cpf,
            ) in cursor:
                normalized_cpf = _sanitize_digits(str(cpf or ""))
                blocked_flag = str(blocked or "").strip().upper()
                if blocked_flag != "N":
                    continue
                if normalized_cpf in {"", "0", "00000000000"}:
                    continue
                rows.append(
                    SellerRow(
                        coordinator_code=str(coordinator_code or "").strip(),
                        coordinator_name=str(coordinator_name or "").strip(),
                        supervisor_code=str(supervisor_code or "").strip(),
                        supervisor_name=str(supervisor_name or "").strip(),
                        seller_code=str(seller_code or "").strip(),
                        seller_name=str(seller_name or "").strip(),
                        cpf=normalized_cpf,
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
    return supabase_url, response.json()["access_token"]


def sync_sellers(rows: Iterable[SellerRow]) -> dict[str, object]:
    sellers = [
        {
            "code": row.seller_code,
            "displayName": row.seller_name,
            "cpf": row.cpf,
            "supervisorCode": row.supervisor_code,
            "supervisorName": row.supervisor_name,
            "coordinatorCode": row.coordinator_code,
            "coordinatorName": row.coordinator_name,
        }
        for row in rows
        if row.seller_code and row.seller_name and len(row.cpf) >= 3
    ]

    supabase_url, access_token = authenticate_supabase()
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.post(
        f"{supabase_url}/functions/v1/admin-users",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
        json={
            "action": "sync_sellers",
            "deactivateMissing": True,
            "sellers": sellers,
        },
        timeout=240,
    )
    response.raise_for_status()
    return response.json()


def main() -> None:
    rows = fetch_oracle_rows()
    result = sync_sellers(rows)
    print(
        json.dumps(
            {
                "oracle_rows": len(rows),
                **result,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
