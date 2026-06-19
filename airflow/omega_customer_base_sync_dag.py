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
CUSTOMER_BASE_SCHEDULE = os.getenv("OMEGA_CUSTOMER_BASE_SCHEDULE", "30 7-17/2 * * *")


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
    dag_id="omega_customer_base_sync",
    description=(
        "Atualiza base de clientes por vendedor para o modulo Clientes sem compra."
    ),
    default_args=default_args,
    start_date=datetime(2026, 6, 19),
    schedule=CUSTOMER_BASE_SCHEDULE,
    catchup=False,
    max_active_runs=1,
    tags=["omega", "oracle", "supabase", "clientes"],
) as dag:
    sync_customer_base = BashOperator(
        task_id="sync_customer_base",
        bash_command=(
            f"{COMMON_PREFIX}; "
            f"{PYTHON_BIN} tool/oracle_customer_base_sync.py"
        ),
    )

    sync_sales_order_items = BashOperator(
        task_id="sync_sales_order_items",
        bash_command=(
            f"{COMMON_PREFIX}; "
            f"{PYTHON_BIN} tool/oracle_sales_order_items_sync.py"
        ),
    )

    sync_customer_base >> sync_sales_order_items
