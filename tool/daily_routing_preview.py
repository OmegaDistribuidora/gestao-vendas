"""Emulator-only preview: real read-only source, isolated local PostgreSQL/API.

No migrations or writes against Supabase/Omega. Incoming JWTs are verified by
Supabase Auth; alternate scopes must pass the existing production scope resolver.
Only the new routing RPC runs locally, using the pending migration verbatim.
"""
from __future__ import annotations

import json
import os
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb
import requests

from daily_routing_sync import fetch_snapshot

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / '.dart_tool' / 'daily_routing_preview'
PG = Path(r'C:\Program Files\PostgreSQL\17\bin')
DSN = 'host=127.0.0.1 port=55439 dbname=postgres user=routing_preview'
URL = 'https://ewkexlyywmvufbirmpot.supabase.co'
LOCK = threading.Lock()
LAST_FETCH: dict[str, float] = {}


def local_connection():
    return psycopg.connect(DSN, connect_timeout=5)


def bootstrap():
    STATE.mkdir(parents=True, exist_ok=True)
    cluster = STATE / 'pg'
    if not (cluster / 'PG_VERSION').exists():
        subprocess.run([str(PG/'initdb.exe'), '-D', str(cluster), '-U', 'routing_preview',
                        '-A', 'trust', '--encoding=UTF8', '--locale=C'], check=True,
                       capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
    status = subprocess.run([str(PG/'pg_ctl.exe'), '-D', str(cluster), 'status'], capture_output=True,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    if status.returncode:
        subprocess.run([str(PG/'pg_ctl.exe'), '-D', str(cluster), '-l', str(STATE/'postgres.log'),
                        '-o', '-h 127.0.0.1 -p 55439', '-w', 'start'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    with local_connection() as c:
        if not c.execute("select to_regclass('public.app_daily_routing_snapshots')").fetchone()[0]:
            c.execute("""
          create role anon; create role authenticated; create role service_role;
          create schema auth;
          create function auth.uid() returns uuid language sql as
            'select nullif(current_setting(''request.jwt.claim.sub'',true),'''')::uuid';
          create function auth.jwt() returns jsonb language sql as
            'select ''{"role":"service_role"}''::jsonb';
          create table public.app_profiles(id uuid primary key,slug text);
          create table public.app_users(auth_user_id uuid primary key,profile_id uuid,
                                       code text,is_active boolean);
          -- Preview resolves alternate scopes on the real API before querying
          -- locally. Direct local attempts to change scope fail closed.
          create function public.app_resolve_view_scope_auth_user(text,text)
            returns uuid language sql as 'select null::uuid';
            """)
            scope = (ROOT/'supabase/migrations/20260831170000_management_profile_scope.sql').read_text(encoding='utf-8')
            c.execute(scope.split('create or replace function public.app_scope_user_allowed')[0])
            c.execute((ROOT/'supabase/migrations/20260910120000_home_daily_routing.sql').read_text(encoding='utf-8'))
        c.execute("""
          create or replace function auth.jwt() returns jsonb language sql as
            'select ''{"role":"service_role"}''::jsonb';
          alter table public.app_profiles add column if not exists name text;
          alter table public.app_users add column if not exists display_name text;
          create or replace function public.app_view_scope_options(
            text[] default array['gerencia','coordenador','supervisor','vendedor']::text[]
          ) returns jsonb language sql as 'select ''[]''::jsonb';
          create or replace function public.app_resolve_view_scope_auth_user(
            text,text,text[]
          ) returns uuid language sql as 'select null::uuid';
        """)
        c.execute((ROOT/'supabase/migrations/20260911120000_routing_analysis_module.sql').read_text(encoding='utf-8'))
        c.execute((ROOT/'supabase/migrations/20260911123000_routing_production_hardening.sql').read_text(encoding='utf-8'))


def refresh_source(day=None):
    day_key = str(day or datetime.now().date())
    with LOCK:
        if time.monotonic() - LAST_FETCH.get(day_key, 0) < 120:
            return
        snapshot = fetch_snapshot(day)
        with local_connection() as c:
            c.execute('select public.app_apply_daily_routing_snapshot(%s)', (Jsonb(snapshot),))
        LAST_FETCH[day_key] = time.monotonic()


def api_get(path, headers):
    response = requests.get(URL+path, headers=headers, timeout=15)
    if response.status_code in (401,403):
        raise PermissionError('Sessao nao autorizada.')
    response.raise_for_status()
    return response.json()


class Handler(BaseHTTPRequestHandler):
    key = ''

    def log_message(self, format, *args):
        pass  # Never log authorization headers or customer data.

    def do_GET(self):
        if self.path != '/health':
            self.respond(404, {})
            return
        self.respond(200, {'preview': True})

    def do_POST(self):
        if self.path not in ('/routing', '/route-analysis'):
            self.respond(404, {})
            return
        try:
            if int(self.headers.get('Content-Length','0')) > 8192:
                raise ValueError('Pedido muito grande.')
            payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            token = self.headers.get('Authorization','')
            if not token.startswith('Bearer '):
                raise PermissionError('Sessao ausente.')
            user_headers = {'apikey': self.key, 'Authorization': token}
            user = api_get('/auth/v1/user', user_headers)
            effective_id = user['id']
            profile, code = payload.get('target_scope_profile_slug'),payload.get('target_scope_owner_code')
            if bool(profile) != bool(code):
                raise PermissionError('Filtro incompleto.')
            if profile:
                response = requests.post(URL+'/rest/v1/rpc/app_resolve_view_scope_auth_user',
                    headers=user_headers, json={'target_profile_slug': profile, 'target_owner_code': code}, timeout=15)
                response.raise_for_status()
                effective_id = response.json()
                if not effective_id:
                    raise PermissionError('Visao nao autorizada.')
            admin_headers = {'apikey': self.key, 'Authorization': 'Bearer '+self.key}
            # Read active identity, without copying credentials or unrelated users.
            viewers = api_get('/rest/v1/app_users?select=auth_user_id,profile_id,code,is_active'
                              +'&auth_user_id=eq.'+user['id'], admin_headers)
            owners = api_get('/rest/v1/app_users?select=auth_user_id,profile_id,code,is_active,display_name'
                            +'&auth_user_id=eq.'+effective_id, admin_headers)
            if not viewers or not viewers[0]['is_active'] or not owners or not owners[0]['is_active']:
                raise PermissionError('Usuario inativo.')
            owner = owners[0]
            profiles = api_get('/rest/v1/app_profiles?select=id,slug,name&id=eq.'+owner['profile_id'], admin_headers)
            allowed = api_get('/rest/v1/app_profile_coordinator_scopes?select=profile_slug,coordinator_code', admin_headers)
            refresh_source(payload['target_date'])
            with local_connection() as c:
                c.execute('insert into app_profiles(id,slug,name) values(%s,%s,%s) '
                          'on conflict(id) do update set slug=excluded.slug,name=excluded.name',
                          (profiles[0]['id'],profiles[0]['slug'],profiles[0].get('name')))
                c.execute('insert into app_users(auth_user_id,profile_id,code,is_active,display_name) '
                          'values(%s,%s,%s,%s,%s) on conflict(auth_user_id) do update set '
                          'profile_id=excluded.profile_id,code=excluded.code,is_active=excluded.is_active,'
                          'display_name=excluded.display_name',
                          (effective_id,owner['profile_id'],owner['code'],True,owner.get('display_name')))
                # Keep management scope identical to configured production scope.
                c.execute('delete from app_profile_coordinator_scopes')
                with c.cursor() as cursor:
                    cursor.executemany('insert into app_profile_coordinator_scopes(profile_slug,coordinator_code) values(%s,%s)',
                                       [(r['profile_slug'],r['coordinator_code']) for r in allowed])
                c.execute("select set_config('request.jwt.claim.sub',%s,true)",(effective_id,))
                if self.path == '/routing':
                    result = c.execute('select public.get_home_daily_routing(%s,null,null,%s,%s,%s,%s,%s)',
                        (payload['target_date'],payload.get('include_details',False),payload.get('item_filter','all'),
                         payload.get('page_offset',0),payload.get('page_size',100),payload.get('expected_snapshot_id'))).fetchone()[0]
                else:
                    result = c.execute('select public.get_routing_analysis(%s,null,null)',
                                       (payload['target_date'],)).fetchone()[0]
            if self.path == '/route-analysis':
                scope_response = requests.post(
                    URL+'/rest/v1/rpc/app_view_scope_options', headers=user_headers,
                    json={'allowed_target_profiles':['gerencia','coordenador','supervisor','vendedor']}, timeout=15)
                scope_response.raise_for_status()
                result['available_scopes'] = scope_response.json()
                result['selected_scope_profile_slug'] = profile
                result['selected_scope_owner_code'] = code
            self.respond(200,result)
        except PermissionError:
            self.respond(403, {'message':'Visao nao autorizada.'})
        except Exception as error:
            print('Preview query failed:',type(error).__name__, flush=True)
            self.respond(400, {'message':'Consulta indisponivel; atualize e tente novamente.'})

    def respond(self, status, payload):
        content = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(content)))
        self.end_headers()
        self.wfile.write(content)


if __name__ == '__main__':
    # CLI credential remains in this local process; never in the APK or files.
    result = subprocess.run(['supabase','projects','api-keys','--project-ref','ewkexlyywmvufbirmpot','-o','json'],
                            check=True,capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
    Handler.key = next(k['api_key'] for k in json.loads(result.stdout) if k['name']=='service_role')
    bootstrap()
    refresh_source()
    print('Routing preview ready: 127.0.0.1:8766 (local database 55439)',flush=True)
    ThreadingHTTPServer(('127.0.0.1',8766),Handler).serve_forever()
