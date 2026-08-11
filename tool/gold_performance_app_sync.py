from __future__ import annotations

import json
import os
import subprocess
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path

import psycopg

from performance_sync_common import (
    get_current_month_start,
    get_previous_month_start,
)
from oracle_financial_sync_common import require_env
from supabase_sync_common import (
    authenticate_supabase,
    begin_sync_run,
    dispatch_push_notifications,
    insert_rows,
    invoke_rpc,
    mark_sync_run_failed,
    set_sync_run_rows_staged,
)


TARGET_TABLE = "app_gold_performance"
STAGING_TABLE = "etl_stg_gold_performance"
SYNC_JOB_NAME = "gold_performance_app_sync"
FIRST_GOLD_MONTH = date(2026, 8, 1)

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
    if isinstance(value, datetime):
        normalized = value if value.tzinfo is not None else value.replace(tzinfo=UTC)
        return normalized.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return value


def _sync_window() -> tuple[date, date]:
    current_month = get_current_month_start()
    full_sync = os.getenv("GOLD_PERFORMANCE_FULL_SYNC", "").strip().lower()
    if full_sync in {"1", "true", "yes"}:
        return FIRST_GOLD_MONTH, current_month

    previous_month = get_previous_month_start(current_month)
    return max(previous_month, FIRST_GOLD_MONTH), current_month


def _fetch_rows(start_month: date, end_month: date) -> list[dict[str, object]]:
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
                select *
                from gold.performance
                where competencia_data between %s and %s
                order by competencia_data, perfil_usuario, codigo_usuario,
                         tipo_performance, codigo_fornecedor nulls first
                """,
                (start_month, end_month),
            )
            columns = [description.name for description in cursor.description]
            result: list[dict[str, object]] = []
            for source_row in cursor.fetchall():
                payload = {
                    column: _json_value(value)
                    for column, value in zip(columns, source_row, strict=True)
                }
                result.append(
                    {
                        "id_apuracao": payload["id_apuracao"],
                        "competencia_data": payload["competencia_data"],
                        "codigo_usuario": str(payload["codigo_usuario"]),
                        "perfil_usuario": payload["perfil_usuario"],
                        "tipo_usuario": payload["tipo_usuario"],
                        "codigo_supervisor": payload.get("codigo_supervisor"),
                        "codigo_coordenador": payload.get("codigo_coordenador"),
                        "tipo_performance": payload["tipo_performance"],
                        "codigo_fornecedor": payload.get("codigo_fornecedor"),
                        "fornecedor": payload.get("fornecedor"),
                        "payload": payload,
                        "source_updated_at": payload.get("data_atualizacao"),
                    }
                )
            return result


def main() -> None:
    start_month, end_month = _sync_window()
    rows = _fetch_rows(start_month, end_month)
    if not rows:
        raise RuntimeError(
            "gold.performance returned no rows for "
            f"{start_month.isoformat()} through {end_month.isoformat()}."
        )

    session = authenticate_supabase(require_env)
    scope_type = (
        "manual"
        if os.getenv("GOLD_PERFORMANCE_FULL_SYNC", "").strip().lower()
        in {"1", "true", "yes"}
        else "fast"
    )
    run_id = begin_sync_run(
        session,
        job_name=SYNC_JOB_NAME,
        target_name=TARGET_TABLE,
        scope_type=scope_type,
        window_start=start_month.isoformat(),
        window_end=end_month.isoformat(),
    )
    try:
        staging_rows = [{"run_id": run_id, **row} for row in rows]
        staged = insert_rows(session, STAGING_TABLE, staging_rows)
        set_sync_run_rows_staged(session, run_id, staged)
        apply_result = invoke_rpc(
            session,
            "apply_gold_performance_sync",
            {"p_run_id": run_id},
        )
    except Exception as error:
        try:
            mark_sync_run_failed(session, run_id, str(error))
        except Exception:
            pass
        raise

    notification_evaluation = invoke_rpc(
        session,
        "evaluate_push_notifications_after_gold_sync",
        {"target_reference_date": date.today().isoformat()},
    )
    dispatch_push_notifications(session)

    print(
        json.dumps(
            {
                "source": "gold.performance",
                "target": TARGET_TABLE,
                "start_month": start_month.isoformat(),
                "end_month": end_month.isoformat(),
                "run_id": run_id,
                "staged": staged,
                "apply_result": apply_result,
                "notification_evaluation": notification_evaluation,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
