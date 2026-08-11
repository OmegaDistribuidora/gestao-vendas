create unlogged table if not exists public.etl_stg_gold_performance (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  id_apuracao text not null,
  competencia_data date not null,
  codigo_usuario text not null,
  perfil_usuario text not null,
  tipo_usuario text not null,
  codigo_supervisor integer,
  codigo_coordenador integer,
  tipo_performance text not null check (tipo_performance in ('Geral', 'Fornecedor')),
  codigo_fornecedor integer,
  fornecedor text,
  payload jsonb not null,
  source_updated_at timestamptz,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, id_apuracao)
);

grant select, insert, delete on public.etl_stg_gold_performance
  to authenticated, service_role;

alter table public.etl_stg_gold_performance enable row level security;

drop policy if exists "etl_stg_gold_performance_admin_manage"
  on public.etl_stg_gold_performance;
create policy "etl_stg_gold_performance_admin_manage"
on public.etl_stg_gold_performance
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.apply_gold_performance_sync(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.etl_sync_runs%rowtype;
  v_rows_staged integer;
  v_rows_inserted integer;
  v_rows_updated integer;
  v_rows_deleted integer;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  select *
    into v_run
  from public.etl_sync_runs
  where id = p_run_id
  for update;

  if not found then
    raise exception 'Execucao de sincronizacao nao encontrada.';
  end if;

  if v_run.status <> 'running' then
    raise exception 'Execucao de sincronizacao nao esta em andamento.';
  end if;

  if v_run.target_name <> 'app_gold_performance' then
    raise exception 'Destino invalido para a sincronizacao Gold.';
  end if;

  select count(*)::integer
    into v_rows_staged
  from public.etl_stg_gold_performance
  where run_id = p_run_id;

  if v_rows_staged = 0 then
    raise exception 'A carga Gold preparada esta vazia.';
  end if;

  if v_run.rows_staged <> v_rows_staged then
    raise exception 'Carga Gold incompleta: esperado %, encontrado %.',
      v_run.rows_staged, v_rows_staged;
  end if;

  select count(*)::integer
    into v_rows_updated
  from public.etl_stg_gold_performance s
  join public.app_gold_performance t on t.id_apuracao = s.id_apuracao
  where s.run_id = p_run_id;

  v_rows_inserted := v_rows_staged - v_rows_updated;

  insert into public.app_gold_performance (
    id_apuracao,
    competencia_data,
    codigo_usuario,
    perfil_usuario,
    tipo_usuario,
    codigo_supervisor,
    codigo_coordenador,
    tipo_performance,
    codigo_fornecedor,
    fornecedor,
    payload,
    source_updated_at,
    synced_at
  )
  select
    s.id_apuracao,
    s.competencia_data,
    s.codigo_usuario,
    s.perfil_usuario,
    s.tipo_usuario,
    s.codigo_supervisor,
    s.codigo_coordenador,
    s.tipo_performance,
    s.codigo_fornecedor,
    s.fornecedor,
    s.payload,
    s.source_updated_at,
    timezone('utc', now())
  from public.etl_stg_gold_performance s
  where s.run_id = p_run_id
  on conflict (id_apuracao)
  do update set
    competencia_data = excluded.competencia_data,
    codigo_usuario = excluded.codigo_usuario,
    perfil_usuario = excluded.perfil_usuario,
    tipo_usuario = excluded.tipo_usuario,
    codigo_supervisor = excluded.codigo_supervisor,
    codigo_coordenador = excluded.codigo_coordenador,
    tipo_performance = excluded.tipo_performance,
    codigo_fornecedor = excluded.codigo_fornecedor,
    fornecedor = excluded.fornecedor,
    payload = excluded.payload,
    source_updated_at = excluded.source_updated_at,
    synced_at = excluded.synced_at;

  delete from public.app_gold_performance t
  where t.competencia_data between v_run.window_start and v_run.window_end
    and not exists (
      select 1
      from public.etl_stg_gold_performance s
      where s.run_id = p_run_id
        and s.id_apuracao = t.id_apuracao
    );
  get diagnostics v_rows_deleted = row_count;

  delete from public.etl_stg_gold_performance
  where run_id = p_run_id;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_rows_staged,
         rows_inserted = v_rows_inserted,
         rows_updated = v_rows_updated,
         rows_deleted = v_rows_deleted,
         notes = jsonb_build_object(
           'atomic_apply', true,
           'source', 'gold.performance'
         ),
         error_message = null,
         finished_at = timezone('utc', now())
   where id = p_run_id;

  return jsonb_build_object(
    'run_id', p_run_id,
    'rows_staged', v_rows_staged,
    'rows_inserted', v_rows_inserted,
    'rows_updated', v_rows_updated,
    'rows_deleted', v_rows_deleted,
    'atomic_apply', true
  );
end;
$$;

revoke all on function public.apply_gold_performance_sync(uuid) from public, anon;
grant execute on function public.apply_gold_performance_sync(uuid)
  to authenticated, service_role;
