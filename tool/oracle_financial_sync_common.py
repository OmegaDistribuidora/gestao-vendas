from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Iterable

import oracledb

try:
    import psycopg
except ImportError:  # The Airflow Windows venv still uses psycopg2.
    import psycopg2 as psycopg

from supabase_sync_common import (
    SupabaseSession,
    authenticate_supabase as authenticate_supabase_session,
    begin_sync_run,
    insert_rows,
    invoke_rpc,
)


INITIAL_SYNC_START_DATE = date(2026, 1, 1)
DEFAULT_FAST_LOOKBACK_DAYS = 1
DEFAULT_RECONCILIATION_LOOKBACK_DAYS = 30
BATCH_SIZE = 1000
DOTENV_PATH = Path(__file__).with_name(".env")
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


@dataclass(frozen=True)
class FinancialRow:
    snapshot_type: str
    snapshot_date: str
    numped: str
    codcli: str
    codusur: str
    codsupervisor: str
    codgerente: str
    codfornec: str
    original_order_date: str
    supplier_main_code: str
    faturamento: float
    adjusted_billing_amount: float
    volume: float
    custo: float
    lucro: float
    mix: float
    imported_at: str


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def load_local_dotenv() -> None:
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


def normalize_text(value: object | None) -> str:
    return str(value or "").strip()


def to_float(value: Decimal | float | int | None) -> float:
    if value is None:
        return 0.0
    return float(value)


def init_oracle_client_if_available() -> None:
    if os.getenv("ORACLE_THIN_MODE", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }:
        return

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


def _postgres_password() -> str:
    configured = os.getenv("APP_POSTGRES_PASSWORD", "").strip()
    if configured:
        return configured
    if os.name != "nt" or not POSTGRES_CREDENTIAL_FILE.exists():
        raise RuntimeError("APP_POSTGRES_PASSWORD is required on this host.")

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


def fetch_supplier_code_map() -> dict[str, str]:
    """Read the authoritative supplier aliases from the local Omega database."""

    with psycopg.connect(
        host=os.getenv("APP_POSTGRES_HOST", "192.168.1.14"),
        port=int(os.getenv("APP_POSTGRES_PORT", "5432")),
        dbname=os.getenv("APP_POSTGRES_DB", "Omega"),
        user=os.getenv("APP_POSTGRES_USER", "PwBi"),
        password=_postgres_password(),
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                select codfornec_orig, codfornec_princ
                from filial.tauxfornecedor
                where codfornec_orig is not null
                  and codfornec_princ is not null
                order by codfornec_orig
                """
            )
            mapping: dict[str, str] = {}
            for original_code, main_code in cursor:
                original = normalize_text(original_code)
                main = normalize_text(main_code)
                previous = mapping.get(original)
                if previous is not None and previous != main:
                    raise RuntimeError(
                        "Conflicting supplier mapping in filial.tauxfornecedor: "
                        f"{original} -> {previous}/{main}."
                    )
                mapping[original] = main

    if not mapping:
        raise RuntimeError("filial.tauxfornecedor returned no valid mappings.")
    return mapping


def _legacy_supplier_code(original_code: str) -> str:
    """Preserve the old code for consumers that still use the legacy column."""

    if original_code in {"1535", "1968"}:
        return "1968"
    if original_code in {"1443", "967"}:
        return "967"
    if original_code in {"1630", "2445"}:
        return "1630"
    return original_code


def authenticate_supabase() -> tuple[str, str]:
    session = authenticate_supabase_session(require_env)
    return session.url, session.access_token


def get_supabase_api_key() -> str:
    return (
        os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        or require_env("SUPABASE_PUBLISHABLE_KEY")
    )


def get_sync_scope() -> str:
    scope = os.getenv("SYNC_SCOPE", "fast").strip().lower()
    if scope in {"reconcile", "reconciliacao", "reconciliation"}:
        return "reconcile"
    if scope == "manual":
        return "manual"
    return "fast"


def _get_lookback_days(scope_type: str) -> int:
    if scope_type == "reconcile":
        raw_value = os.getenv("RECONCILIATION_LOOKBACK_DAYS", "").strip()
        default_value = DEFAULT_RECONCILIATION_LOOKBACK_DAYS
    else:
        raw_value = os.getenv("FAST_LOOKBACK_DAYS", "").strip()
        default_value = DEFAULT_FAST_LOOKBACK_DAYS

    if not raw_value:
        return default_value

    try:
        return max(0, int(raw_value))
    except ValueError:
        return default_value


def get_sync_window() -> tuple[str, date, date]:
    override_start = os.getenv("SYNC_START_DATE", "").strip()
    override_end = os.getenv("SYNC_END_DATE", "").strip()
    if override_start and override_end:
        start_date = date.fromisoformat(override_start)
        end_date = date.fromisoformat(override_end)
        if start_date > end_date:
            raise RuntimeError("SYNC_START_DATE cannot be greater than SYNC_END_DATE.")
        return "manual", start_date, end_date

    scope_type = get_sync_scope()
    end_date = date.today()
    lookback_days = _get_lookback_days(scope_type)
    start_date = end_date - timedelta(days=lookback_days)
    if start_date < INITIAL_SYNC_START_DATE:
        start_date = INITIAL_SYNC_START_DATE
    return scope_type, start_date, end_date


def fetch_oracle_rows(
    snapshot_type: str,
    query: str,
    sync_start_date: date,
    sync_end_date: date | None = None,
    *,
    storage_supplier_code: str = "legacy",
) -> list[FinancialRow]:
    if storage_supplier_code not in {"legacy", "main"}:
        raise ValueError("storage_supplier_code must be 'legacy' or 'main'.")

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
    end_exclusive = (sync_end_date or date.today()) + timedelta(days=1)
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                query,
                sync_start_date=datetime.combine(sync_start_date, datetime.min.time()),
                sync_end_exclusive=datetime.combine(
                    end_exclusive,
                    datetime.min.time(),
                ),
            )
            supplier_mapping = fetch_supplier_code_map()
            aggregated: dict[tuple[str, str, str, str, str, str], FinancialRow] = {}
            supplier_by_storage_key: dict[
                tuple[str, str, str, str, str], str
            ] = {}
            for (
                numped,
                snapshot_date,
                codcli,
                codusur,
                codsupervisor,
                codgerente,
                supplier_original_code,
                original_order_date,
                custo,
                faturamento,
                adjusted_billing_amount,
                mix,
                volume,
                lucro,
            ) in cursor:
                original_supplier = normalize_text(supplier_original_code)
                main_supplier = supplier_mapping.get(
                    original_supplier,
                    original_supplier,
                )
                stored_supplier = (
                    main_supplier
                    if storage_supplier_code == "main"
                    else _legacy_supplier_code(original_supplier)
                )
                row = FinancialRow(
                    snapshot_type=snapshot_type,
                    snapshot_date=snapshot_date.strftime("%Y-%m-%d"),
                    numped=normalize_text(numped),
                    codcli=normalize_text(codcli),
                    codusur=normalize_text(codusur),
                    codsupervisor=normalize_text(codsupervisor),
                    codgerente=normalize_text(codgerente),
                    codfornec=stored_supplier,
                    original_order_date=original_order_date.strftime("%Y-%m-%d"),
                    supplier_main_code=main_supplier,
                    custo=to_float(custo),
                    faturamento=to_float(faturamento),
                    adjusted_billing_amount=to_float(adjusted_billing_amount),
                    mix=to_float(mix),
                    volume=to_float(volume),
                    lucro=to_float(lucro),
                    imported_at=imported_at,
                )
                storage_key = (
                    row.snapshot_date,
                    row.numped,
                    row.codcli,
                    row.codusur,
                    row.codfornec,
                )
                previous_main = supplier_by_storage_key.get(storage_key)
                if previous_main is not None and previous_main != main_supplier:
                    raise RuntimeError(
                        "Supplier mapping conflicts with the legacy financial key "
                        f"for order {row.numped}: {previous_main}/{main_supplier}."
                    )
                supplier_by_storage_key[storage_key] = main_supplier
                key = (
                    row.snapshot_date,
                    row.numped,
                    row.codcli,
                    row.codusur,
                    row.codfornec,
                    row.supplier_main_code,
                )
                existing = aggregated.get(key)
                if existing is None:
                    aggregated[key] = row
                    continue

                if (
                    existing.codsupervisor != row.codsupervisor
                    or existing.codgerente != row.codgerente
                    or existing.original_order_date != row.original_order_date
                ):
                    raise RuntimeError(
                        "Inconsistent financial grouping for order "
                        f"{row.numped} and supplier {row.codfornec}."
                    )
                aggregated[key] = FinancialRow(
                    snapshot_type=row.snapshot_type,
                    snapshot_date=row.snapshot_date,
                    numped=row.numped,
                    codcli=row.codcli,
                    codusur=row.codusur,
                    codsupervisor=row.codsupervisor,
                    codgerente=row.codgerente,
                    codfornec=row.codfornec,
                    original_order_date=row.original_order_date,
                    supplier_main_code=row.supplier_main_code,
                    custo=existing.custo + row.custo,
                    faturamento=existing.faturamento + row.faturamento,
                    adjusted_billing_amount=(
                        existing.adjusted_billing_amount
                        + row.adjusted_billing_amount
                    ),
                    mix=existing.mix + row.mix,
                    volume=existing.volume + row.volume,
                    lucro=existing.lucro + row.lucro,
                    imported_at=row.imported_at,
                )
            return list(aggregated.values())
    finally:
        connection.close()


def create_financial_sync_run(
    session: SupabaseSession,
    *,
    job_name: str,
    scope_type: str,
    window_start: date,
    window_end: date,
) -> str:
    return begin_sync_run(
        session,
        job_name=job_name,
        target_name="app_financial_snapshots",
        scope_type=scope_type,
        window_start=window_start.isoformat(),
        window_end=window_end.isoformat(),
    )


def stage_financial_rows(
    session: SupabaseSession,
    run_id: str,
    rows: Iterable[FinancialRow],
) -> int:
    deduped_rows: dict[tuple[str, str, str, str, str, str], FinancialRow] = {}
    for row in rows:
        deduped_rows[
            (
                row.snapshot_type,
                row.snapshot_date,
                row.numped,
                row.codcli,
                row.codusur,
                row.codfornec,
            )
        ] = row

    payload = [
        {
            "run_id": run_id,
            "snapshot_type": row.snapshot_type,
            "snapshot_date": row.snapshot_date,
            "numped": row.numped,
            "codcli": row.codcli,
            "codusur": row.codusur,
            "codsupervisor": row.codsupervisor,
            "codgerente": row.codgerente,
            "codfornec": row.codfornec,
            "original_order_date": row.original_order_date,
            "supplier_main_code": row.supplier_main_code,
            "faturamento": row.faturamento,
            "adjusted_billing_amount": row.adjusted_billing_amount,
            "volume": row.volume,
            "custo": row.custo,
            "lucro": row.lucro,
            "mix": row.mix,
            "imported_at": row.imported_at,
        }
        for row in deduped_rows.values()
    ]
    return insert_rows(session, "etl_stg_financial_snapshots", payload)


def apply_financial_sync(session: SupabaseSession, run_id: str) -> dict[str, object]:
    response = invoke_rpc(
        session,
        "apply_financial_sync",
        {"p_run_id": run_id},
    )
    if not isinstance(response, dict):
        return {}
    return {str(key): value for key, value in response.items()}


load_local_dotenv()
