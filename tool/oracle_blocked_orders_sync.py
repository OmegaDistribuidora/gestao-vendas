from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path

import oracledb
import requests


TABLE_NAME = "app_blocked_orders"
DOTENV_PATH = Path(__file__).with_name(".env")
QUERY_START_DATE = "01/01/2026"
BATCH_SIZE = 1000

ORACLE_QUERY = """
WITH raw_orders AS (
    SELECT
        pcpedc.numped AS numped,
        pcpedc.posicao AS cod_posicao,
        CASE
            WHEN pcpedc.posicao = 'B' THEN 'Bloqueado'
            ELSE 'Outros - ' || pcpedc.posicao
        END AS posicao_pedido,
        TRUNC(pcpedc.data) AS data_pedido,
        pcpedc.codcli,
        INITCAP(pcclient.cliente) AS client_name,
        pcpedc.codusur,
        INITCAP(pcusuari.nome) AS seller_name,
        pcusuari.codsupervisor,
        pcsuperv.codgerente,
        pcpedc.condvenda AS tipo_venda,
        CASE
            WHEN COALESCE(
                pcpedc.motivoposicao,
                pcpedc.obs,
                pcpedc.obs1,
                pcpedc.obs2
            ) = 'Bloqueio Comercial numero: 1.Verifique a rotina 307'
                THEN 'Bloqueio Comercial'
            WHEN REGEXP_LIKE(
                COALESCE(
                    pcpedc.motivoposicao,
                    pcpedc.obs,
                    pcpedc.obs1,
                    pcpedc.obs2
                ),
                '^O valor limite de credito foi excedido\\.  Vl\\. Ped\\.:.* Cr .*'
            )
                THEN 'O valor limite de credito foi excedido.'
            ELSE COALESCE(
                pcpedc.motivoposicao,
                pcpedc.obs,
                pcpedc.obs1,
                pcpedc.obs2
            )
        END AS motivo_bloqueio,
        pcpedi.codprod,
        pcprodut.descricao AS product_name,
        NVL(pcpedi.qt, 0) AS quantity_item,
        NVL(pcpedi.qt, 0) / NULLIF(pcprodut.qtunitcx, 0) AS volume_item,
        NVL(pcpedi.qt, 0) * NVL(pcpedi.pvenda, 0) AS valor_total_pedido
    FROM
        pcpedc
        JOIN pcpedi
            ON pcpedi.numped = pcpedc.numped
        JOIN pcprodut
            ON pcprodut.codprod = pcpedi.codprod
        LEFT JOIN pcclient
            ON pcclient.codcli = pcpedc.codcli
        LEFT JOIN pcusuari
            ON pcusuari.codusur = pcpedc.codusur
        LEFT JOIN pcsuperv
            ON pcsuperv.codsupervisor = pcusuari.codsupervisor
    WHERE
        pcpedc.data >= TO_DATE(:query_start_date, 'DD/MM/YYYY')
        AND pcpedc.data < TRUNC(SYSDATE) + 1
        AND pcpedc.posicao = 'B'
        AND pcpedc.dtcancel IS NULL
)
SELECT
    numped,
    cod_posicao,
    posicao_pedido,
    data_pedido,
    codcli,
    client_name,
    codusur,
    seller_name,
    codsupervisor,
    codgerente,
    tipo_venda,
    motivo_bloqueio,
    codprod,
    product_name,
    SUM(quantity_item) AS quantity_item,
    SUM(volume_item) AS volume_item,
    SUM(valor_total_pedido) AS valor_total_pedido
FROM raw_orders
GROUP BY
    numped,
    cod_posicao,
    posicao_pedido,
    data_pedido,
    codcli,
    client_name,
    codusur,
    seller_name,
    codsupervisor,
    codgerente,
    tipo_venda,
    motivo_bloqueio,
    codprod,
    product_name
ORDER BY
    data_pedido DESC,
    numped DESC,
    codprod
"""


@dataclass(frozen=True)
class BlockedOrderRow:
    numped: str
    cod_posicao: str
    posicao_pedido: str
    data_pedido: str
    codcli: str
    client_name: str
    codusur: str
    seller_name: str
    codsupervisor: str
    codgerente: str
    tipo_venda: int
    motivo_bloqueio: str
    codprod: str
    product_name: str
    quantity_item: float
    volume_item: float
    valor_total_pedido: float
    imported_at: str


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


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def normalize_text(value: object | None) -> str:
    return str(value or "").strip()


def to_float(value: Decimal | float | int | None) -> float:
    if value is None:
        return 0.0
    return float(value)


def init_oracle_client_if_available() -> None:
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
    return supabase_url, response.json()["access_token"]


def fetch_oracle_rows() -> list[BlockedOrderRow]:
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
            cursor.execute(ORACLE_QUERY, query_start_date=QUERY_START_DATE)
            rows: list[BlockedOrderRow] = []
            for (
                numped,
                cod_posicao,
                posicao_pedido,
                data_pedido,
                codcli,
                client_name,
                codusur,
                seller_name,
                codsupervisor,
                codgerente,
                tipo_venda,
                motivo_bloqueio,
                codprod,
                product_name,
                quantity_item,
                volume_item,
                valor_total_pedido,
            ) in cursor:
                rows.append(
                    BlockedOrderRow(
                        numped=normalize_text(numped),
                        cod_posicao=normalize_text(cod_posicao),
                        posicao_pedido=normalize_text(posicao_pedido),
                        data_pedido=data_pedido.strftime("%Y-%m-%d"),
                        codcli=normalize_text(codcli),
                        client_name=normalize_text(client_name),
                        codusur=normalize_text(codusur),
                        seller_name=normalize_text(seller_name),
                        codsupervisor=normalize_text(codsupervisor),
                        codgerente=normalize_text(codgerente),
                        tipo_venda=int(tipo_venda or 0),
                        motivo_bloqueio=normalize_text(motivo_bloqueio),
                        codprod=normalize_text(codprod),
                        product_name=normalize_text(product_name),
                        quantity_item=to_float(quantity_item),
                        volume_item=to_float(volume_item),
                        valor_total_pedido=to_float(valor_total_pedido),
                        imported_at=imported_at,
                    )
                )
            return rows
    finally:
        connection.close()


def purge_supabase_rows() -> int:
    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")

    response = requests.delete(
        f"{supabase_url}/rest/v1/{TABLE_NAME}",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {access_token}",
            "Prefer": "return=representation",
        },
        params={
            "numped": "not.is.null",
        },
        timeout=300,
    )
    if not response.ok:
        raise RuntimeError(
            f"Supabase blocked orders purge failed: {response.status_code} {response.text}"
        )

    deleted_rows = response.json() if response.text.strip() else []
    return len(deleted_rows) if isinstance(deleted_rows, list) else 0


def upsert_supabase_rows(rows: list[BlockedOrderRow]) -> int:
    payload = [
        {
            "numped": row.numped,
            "cod_posicao": row.cod_posicao,
            "posicao_pedido": row.posicao_pedido,
            "data_pedido": row.data_pedido,
            "codcli": row.codcli,
            "client_name": row.client_name,
            "codusur": row.codusur,
            "seller_name": row.seller_name,
            "codsupervisor": row.codsupervisor,
            "codgerente": row.codgerente,
            "tipo_venda": row.tipo_venda,
            "motivo_bloqueio": row.motivo_bloqueio,
            "codprod": row.codprod,
            "product_name": row.product_name,
            "quantity_item": row.quantity_item,
            "volume_item": row.volume_item,
            "valor_total_pedido": row.valor_total_pedido,
            "imported_at": row.imported_at,
        }
        for row in rows
    ]

    if not payload:
        return 0

    supabase_url, access_token = authenticate_supabase()
    publishable_key = require_env("SUPABASE_PUBLISHABLE_KEY")
    headers = {
        "apikey": publishable_key,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }

    for start in range(0, len(payload), BATCH_SIZE):
        chunk = payload[start : start + BATCH_SIZE]
        response = requests.post(
            f"{supabase_url}/rest/v1/{TABLE_NAME}?on_conflict=numped,codprod",
            headers=headers,
            data=json.dumps(chunk),
            timeout=300,
        )
        if not response.ok:
            raise RuntimeError(
                f"Supabase blocked orders upsert failed on batch {start}: "
                f"{response.status_code} {response.text}"
            )

    return len(payload)


def main() -> None:
    load_local_dotenv()
    rows = fetch_oracle_rows()
    purged_count = purge_supabase_rows()
    upserted_count = upsert_supabase_rows(rows)
    total_value = sum(row.valor_total_pedido for row in rows)
    print(
        json.dumps(
            {
                "rows": len(rows),
                "purged": purged_count,
                "upserted": upserted_count,
                "total_value": round(total_value, 2),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
