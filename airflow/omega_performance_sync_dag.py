from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator


APP_ROOT = os.getenv(
    "OMEGA_APP_ROOT",
    "/mnt/c/Users/POWERBI/OneDrive - omegadistribuidora.com.br/Projetos/William/app",
)
ENV_FILE = os.getenv("OMEGA_APP_ENV_FILE", f"{APP_ROOT}/.env")
PYTHON_BIN = os.getenv("OMEGA_APP_PYTHON", "python3")
PERFORMANCE_SCHEDULE = os.getenv("OMEGA_PERFORMANCE_SCHEDULE", "20 7 * * *")


def _build_shell_prefix() -> str:
    parts = [
        "set -euo pipefail",
        f"cd '{APP_ROOT}'",
        "export PYTHONUNBUFFERED=1",
    ]
    if ENV_FILE:
        parts.append(
            f"if [ -f '{ENV_FILE}' ]; then set -a; . '{ENV_FILE}'; set +a; fi"
        )
    return "; ".join(parts)


COMMON_PREFIX = _build_shell_prefix()


default_args = {
    "owner": "omega",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=10),
}


with DAG(
    dag_id="omega_performance_sync",
    description=(
        "Atualiza metas de performance e SKU mensal para vendedor, supervisor "
        "e coordenador."
    ),
    default_args=default_args,
    start_date=datetime(2026, 5, 18),
    schedule=PERFORMANCE_SCHEDULE,
    catchup=False,
    max_active_runs=1,
    tags=["omega", "oracle", "supabase", "performance"],
) as dag:
    sync_performance_targets = BashOperator(
        task_id="sync_performance_targets",
        bash_command=(
            f"{COMMON_PREFIX}; "
            f"{PYTHON_BIN} tool/performance_targets_sync.py"
        ),
    )

    sync_performance_sku = BashOperator(
        task_id="sync_performance_sku",
        bash_command=(
            f"{COMMON_PREFIX}; "
            f"{PYTHON_BIN} tool/oracle_performance_sku_sync.py"
        ),
    )

    sync_performance_targets >> sync_performance_sku
