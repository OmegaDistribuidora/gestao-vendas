from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Iterable

import oracledb

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
    faturamento: float
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


def authenticate_supabase() -> tuple[str, str]:
    session = authenticate_supabase_session(require_env)
    return session.url, session.access_token


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
) -> list[FinancialRow]:
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
                sync_start_date=datetime.combine(sync_start_date, datetime.min.time()),
            )
            rows: list[FinancialRow] = []
            for (
                numped,
                snapshot_date,
                codcli,
                codusur,
                codsupervisor,
                codgerente,
                codfornec,
                custo,
                faturamento,
                mix,
                volume,
                lucro,
            ) in cursor:
                rows.append(
                    FinancialRow(
                        snapshot_type=snapshot_type,
                        snapshot_date=snapshot_date.strftime("%Y-%m-%d"),
                        numped=normalize_text(numped),
                        codcli=normalize_text(codcli),
                        codusur=normalize_text(codusur),
                        codsupervisor=normalize_text(codsupervisor),
                        codgerente=normalize_text(codgerente),
                        codfornec=normalize_text(codfornec),
                        custo=to_float(custo),
                        faturamento=to_float(faturamento),
                        mix=to_float(mix),
                        volume=to_float(volume),
                        lucro=to_float(lucro),
                        imported_at=imported_at,
                    )
                )
            return rows
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
            "faturamento": row.faturamento,
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
