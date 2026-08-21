from __future__ import annotations

import hashlib
import json
import os
import subprocess
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import psycopg

from oracle_financial_sync_common import require_env
from supabase_sync_common import authenticate_supabase, invoke_rpc


SOURCE_TABLE = "filial.tauxcompromisso"
TARGET_NAME = "app_commitments"

POSTGRES_HOST = os.getenv("APP_POSTGRES_HOST", "192.168.1.14")
POSTGRES_PORT = int(os.getenv("APP_POSTGRES_PORT", "5432"))
POSTGRES_DB = os.getenv("APP_POSTGRES_DB", "Omega")
POSTGRES_USER = os.getenv("APP_POSTGRES_USER", "PwBi")
POSTGRES_PASSWORD = os.getenv("APP_POSTGRES_PASSWORD", "").strip()
POSTGRES_CREDENTIAL_FILE = Path(
    os.getenv(
        "APP_POSTGRES_CREDENTIAL_FILE",
        r"C:\Users\POWERBI\Desktop\Bckup\pg_password.txt",
    )
)
POWERSHELL_EXE = os.getenv(
    "APP_POWERSHELL_EXE",
    r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
)
STATE_FILE = Path(
    os.getenv(
        "APP_COMMITMENTS_STATE_FILE",
        r"C:\Users\POWERBI\OneDrive - omegadistribuidora.com.br"
        r"\Projetos\William\app\.state\commitments_sync.sha256",
    )
)


def _postgres_password() -> str:
    if POSTGRES_PASSWORD:
        return POSTGRES_PASSWORD
    if os.name != "nt" or not POSTGRES_CREDENTIAL_FILE.exists():
        raise RuntimeError("Environment variable APP_POSTGRES_PASSWORD is required.")

    credential_path = str(POSTGRES_CREDENTIAL_FILE).replace("'", "''")
    command = (
        f"$credential = Get-Content -LiteralPath '{credential_path}' | "
        "Select-Object -First 1; "
        "$secure = ConvertTo-SecureString -String $credential; "
        "$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); "
        "try { "
        "$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($pointer); "
        "[Console]::Out.Write($plain) "
        "} finally { "
        "[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) "
        "}"
    )
    result = subprocess.run(
        [
            POWERSHELL_EXE,
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            command,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    password = result.stdout.strip()
    if result.returncode != 0 or not password:
        raise RuntimeError("Unable to read the encrypted PostgreSQL credential.")
    return password


def _json_value(value: object) -> object:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def _fetch_rows() -> list[dict[str, object]]:
    with psycopg.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=_postgres_password(),
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                select distinct on (
                  lower(btrim(tipo)), codigo, data_inicio, data_fim
                )
                  lower(btrim(tipo)) as tipo,
                  codigo,
                  meta_financeira,
                  meta_positivacao,
                  data_inicio,
                  data_fim,
                  data_insercao
                from filial.tauxcompromisso
                where lower(btrim(tipo)) in ('supervisor', 'coordenador')
                order by
                  lower(btrim(tipo)), codigo, data_inicio, data_fim,
                  data_insercao desc
                """
            )
            columns = [description.name for description in cursor.description]
            return [
                {
                    column: _json_value(value)
                    for column, value in zip(columns, row, strict=True)
                }
                for row in cursor.fetchall()
            ]


def _canonical_payload(rows: list[dict[str, object]]) -> str:
    return json.dumps(
        rows,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _source_checksum(canonical_payload: str) -> str:
    return hashlib.sha256(canonical_payload.encode("utf-8")).hexdigest()


def _stored_checksum() -> str | None:
    if not STATE_FILE.exists():
        return None
    value = STATE_FILE.read_text(encoding="utf-8").strip()
    return value or None


def _save_checksum(checksum: str) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary_file = STATE_FILE.with_suffix(f"{STATE_FILE.suffix}.tmp")
    temporary_file.write_text(f"{checksum}\n", encoding="utf-8")
    temporary_file.replace(STATE_FILE)


def main() -> None:
    rows = _fetch_rows()
    canonical_payload = _canonical_payload(rows)
    checksum = _source_checksum(canonical_payload)
    previous_checksum = _stored_checksum()

    if checksum == previous_checksum:
        print(
            json.dumps(
                {
                    "source": SOURCE_TABLE,
                    "target": TARGET_NAME,
                    "status": "skipped",
                    "reason": "source_unchanged",
                    "rows": len(rows),
                    "source_checksum": checksum,
                    "supabase_connection": False,
                },
                ensure_ascii=False,
            )
        )
        return

    session = authenticate_supabase(require_env)
    result = invoke_rpc(
        session,
        "apply_commitments_sync",
        {
            "p_rows": rows,
            "p_source_checksum": checksum,
        },
    )
    _save_checksum(checksum)

    print(
        json.dumps(
            {
                "source": SOURCE_TABLE,
                "target": TARGET_NAME,
                "status": "applied",
                "rows": len(rows),
                "source_checksum": checksum,
                "result": result,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
