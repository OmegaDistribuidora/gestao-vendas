from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from pathlib import Path

import oracledb
import requests


ORACLE_QUERY = """
SELECT DISTINCT
    CASE
        WHEN pcfornec.codfornec IN (1443, 967) THEN 967
        WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
        WHEN pcfornec.codfornec IN (2445, 1630) THEN 1630
        ELSE pcfornec.codfornec
    END AS codfornec,
    CASE
        WHEN pcfornec.codfornec = 117 THEN 'Bombril'
        WHEN pcfornec.codfornec IN (1443, 967) THEN 'Maratá'
        WHEN pcfornec.codfornec = 1481 THEN 'Realeza'
        WHEN pcfornec.codfornec IN (1535, 1968) THEN 'JDE'
        WHEN pcfornec.codfornec IN (2445, 1630) THEN 'Panasonic'
        WHEN pcfornec.codfornec = 3609 THEN 'Mili'
        WHEN pcfornec.codfornec = 3930 THEN 'Q-Odor'
        WHEN pcfornec.codfornec = 4698 THEN 'Assim'
        WHEN pcfornec.codfornec = 4750 THEN 'Mat Inset'
        WHEN pcfornec.codfornec = 4701 THEN 'Albany'
        WHEN pcfornec.codfornec = 5348 THEN 'Balducco'
        WHEN pcfornec.codfornec = 5537 THEN 'CCM'
        WHEN pcfornec.codfornec = 5569 THEN 'Gallo'
        WHEN pcfornec.codfornec = 6154 THEN 'Stella D''Oro'
        WHEN pcfornec.codfornec = 6212 THEN 'Bom Princípio'
        ELSE INITCAP(pcfornec.fornecedor)
    END AS fornecedor
FROM pcfornec
ORDER BY codfornec
"""


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def _init_oracle_client_if_available() -> None:
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


def _authenticate_supabase() -> tuple[str, str]:
    supabase_url = _require_env("SUPABASE_URL")
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")
    admin_email = _require_env("SUPABASE_ADMIN_EMAIL")
    admin_password = _require_env("SUPABASE_ADMIN_PASSWORD")

    response = requests.post(
        f"{supabase_url}/auth/v1/token?grant_type=password",
        headers={
            "apikey": publishable_key,
            "Content-Type": "application/json",
        },
        json={"email": admin_email, "password": admin_password},
        timeout=60,
    )
    response.raise_for_status()
    return supabase_url, response.json()["access_token"]


def _fetch_rows() -> list[dict[str, str]]:
    oracle_user = _require_env("ORACLE_USER")
    oracle_password = _require_env("ORACLE_PASSWORD")
    oracle_dsn = _require_env("ORACLE_DSN")
    _init_oracle_client_if_available()

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
            cursor.execute(ORACLE_QUERY)
            return [
                {
                    "codfornec": str(codfornec or "").strip(),
                    "supplier_name": str(supplier_name or "").strip(),
                    "imported_at": imported_at,
                }
                for codfornec, supplier_name in cursor
                if str(codfornec or "").strip() and str(supplier_name or "").strip()
            ]
    finally:
        connection.close()


def _upsert_rows(rows: list[dict[str, str]]) -> int:
    if not rows:
        return 0

    supabase_url, access_token = _authenticate_supabase()
    publishable_key = _require_env("SUPABASE_PUBLISHABLE_KEY")
    headers = {
        "apikey": publishable_key,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    response = requests.post(
        f"{supabase_url}/rest/v1/app_suppliers?on_conflict=codfornec",
        headers=headers,
        data=json.dumps(rows),
        timeout=300,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase supplier upsert failed: {response.status_code} {response.text}"
        )
    return len(rows)


def main() -> None:
    rows = _fetch_rows()
    upserted_count = _upsert_rows(rows)
    print(
        json.dumps(
            {
                "rows": len(rows),
                "upserted": upserted_count,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
