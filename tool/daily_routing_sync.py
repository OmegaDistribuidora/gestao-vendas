"""Read today's Gold routing source; publish only a changed, complete snapshot.

Preview uses fetch_snapshot only (read-only). Production sync requires --publish
and authenticates with the existing administrative ETL account. Never schedules
itself.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
from gold_performance_app_sync import (
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, _postgres_password,
)
from oracle_financial_sync_common import require_env
from supabase_sync_common import authenticate_supabase, invoke_rpc

SQL = Path(__file__).with_name('daily_routing_source.sql')
STATE_FILE = Path(
    os.getenv(
        'APP_DAILY_ROUTING_STATE_FILE',
        r'C:\Users\POWERBI\OneDrive - omegadistribuidora.com.br'
        r'\Projetos\William\app\.state\daily_routing_sync.sha256',
    )
)


def fetch_snapshot(day=None):
    day = day or datetime.now(ZoneInfo('America/Sao_Paulo')).date()
    with psycopg.connect(
        host=POSTGRES_HOST, port=POSTGRES_PORT, dbname=POSTGRES_DB,
        user=POSTGRES_USER, password=_postgres_password(), connect_timeout=10,
        options='-c default_transaction_read_only=on -c statement_timeout=20000',
    ) as connection:
        connection.execute('set transaction isolation level repeatable read')
        routing_count, month_count, ambiguous, sales_source_fresh = connection.execute('''
          select (select count(*) from filial."fRoteirizacao"),
                 (select count(*) from filial."fRoteiro"
                   where data>=date_trunc('month',%(day)s::date)
                     and data<date_trunc('month',%(day)s::date)+interval '1 month'),
                 (select count(*) from (
                   select codusur from filial.deqpcomercial
                   where data_insercao=(select max(data_insercao) from filial.deqpcomercial)
                   group by codusur having count(distinct (codsup,codgerente,bloqueio,time))>1
                 ) h),
                 (select completed_at >= now() - interval '15 minutes'
                    from gold_src.sync_state where source_name='fvendas')
        ''', {'day': day}).fetchone()
        if routing_count < 100 or month_count < 1000 or ambiguous or not sales_source_fresh:
            raise RuntimeError(
                'Fonte de roteiro/vendas incompleta, desatualizada ou hierarquia ambigua; '
                'snapshot preservado.'
            )
        result = connection.execute(SQL.read_text(encoding='utf-8'), {'day': day}).fetchone()[0]
    if not result['sellers'] or not result['source_updated_at']:
        raise RuntimeError('Fonte de roteiro/hierarquia indisponivel; snapshot preservado.')
    signature_payload = {
        key: value
        for key, value in result.items()
        if key not in {'source_updated_at', 'routing_updated_at'}
    }
    result['snapshot_id'] = hashlib.sha256(
        json.dumps(signature_payload, sort_keys=True, ensure_ascii=False).encode()
    ).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    snapshot = fetch_snapshot()
    if not args.publish:
        print(json.dumps({'date': snapshot['reference_date'], 'occurrences': len(snapshot['items']),
                          'purchased': sum(i['purchased'] for i in snapshot['items']),
                          'source_updated_at': snapshot['source_updated_at']}))
        return
    signature = snapshot['snapshot_id']
    if STATE_FILE.exists() and STATE_FILE.read_text().strip() == signature:
        print('Roteiro sem alteracoes; Supabase nao consultado.')
        return
    session = authenticate_supabase(require_env)
    invoke_rpc(
        session,
        'app_apply_daily_routing_snapshot',
        {'snapshot': snapshot},
        timeout=60,
    )
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_suffix('.tmp')
    temporary.write_text(signature, encoding='utf-8')
    temporary.replace(STATE_FILE)
    print(json.dumps({'published': snapshot['reference_date'], 'occurrences': len(snapshot['items'])}))


if __name__ == '__main__':
    main()
