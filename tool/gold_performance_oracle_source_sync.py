from __future__ import annotations

import argparse
import os
import subprocess
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Iterable, Sequence

import oracledb
import psycopg
from psycopg import sql


FIRST_GOLD_DATE = date(2026, 6, 1)
DEFAULT_SCHEMA = "gold_src"
DEFAULT_ENV_FILE = Path(
    os.getenv(
        "OMEGA_APP_ENV_FILE",
        r"C:\Users\POWERBI\OneDrive - omegadistribuidora.com.br\Projetos\William\app\.env",
    )
)
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
LOCK_ID = 7_403_061_001


# These are deliberately derived from the canonical BI queries in Transf_Dados.
# Only columns consumed by gold.atualizar_performance are selected and aggregated.
ORACLE_SALES_QUERY = """
SELECT
    TRUNC(pcpedc.data) AS data,
    pcpedi.codusur,
    pcpedi.codcli,
    pcprodut.codfornec,
    pcpedi.codprod,
    SUM(pcpedi.qt) AS qt,
    SUM(pcpedi.qt * pcpedi.pvenda) AS venda,
    SUM(pcpedi.qt / NULLIF(pcprodut.qtunitcx, 0)) AS volume
FROM pcpedi
JOIN pcpedc ON pcpedi.numped = pcpedc.numped
JOIN pcprodut ON pcpedi.codprod = pcprodut.codprod
WHERE pcpedi.data >= :window_start
  AND pcpedi.data < :window_end
  AND pcpedc.codfilial IN (1, 3, 4)
  AND pcpedc.condvenda = 1
  AND pcpedc.dtcancel IS NULL
GROUP BY
    TRUNC(pcpedc.data), pcpedi.codusur, pcpedi.codcli,
    pcprodut.codfornec, pcpedi.codprod
"""

ORACLE_RETURNS_QUERY = """
SELECT
    TRUNC(pcmov.dtmov) AS data,
    pcmov.codusur,
    pcmov.codcli,
    pcfornec.codfornec,
    pcmov.codprod,
    SUM(pcmov.qt) AS qt,
    (SUM(pcmov.qt * pcmov.punit)
      + SUM(pcmov.qt * NVL(pcmov.vloutros, 0))) * -1 AS faturamento,
    SUM(pcmov.qt / NULLIF(pcprodut.qtunitcx, 0)) * -1 AS volume
FROM pcmov
JOIN pcnfent ON pcmov.numtransent = pcnfent.numtransent
JOIN pcpedc ON pcmov.numped = pcpedc.numped
JOIN pcusuari ON pcmov.codusur = pcusuari.codusur
JOIN pcprodut ON pcmov.codprod = pcprodut.codprod
JOIN pcfornec ON pcprodut.codfornec = pcfornec.codfornec
JOIN pctabdev ON pctabdev.coddevol = pcnfent.coddevol
WHERE pcmov.dtmov >= :window_start
  AND pcmov.dtmov < :window_end
  AND pcpedc.codfilial IN (1, 3, 4)
  AND pcpedc.condvenda = 1
  AND pcpedc.dtcancel IS NULL
  AND pcmov.codoper IN ('E', 'ED')
  AND (pcmov.pbonific = 0 OR pcmov.pbonific IS NULL)
GROUP BY
    TRUNC(pcmov.dtmov), pcmov.codusur, pcmov.codcli,
    pcfornec.codfornec, pcmov.codprod
"""

ORACLE_BILLING_QUERY = """
SELECT
    tipo,
    data,
    codusur,
    codfornec,
    condvenda,
    SUM(faturamento) AS faturamento,
    SUM(custo) AS custo
FROM (
    SELECT
        'F' AS tipo,
        TRUNC(pcmov.dtmov) AS data,
        pcmov.codusur,
        CASE
            WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
            WHEN pcfornec.codfornec IN (1443, 967) THEN 967
            WHEN pcfornec.codfornec IN (1493, 1465) THEN 2727
            WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
            ELSE pcfornec.codfornec
        END AS codfornec,
        pcpedc.condvenda,
        SUM(pcmov.qt * pcmov.punit)
          + SUM(pcmov.qt * NVL(pcmov.vloutros, 0)) AS faturamento,
        SUM(pcmov.qt * pcmov.custofin) AS custo
    FROM pcmov
    JOIN pcnfsaid ON pcmov.numtransvenda = pcnfsaid.numtransvenda
    JOIN pcpedc ON pcmov.numped = pcpedc.numped
    JOIN pcusuari ON pcmov.codusur = pcusuari.codusur
    JOIN pcprodut ON pcmov.codprod = pcprodut.codprod
    JOIN pcfornec ON pcprodut.codfornec = pcfornec.codfornec
    LEFT JOIN pcnfent ON pcmov.numtransent = pcnfent.numtransent
    WHERE pcmov.dtmov >= :window_start
      AND pcmov.dtmov < :window_end
      AND pcpedc.codfilial IN (1, 3, 4)
      AND pcpedc.condvenda IN (1)
      AND pcmov.dtcancel IS NULL
      AND pcmov.codoper NOT IN ('SR', 'SO')
      AND (pcmov.pbonific = 0 OR pcmov.pbonific IS NULL)
    GROUP BY
        TRUNC(pcmov.dtmov), pcmov.codusur, pcpedc.condvenda,
        CASE
            WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
            WHEN pcfornec.codfornec IN (1443, 967) THEN 967
            WHEN pcfornec.codfornec IN (1493, 1465) THEN 2727
            WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
            ELSE pcfornec.codfornec
        END
    UNION ALL
    SELECT
        'D' AS tipo,
        TRUNC(pcmov.dtmov) AS data,
        pcmov.codusur,
        CASE
            WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
            WHEN pcfornec.codfornec IN (1443, 967) THEN 967
            WHEN pcfornec.codfornec IN (1493, 1465) THEN 2727
            WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
            ELSE pcfornec.codfornec
        END AS codfornec,
        pcpedc.condvenda,
        (SUM(pcmov.qt * pcmov.punit)
          + SUM(pcmov.qt * NVL(pcmov.vloutros, 0))) * -1 AS faturamento,
        SUM(pcmov.qt * pcmov.custofin) * -1 AS custo
    FROM pcmov
    JOIN pcnfent ON pcmov.numtransent = pcnfent.numtransent
    JOIN pcpedc ON pcmov.numped = pcpedc.numped
    JOIN pcusuari ON pcmov.codusur = pcusuari.codusur
    JOIN pcprodut ON pcmov.codprod = pcprodut.codprod
    JOIN pcfornec ON pcprodut.codfornec = pcfornec.codfornec
    WHERE pcmov.dtmov >= :window_start
      AND pcmov.dtmov < :window_end
      AND pcpedc.codfilial IN (1, 3, 4)
      AND pcpedc.condvenda IN (1)
      AND pcmov.dtcancel IS NULL
      AND pcmov.codoper IN ('E', 'ED')
      AND (pcmov.pbonific = 0 OR pcmov.pbonific IS NULL)
    GROUP BY
        TRUNC(pcmov.dtmov), pcmov.codusur, pcpedc.condvenda,
        CASE
            WHEN pcfornec.codfornec IN (1535, 1968) THEN 1968
            WHEN pcfornec.codfornec IN (1443, 967) THEN 967
            WHEN pcfornec.codfornec IN (1493, 1465) THEN 2727
            WHEN pcfornec.codfornec IN (1630, 2445) THEN 1630
            ELSE pcfornec.codfornec
        END
)
GROUP BY tipo, data, codusur, codfornec, condvenda
"""


@dataclass(frozen=True)
class SourceSpec:
    name: str
    query: str
    columns: tuple[str, ...]


SOURCES = (
    SourceSpec(
        "fvendas",
        ORACLE_SALES_QUERY,
        ("data", "codusur", "codcli", "codfornec", "codprod", "qt", "venda", "volume"),
    ),
    SourceSpec(
        "fdevolucao",
        ORACLE_RETURNS_QUERY,
        ("data", "codusur", "codcli", "codfornec", "codprod", "qt", "faturamento", "volume"),
    ),
    SourceSpec(
        "ffaturamento",
        ORACLE_BILLING_QUERY,
        ("tipo", "data", "codusur", "codfornec", "condvenda", "faturamento", "custo"),
    ),
)


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        raise RuntimeError(f"Environment file not found: {path}")
    for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def _postgres_password() -> str:
    configured = os.getenv("APP_POSTGRES_PASSWORD", "").strip()
    if configured:
        return configured
    if os.name != "nt" or not POSTGRES_CREDENTIAL_FILE.exists():
        raise RuntimeError("APP_POSTGRES_PASSWORD is required on this host.")
    credential_path = str(POSTGRES_CREDENTIAL_FILE).replace("'", "''")
    command = (
        f"$credential = Get-Content -LiteralPath '{credential_path}' | Select-Object -First 1; "
        "$secure = ConvertTo-SecureString -String $credential; "
        "$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); "
        "try { [Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringAuto($pointer)) } "
        "finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }"
    )
    result = subprocess.run(
        [POWERSHELL_EXE, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
        capture_output=True,
        text=True,
        check=False,
    )
    password = result.stdout.strip()
    if result.returncode != 0 or not password:
        raise RuntimeError("Unable to read the encrypted PostgreSQL credential.")
    return password


def _connect_postgres() -> psycopg.Connection:
    return psycopg.connect(
        host=os.getenv("APP_POSTGRES_HOST", "192.168.1.14"),
        port=int(os.getenv("APP_POSTGRES_PORT", "5432")),
        dbname=os.getenv("APP_POSTGRES_DB", "Omega"),
        user=os.getenv("APP_POSTGRES_USER", "PwBi"),
        password=_postgres_password(),
    )


def _connect_oracle() -> oracledb.Connection:
    client_dir = os.getenv("ORACLE_CLIENT_LIB_DIR", "").strip()
    if client_dir:
        try:
            oracledb.init_oracle_client(lib_dir=client_dir)
        except oracledb.ProgrammingError:
            pass
    return oracledb.connect(
        user=_require_env("ORACLE_USER"),
        password=_require_env("ORACLE_PASSWORD"),
        dsn=_require_env("ORACLE_DSN"),
    )


def _validate_identifier(value: str) -> str:
    if not value or not value.replace("_", "").isalnum() or value[0].isdigit():
        raise ValueError(f"Invalid SQL identifier: {value!r}")
    return value


def _create_objects(connection: psycopg.Connection, schema: str) -> None:
    schema_id = sql.Identifier(schema)
    statements = (
        sql.SQL("create schema if not exists {}").format(schema_id),
        sql.SQL("""
            create table if not exists {}.fvendas (
                data date not null, codusur integer not null, codcli integer not null,
                codfornec integer not null, codprod integer not null,
                qt numeric not null, venda numeric not null, volume numeric not null
            )
        """).format(schema_id),
        sql.SQL("""
            create table if not exists {}.fdevolucao (
                data date not null, codusur integer not null, codcli integer not null,
                codfornec integer not null, codprod integer not null,
                qt numeric not null, faturamento numeric not null, volume numeric not null
            )
        """).format(schema_id),
        sql.SQL("""
            create table if not exists {}.ffaturamento (
                tipo text not null, data date not null, codusur integer not null,
                codfornec integer not null, condvenda integer not null,
                faturamento numeric not null, custo numeric not null
            )
        """).format(schema_id),
        sql.SQL("""
            create table if not exists {}.sync_state (
                source_name text primary key,
                window_start date not null,
                window_end_exclusive date not null,
                row_count bigint not null,
                completed_at timestamptz not null default now(),
                run_id uuid not null
            )
        """).format(schema_id),
        sql.SQL("create index if not exists {} on {}.fvendas (data, codusur, codfornec)").format(
            sql.Identifier(f"ix_{schema}_fvendas_window"), schema_id
        ),
        sql.SQL("create index if not exists {} on {}.fdevolucao (data, codusur, codfornec)").format(
            sql.Identifier(f"ix_{schema}_fdevolucao_window"), schema_id
        ),
        sql.SQL("create index if not exists {} on {}.ffaturamento (data, codusur, codfornec)").format(
            sql.Identifier(f"ix_{schema}_ffaturamento_window"), schema_id
        ),
    )
    with connection.cursor() as cursor:
        for statement in statements:
            cursor.execute(statement)


def _copy_oracle_rows(
    oracle_connection: oracledb.Connection,
    pg_connection: psycopg.Connection,
    schema: str,
    spec: SourceSpec,
    start: date,
    end_exclusive: date,
) -> tuple[str, int]:
    staging = f"stage_{spec.name}_{uuid.uuid4().hex[:10]}"
    schema_id = sql.Identifier(schema)
    staging_id = sql.Identifier(staging)
    with pg_connection.cursor() as pg_cursor:
        pg_cursor.execute(
            sql.SQL("create temporary table {} (like {}.{} including defaults) on commit drop").format(
                staging_id, schema_id, sql.Identifier(spec.name)
            )
        )
        copy_statement = sql.SQL("copy {} ({}) from stdin").format(
            staging_id,
            sql.SQL(", ").join(map(sql.Identifier, spec.columns)),
        )
        count = 0
        with oracle_connection.cursor() as oracle_cursor:
            oracle_cursor.arraysize = 5000
            oracle_cursor.execute(
                spec.query,
                window_start=start,
                window_end=end_exclusive,
            )
            with pg_cursor.copy(copy_statement) as copy:
                while True:
                    rows = oracle_cursor.fetchmany(5000)
                    if not rows:
                        break
                    for row in rows:
                        copy.write_row(row)
                    count += len(rows)
    return staging, count


def _replace_window(
    connection: psycopg.Connection,
    schema: str,
    spec: SourceSpec,
    staging: str,
    start: date,
    end_exclusive: date,
    row_count: int,
    run_id: uuid.UUID,
) -> None:
    with connection.cursor() as cursor:
        cursor.execute(
            sql.SQL("delete from {}.{} where data >= %s and data < %s").format(
                sql.Identifier(schema), sql.Identifier(spec.name)
            ),
            (start, end_exclusive),
        )
        cursor.execute(
            sql.SQL("insert into {}.{} ({}) select {} from {}").format(
                sql.Identifier(schema),
                sql.Identifier(spec.name),
                sql.SQL(", ").join(map(sql.Identifier, spec.columns)),
                sql.SQL(", ").join(map(sql.Identifier, spec.columns)),
                sql.Identifier(staging),
            )
        )
        cursor.execute(
            sql.SQL("""
                insert into {}.sync_state
                    (source_name, window_start, window_end_exclusive, row_count, completed_at, run_id)
                values (%s, %s, %s, %s, now(), %s)
                on conflict (source_name) do update set
                    window_start = excluded.window_start,
                    window_end_exclusive = excluded.window_end_exclusive,
                    row_count = excluded.row_count,
                    completed_at = excluded.completed_at,
                    run_id = excluded.run_id
            """).format(sql.Identifier(schema)),
            (spec.name, start, end_exclusive, row_count, run_id),
        )


def _summary(connection: psycopg.Connection, schema: str, start: date, end: date) -> list[tuple]:
    query = sql.SQL("""
        select 'fvendas', count(*), coalesce(sum(venda), 0), coalesce(sum(volume), 0), coalesce(sum(qt), 0)
          from {}.fvendas where data >= %s and data < %s
        union all
        select 'fdevolucao', count(*), coalesce(sum(faturamento), 0), coalesce(sum(volume), 0), coalesce(sum(qt), 0)
          from {}.fdevolucao where data >= %s and data < %s
        union all
        select 'ffaturamento', count(*), coalesce(sum(faturamento), 0), coalesce(sum(custo), 0), 0
          from {}.ffaturamento where data >= %s and data < %s and condvenda = 1
        order by 1
    """).format(*([sql.Identifier(schema)] * 3))
    with connection.cursor() as cursor:
        cursor.execute(query, (start, end, start, end, start, end))
        return cursor.fetchall()


def _compare_with_filial(
    connection: psycopg.Connection,
    schema: str,
    start: date,
    end_exclusive: date,
) -> list[tuple]:
    query = sql.SQL("""
        with source_totals as (
            select 'fvendas'::text source, sum(venda)::numeric value_1,
                   sum(volume)::numeric value_2, sum(qt)::numeric value_3
              from {}.fvendas where data >= %s and data < %s
            union all
            select 'fdevolucao', sum(faturamento), sum(volume), sum(qt)
              from {}.fdevolucao where data >= %s and data < %s
            union all
            select 'ffaturamento', sum(faturamento), sum(custo), 0
              from {}.ffaturamento where data >= %s and data < %s and condvenda = 1
        ), local_totals as (
            select 'fvendas'::text source, sum(venda)::numeric value_1,
                   sum(volume)::numeric value_2, sum(qt)::numeric value_3
              from filial.fvendas where data >= %s and data < %s
            union all
            select 'fdevolucao', sum(faturamento), sum(volume), sum(qt)
              from filial.fdevolucao where data >= %s and data < %s
            union all
            select 'ffaturamento', sum(faturamento), sum(custo), 0
              from filial.ffaturamento where data >= %s and data < %s and condvenda = 1
        )
        select s.source,
               round(coalesce(s.value_1, 0), 4), round(coalesce(l.value_1, 0), 4),
               round(coalesce(s.value_1, 0) - coalesce(l.value_1, 0), 4),
               round(coalesce(s.value_2, 0) - coalesce(l.value_2, 0), 4),
               round(coalesce(s.value_3, 0) - coalesce(l.value_3, 0), 4)
          from source_totals s join local_totals l using (source)
         order by s.source
    """).format(*([sql.Identifier(schema)] * 3))
    params = (start, end_exclusive) * 6
    with connection.cursor() as cursor:
        cursor.execute(query, params)
        return cursor.fetchall()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh the Gold performance operational facts from Oracle.")
    parser.add_argument("--schema", default=os.getenv("GOLD_SOURCE_SCHEMA", DEFAULT_SCHEMA))
    parser.add_argument("--start-date", type=date.fromisoformat)
    parser.add_argument("--end-date", type=date.fromisoformat, help="Inclusive end date")
    parser.add_argument("--backfill", action="store_true", help="Refresh from 2026-06-01 through today")
    parser.add_argument("--compare-local", action="store_true")
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_FILE)
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    schema = _validate_identifier(args.schema)
    today = date.today()
    if args.backfill:
        start = FIRST_GOLD_DATE
    else:
        start = args.start_date or max(FIRST_GOLD_DATE, today - timedelta(days=1))
    end_inclusive = args.end_date or today
    end_exclusive = end_inclusive + timedelta(days=1)
    if start < FIRST_GOLD_DATE or end_exclusive <= start:
        raise ValueError(f"Invalid Gold source window: {start} through {end_inclusive}")

    _load_dotenv(args.env_file)
    run_id = uuid.uuid4()
    started_at = datetime.now()
    counts: dict[str, int] = {}

    with _connect_postgres() as pg_connection:
        with pg_connection.cursor() as cursor:
            cursor.execute("select pg_try_advisory_xact_lock(%s)", (LOCK_ID,))
            if not cursor.fetchone()[0]:
                raise RuntimeError("Another Gold Oracle source refresh is already running.")
        _create_objects(pg_connection, schema)
        with _connect_oracle() as oracle_connection:
            for spec in SOURCES:
                staging, count = _copy_oracle_rows(
                    oracle_connection, pg_connection, schema, spec, start, end_exclusive
                )
                _replace_window(
                    pg_connection, schema, spec, staging, start, end_exclusive, count, run_id
                )
                counts[spec.name] = count

        summary = _summary(pg_connection, schema, start, end_exclusive)
        comparison = (
            _compare_with_filial(pg_connection, schema, start, end_exclusive)
            if args.compare_local
            else []
        )
        pg_connection.commit()

    duration = (datetime.now() - started_at).total_seconds()
    print(
        f"Gold Oracle source refreshed atomically: schema={schema}, "
        f"window={start}..{end_inclusive}, rows={counts}, duration={duration:.1f}s"
    )
    for row in summary:
        print(f"summary={row}")
    for row in comparison:
        print(
            "compare_local="
            f"source={row[0]}, oracle={row[1]}, local={row[2]}, "
            f"delta_primary={row[3]}, delta_secondary={row[4]}, delta_tertiary={row[5]}"
        )


if __name__ == "__main__":
    main()
