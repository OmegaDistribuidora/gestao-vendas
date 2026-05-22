from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Callable, Iterable

import requests


DEFAULT_BATCH_SIZE = 1000


@dataclass(frozen=True)
class SupabaseSession:
    url: str
    publishable_key: str
    access_token: str


def authenticate_supabase(require_env: Callable[[str], str]) -> SupabaseSession:
    supabase_url = require_env("SUPABASE_URL")
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")
    admin_email = require_env("SUPABASE_ADMIN_EMAIL")
    admin_password = require_env("SUPABASE_ADMIN_PASSWORD")

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
    return SupabaseSession(
        url=supabase_url,
        publishable_key=publishable_key,
        access_token=response.json()["access_token"],
    )


def build_rest_headers(
    session: SupabaseSession,
    *,
    prefer: str | None = None,
    json_content: bool = False,
) -> dict[str, str]:
    headers = {
        "apikey": session.publishable_key,
        "Authorization": f"Bearer {session.access_token}",
        "User-Agent": "omega-sync/etl-v2",
    }
    if prefer:
        headers["Prefer"] = prefer
    if json_content:
        headers["Content-Type"] = "application/json"
    return headers


def invoke_rpc(
    session: SupabaseSession,
    function_name: str,
    payload: dict[str, object],
    *,
    timeout: int = 300,
) -> object:
    response = requests.post(
        f"{session.url}/rest/v1/rpc/{function_name}",
        headers=build_rest_headers(session, json_content=True),
        data=json.dumps(payload),
        timeout=timeout,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase RPC {function_name} failed: "
            f"{response.status_code} {response.text}"
        )

    if not response.text.strip():
        return None
    return response.json()


def insert_rows(
    session: SupabaseSession,
    table_name: str,
    rows: Iterable[dict[str, object]],
    *,
    batch_size: int = DEFAULT_BATCH_SIZE,
) -> int:
    payload = list(rows)
    if not payload:
        return 0

    headers = build_rest_headers(
        session,
        json_content=True,
        prefer="return=minimal",
    )

    for start in range(0, len(payload), batch_size):
        chunk = payload[start : start + batch_size]
        response = requests.post(
            f"{session.url}/rest/v1/{table_name}",
            headers=headers,
            data=json.dumps(chunk),
            timeout=300,
        )
        if not response.ok:
            raise RuntimeError(
                f"Supabase insert failed for {table_name} on batch {start}: "
                f"{response.status_code} {response.text}"
            )

    return len(payload)


def begin_sync_run(
    session: SupabaseSession,
    *,
    job_name: str,
    target_name: str,
    scope_type: str,
    window_start: str,
    window_end: str,
) -> str:
    response = invoke_rpc(
        session,
        "begin_sync_run",
        {
            "p_job_name": job_name,
            "p_target_name": target_name,
            "p_scope_type": scope_type,
            "p_window_start": window_start,
            "p_window_end": window_end,
        },
    )
    run_id = str(response or "").strip()
    if not run_id:
        raise RuntimeError(
            f"Supabase begin_sync_run returned an invalid run id for {job_name}."
        )
    return run_id


def set_sync_run_rows_staged(
    session: SupabaseSession,
    run_id: str,
    rows_staged: int,
) -> None:
    invoke_rpc(
        session,
        "set_sync_run_rows_staged",
        {
            "p_run_id": run_id,
            "p_rows_staged": rows_staged,
        },
    )


def mark_sync_run_failed(
    session: SupabaseSession,
    run_id: str,
    error_message: str,
) -> None:
    invoke_rpc(
        session,
        "mark_sync_run_failed",
        {
            "p_run_id": run_id,
            "p_error_message": error_message[:4000],
        },
    )
