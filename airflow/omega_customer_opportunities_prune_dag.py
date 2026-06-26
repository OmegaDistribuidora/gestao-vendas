from __future__ import annotations

import os
import subprocess
from datetime import timedelta
from pathlib import Path

import pendulum
from airflow import DAG
from airflow.exceptions import AirflowException
from airflow.providers.standard.operators.python import PythonOperator


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
OPPORTUNITIES_PRUNE_SCHEDULE = os.getenv(
    "OMEGA_CUSTOMER_OPPORTUNITIES_PRUNE_SCHEDULE",
    "15 7-17/3 * * *",
)


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


def _run_script(script_name: str) -> None:
    script_win = str(Path(APP_WIN) / "tool" / script_name)
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
            f"Falha ao executar {script_name} (exit code {result.returncode})"
        )


default_args = {
    "owner": "omega",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=10),
}


with DAG(
    dag_id="omega_customer_opportunities_prune",
    description="Arquiva e remove oportunidades que ja foram cadastradas no WinThor.",
    default_args=default_args,
    start_date=pendulum.datetime(2026, 6, 26, tz="America/Sao_Paulo"),
    schedule=OPPORTUNITIES_PRUNE_SCHEDULE,
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(minutes=20),
    is_paused_upon_creation=False,
    tags=["omega", "oracle", "supabase", "oportunidades"],
) as dag:
    prune_registered_customer_opportunities = PythonOperator(
        task_id="prune_registered_customer_opportunities",
        python_callable=_run_script,
        op_kwargs={"script_name": "customer_opportunities_prune.py"},
    )
