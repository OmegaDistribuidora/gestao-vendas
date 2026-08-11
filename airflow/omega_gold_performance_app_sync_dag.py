from __future__ import annotations

import os
import subprocess
from datetime import timedelta
from pathlib import Path

import pendulum
from airflow import DAG
from airflow.exceptions import AirflowException
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.sensors.external_task import ExternalTaskSensor


APP_WIN = os.getenv(
    "OMEGA_APP_ROOT",
    r"C:\Repos\gestao-vendas",
)
APP_LINUX = "/mnt/c/Repos/gestao-vendas"
ENV_FILE = os.getenv(
    "OMEGA_APP_ENV_FILE",
    "/mnt/c/Users/POWERBI/OneDrive - omegadistribuidora.com.br/Projetos/William/app/.env",
)
PYTHON_BIN = os.getenv(
    "OMEGA_APP_PYTHON",
    "/mnt/c/Users/POWERBI/scoop/apps/python/current/python.exe",
)
SCHEDULE = os.getenv("OMEGA_GOLD_PERFORMANCE_APP_SCHEDULE", "*/2 6-23 * * *")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")


def _decode_output(content: bytes) -> str:
    for encoding in ("utf-8", "cp1252", "latin-1"):
        try:
            return content.decode(encoding)
        except UnicodeDecodeError:
            continue
    return content.decode("utf-8", errors="replace")


def _load_dotenv(env: dict[str, str]) -> dict[str, str]:
    path = Path(ENV_FILE)
    if not path.exists():
        raise AirflowException(f"Arquivo de ambiente nao encontrado: {ENV_FILE}")

    merged = env.copy()
    dotenv_keys: list[str] = []
    for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        merged[key] = value.strip().strip('"').strip("'")
        dotenv_keys.append(key)
    merged["PYTHONUNBUFFERED"] = "1"

    wslenv_entries = [item for item in merged.get("WSLENV", "").split(":") if item]
    forwarded_keys = {item.split("/", 1)[0] for item in wslenv_entries}
    for key in [*dotenv_keys, "PYTHONUNBUFFERED"]:
        if key not in forwarded_keys:
            wslenv_entries.append(f"{key}/w")
    merged["WSLENV"] = ":".join(wslenv_entries)
    return merged


def _run_sync() -> None:
    script_win = str(Path(APP_WIN) / "tool" / "gold_performance_app_sync.py")
    result = subprocess.run(
        [PYTHON_BIN, script_win],
        cwd=APP_LINUX,
        env=_load_dotenv(os.environ.copy()),
        capture_output=True,
        check=False,
    )
    stdout = _decode_output(result.stdout)
    stderr = _decode_output(result.stderr)
    if stdout.strip():
        print(stdout.strip())
    if stderr.strip():
        print(stderr.strip())
    if result.returncode != 0:
        raise AirflowException(
            "Falha ao sincronizar gold.performance com o aplicativo "
            f"(exit code {result.returncode})"
        )


with DAG(
    dag_id="omega_gold_performance_app_sync",
    description="Replica gold.performance no Supabase para o aplicativo.",
    default_args={
        "owner": "omega",
        "depends_on_past": False,
        "email_on_failure": False,
        "email_on_retry": False,
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
    },
    start_date=pendulum.datetime(2026, 8, 1, 6, 0, tz=LOCAL_TZ),
    schedule=SCHEDULE,
    catchup=False,
    max_active_runs=1,
    tags=["omega", "postgres", "supabase", "gold", "performance"],
) as dag:
    wait_for_gold_performance = ExternalTaskSensor(
        task_id="wait_for_gold_performance",
        external_dag_id="gold_performance",
        external_task_id="atualizar_mes_atual_e_anterior",
        allowed_states=["success"],
        failed_states=["failed", "upstream_failed"],
        mode="reschedule",
        poke_interval=5,
        timeout=90,
    )

    sync_gold_performance = PythonOperator(
        task_id="sync_gold_performance",
        python_callable=_run_sync,
        execution_timeout=timedelta(minutes=10),
    )

    wait_for_gold_performance >> sync_gold_performance
