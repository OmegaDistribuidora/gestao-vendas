from __future__ import annotations

import os
import subprocess
from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.exceptions import AirflowException
from airflow.providers.standard.operators.python import PythonOperator


POWERSHELL = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
SCRIPT = r"C:\Users\POWERBI\Desktop\gold_performance\executar_carga_performance.ps1"
PYTHON_BIN = os.getenv(
    "OMEGA_APP_PYTHON",
    "/mnt/c/Users/POWERBI/scoop/apps/python/current/python.exe",
)
APP_WIN = os.getenv("OMEGA_APP_ROOT", r"C:\Repos\gestao-vendas")
APP_LINUX = "/mnt/c/Repos/gestao-vendas"
ORACLE_SOURCE_SCRIPT = rf"{APP_WIN}\tool\gold_performance_oracle_source_sync.py"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")


def _run_oracle_source(*extra_args: str) -> None:
    resultado = subprocess.run(
        [
            PYTHON_BIN,
            ORACLE_SOURCE_SCRIPT,
            "--schema",
            "gold_src",
            *extra_args,
        ],
        cwd=APP_LINUX,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if resultado.stdout.strip():
        print(resultado.stdout.strip())
    if resultado.stderr.strip():
        print(resultado.stderr.strip())
    if resultado.returncode != 0:
        raise AirflowException(
            "Falha na atualizacao Oracle da fonte operacional da Gold "
            f"(codigo {resultado.returncode})."
        )


def atualizar_fontes_oracle() -> None:
    # Default script window is yesterday through today. It captures late changes
    # without repeatedly reading the historical BI horizon from Oracle.
    _run_oracle_source()


def reconciliar_fontes_oracle() -> None:
    _run_oracle_source("--backfill")


def atualizar_performance_gold() -> None:
    resultado = subprocess.run(
        [
            POWERSHELL,
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            SCRIPT,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )

    if resultado.stdout.strip():
        print(resultado.stdout.strip())
    if resultado.stderr.strip():
        print(resultado.stderr.strip())

    if resultado.returncode != 0:
        raise AirflowException(
            f"Falha na carga da gold.performance (código {resultado.returncode})."
        )


with DAG(
    dag_id="gold_performance",
    description=(
        "Recalcula a performance do mês atual e do mês anterior no banco Omega."
    ),
    default_args={
        "owner": "powerbi",
        "depends_on_past": False,
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
    },
    start_date=pendulum.datetime(2026, 6, 1, 6, 0, tz=LOCAL_TZ),
    schedule="*/2 6-23 * * *",
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(minutes=10),
    is_paused_upon_creation=False,
    tags=["omega", "postgres", "gold", "performance", "power-bi"],
) as dag:
    atualizar_fontes = PythonOperator(
        task_id="atualizar_fontes_oracle",
        python_callable=atualizar_fontes_oracle,
        execution_timeout=timedelta(minutes=3),
    )

    atualizar = PythonOperator(
        task_id="atualizar_mes_atual_e_anterior",
        python_callable=atualizar_performance_gold,
        execution_timeout=timedelta(minutes=5),
    )

    atualizar_fontes >> atualizar


with DAG(
    dag_id="gold_performance_oracle_reconcile",
    description="Reconcilia desde junho/2026 as fontes Oracle exclusivas da Gold.",
    default_args={
        "owner": "powerbi",
        "depends_on_past": False,
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
    },
    start_date=pendulum.datetime(2026, 8, 11, 5, 15, tz=LOCAL_TZ),
    schedule="15 5 * * *",
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(minutes=10),
    is_paused_upon_creation=False,
    tags=["omega", "oracle", "gold", "performance", "reconcile"],
) as reconcile_dag:
    reconciliar = PythonOperator(
        task_id="reconciliar_fontes_desde_junho_2026",
        python_callable=reconciliar_fontes_oracle,
        execution_timeout=timedelta(minutes=5),
    )
