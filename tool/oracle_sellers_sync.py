from __future__ import annotations

import json
import os
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import oracledb
import requests


DOTENV_PATH = Path(__file__).with_name(".env")

# Some CPFs currently exist in Oracle under more than one seller code.
# The Supabase admin sync expects a single stable account per CPF, so we keep
# the seller code that already updates successfully for these known collisions.
PREFERRED_SELLER_CODE_BY_CPF = {
    "41647599334": "1018",
    "64619583391": "595",
    "16379748334": "1264",
    "00533818311": "1901",
    "01665564326": "712",
    "30201829304": "582",
}

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


def _load_local_dotenv() -> None:
    if not DOTENV_PATH.exists():
        return

    for raw_line in DOTENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


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


def _build_supervisors(rows: Iterable[SellerRow]) -> list[dict[str, str]]:
    supervisors: dict[str, dict[str, str]] = {}
    for row in rows:
        if not row.supervisor_code or not row.supervisor_name:
            continue
        supervisors[row.supervisor_code] = {
            "code": row.supervisor_code,
            "displayName": row.supervisor_name,
        }
    return list(supervisors.values())


def _build_coordinators(rows: Iterable[SellerRow]) -> list[dict[str, str]]:
    coordinators: dict[str, dict[str, str]] = {}
    for row in rows:
        if not row.coordinator_code or not row.coordinator_name:
            continue
        coordinators[row.coordinator_code] = {
            "code": row.coordinator_code,
            "displayName": row.coordinator_name,
        }
    return list(coordinators.values())


def _resolve_duplicate_cpfs(rows: Iterable[SellerRow]) -> tuple[list[SellerRow], int]:
    grouped_rows: dict[str, list[SellerRow]] = defaultdict(list)
    ordered_rows = list(rows)
    for row in ordered_rows:
        grouped_rows[row.cpf].append(row)

    resolved_rows: list[SellerRow] = []
    duplicates_skipped = 0

    for row in ordered_rows:
        group = grouped_rows[row.cpf]
        if not group:
            continue
        if len(group) == 1:
            resolved_rows.append(row)
            grouped_rows[row.cpf] = []
            continue

        preferred_code = PREFERRED_SELLER_CODE_BY_CPF.get(row.cpf, "").strip()
        chosen_row = next(
            (candidate for candidate in group if candidate.seller_code == preferred_code),
            group[0],
        )
        resolved_rows.append(chosen_row)
        duplicates_skipped += len(group) - 1
        grouped_rows[row.cpf] = []

    return resolved_rows, duplicates_skipped


def sync_sellers(rows: Iterable[SellerRow]) -> dict[str, object]:
    rows, duplicates_skipped = _resolve_duplicate_cpfs(rows)
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
    supervisors = _build_supervisors(rows)
    coordinators = _build_coordinators(rows)

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
            "sellers": sellers,
            "supervisors": supervisors,
            "coordinators": coordinators,
        },
        timeout=240,
    )
    response.raise_for_status()
    result = response.json()
    result["duplicatesSkipped"] = duplicates_skipped
    return result


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
    _load_local_dotenv()
    main()
