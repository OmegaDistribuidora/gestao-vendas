create table if not exists public.etl_sync_runs (
  id uuid primary key default gen_random_uuid(),
  job_name text not null,
  target_name text not null,
  scope_type text not null check (scope_type in ('fast', 'reconcile', 'manual')),
  window_start date not null,
  window_end date not null,
  status text not null default 'running' check (status in ('running', 'applied', 'failed')),
  rows_staged integer not null default 0,
  rows_inserted integer not null default 0,
  rows_updated integer not null default 0,
  rows_deleted integer not null default 0,
  notes jsonb not null default '{}'::jsonb,
  error_message text,
  started_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz
);

create index if not exists idx_etl_sync_runs_job_started_at
  on public.etl_sync_runs (job_name, started_at desc);

create index if not exists idx_etl_sync_runs_target_started_at
  on public.etl_sync_runs (target_name, started_at desc);

grant select, insert, update, delete on public.etl_sync_runs to authenticated, service_role;

alter table public.etl_sync_runs enable row level security;

drop policy if exists "etl_sync_runs_admin_manage" on public.etl_sync_runs;
create policy "etl_sync_runs_admin_manage"
on public.etl_sync_runs
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create unlogged table if not exists public.etl_stg_sales_daily_snapshots (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  sales_date date not null,
  numped text not null,
  codcli text not null,
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  venda numeric not null default 0,
  volume numeric not null default 0,
  imported_at timestamptz not null,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, sales_date, numped, codcli, codusur, codfornec)
);

grant select, insert, delete on public.etl_stg_sales_daily_snapshots to authenticated, service_role;

alter table public.etl_stg_sales_daily_snapshots enable row level security;

drop policy if exists "etl_stg_sales_daily_snapshots_admin_manage" on public.etl_stg_sales_daily_snapshots;
create policy "etl_stg_sales_daily_snapshots_admin_manage"
on public.etl_stg_sales_daily_snapshots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create unlogged table if not exists public.etl_stg_financial_snapshots (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  snapshot_type text not null check (snapshot_type in ('F', 'D')),
  snapshot_date date not null,
  numped text not null,
  codcli text not null,
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  faturamento numeric(18, 2) not null default 0,
  volume numeric(18, 4) not null default 0,
  custo numeric(18, 2) not null default 0,
  lucro numeric(18, 2) not null default 0,
  mix numeric(18, 2) not null default 0,
  imported_at timestamptz not null,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, snapshot_type, snapshot_date, numped, codcli, codusur, codfornec)
);

grant select, insert, delete on public.etl_stg_financial_snapshots to authenticated, service_role;

alter table public.etl_stg_financial_snapshots enable row level security;

drop policy if exists "etl_stg_financial_snapshots_admin_manage" on public.etl_stg_financial_snapshots;
create policy "etl_stg_financial_snapshots_admin_manage"
on public.etl_stg_financial_snapshots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create unlogged table if not exists public.etl_stg_return_order_items (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  return_date date not null,
  numped text not null,
  codcli text not null,
  client_name text not null,
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  return_reason text not null,
  codprod text not null,
  product_name text not null,
  item_value numeric(18, 2) not null default 0,
  quantity numeric(18, 4) not null default 0,
  volume numeric(18, 4) not null default 0,
  imported_at timestamptz not null,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, return_date, numped, codprod, codfornec, codusur, return_reason)
);

grant select, insert, delete on public.etl_stg_return_order_items to authenticated, service_role;

alter table public.etl_stg_return_order_items enable row level security;

drop policy if exists "etl_stg_return_order_items_admin_manage" on public.etl_stg_return_order_items;
create policy "etl_stg_return_order_items_admin_manage"
on public.etl_stg_return_order_items
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.begin_sync_run(
  p_job_name text,
  p_target_name text,
  p_scope_type text,
  p_window_start date,
  p_window_end date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
begin
  if p_job_name is null or btrim(p_job_name) = '' then
    raise exception 'job_name is required.';
  end if;

  if p_target_name is null or btrim(p_target_name) = '' then
    raise exception 'target_name is required.';
  end if;

  if p_scope_type not in ('fast', 'reconcile', 'manual') then
    raise exception 'scope_type is invalid.';
  end if;

  if p_window_start is null or p_window_end is null or p_window_start > p_window_end then
    raise exception 'Invalid sync window.';
  end if;

  insert into public.etl_sync_runs (
    job_name,
    target_name,
    scope_type,
    window_start,
    window_end
  )
  values (
    btrim(p_job_name),
    btrim(p_target_name),
    p_scope_type,
    p_window_start,
    p_window_end
  )
  returning id into v_run_id;

  return v_run_id;
end;
$$;

grant execute on function public.begin_sync_run(text, text, text, date, date) to authenticated, service_role;

create or replace function public.set_sync_run_rows_staged(
  p_run_id uuid,
  p_rows_staged integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.etl_sync_runs
     set rows_staged = greatest(coalesce(p_rows_staged, 0), 0)
   where id = p_run_id;
end;
$$;

grant execute on function public.set_sync_run_rows_staged(uuid, integer) to authenticated, service_role;

create or replace function public.mark_sync_run_failed(
  p_run_id uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.etl_sync_runs
     set status = 'failed',
         error_message = nullif(left(coalesce(p_error_message, ''), 4000), ''),
         finished_at = timezone('utc', now())
   where id = p_run_id;
end;
$$;

grant execute on function public.mark_sync_run_failed(uuid, text) to authenticated, service_role;

create or replace function public.apply_sales_sync(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.etl_sync_runs%rowtype;
  v_rows_staged integer := 0;
  v_rows_inserted integer := 0;
  v_rows_updated integer := 0;
  v_rows_deleted integer := 0;
begin
  select *
    into v_run
  from public.etl_sync_runs
  where id = p_run_id;

  if not found then
    raise exception 'Sync run not found.';
  end if;

  select count(*)
    into v_rows_staged
  from public.etl_stg_sales_daily_snapshots s
  where s.run_id = p_run_id;

  if v_rows_staged > 0 then
    select count(*)
      into v_rows_inserted
    from public.etl_stg_sales_daily_snapshots s
    left join public.app_sales_daily_snapshots t
      on t.sales_date = s.sales_date
     and t.numped = s.numped
     and t.codcli = s.codcli
     and t.codusur = s.codusur
     and t.codfornec = s.codfornec
    where s.run_id = p_run_id
      and t.id is null;

    select count(*)
      into v_rows_updated
    from public.etl_stg_sales_daily_snapshots s
    join public.app_sales_daily_snapshots t
      on t.sales_date = s.sales_date
     and t.numped = s.numped
     and t.codcli = s.codcli
     and t.codusur = s.codusur
     and t.codfornec = s.codfornec
    where s.run_id = p_run_id
      and (
        t.codsupervisor is distinct from s.codsupervisor
        or t.codgerente is distinct from s.codgerente
        or t.venda is distinct from s.venda
        or t.volume is distinct from s.volume
      );

    select count(*)
      into v_rows_deleted
    from public.app_sales_daily_snapshots t
    where t.sales_date between v_run.window_start and v_run.window_end
      and not exists (
        select 1
        from public.etl_stg_sales_daily_snapshots s
        where s.run_id = p_run_id
          and s.sales_date = t.sales_date
          and s.numped = t.numped
          and s.codcli = t.codcli
          and s.codusur = t.codusur
          and s.codfornec = t.codfornec
      );

    delete from public.app_sales_daily_snapshots t
    where t.sales_date between v_run.window_start and v_run.window_end
      and not exists (
        select 1
        from public.etl_stg_sales_daily_snapshots s
        where s.run_id = p_run_id
          and s.sales_date = t.sales_date
          and s.numped = t.numped
          and s.codcli = t.codcli
          and s.codusur = t.codusur
          and s.codfornec = t.codfornec
      );

    insert into public.app_sales_daily_snapshots (
      sales_date,
      numped,
      codcli,
      codusur,
      codsupervisor,
      codgerente,
      codfornec,
      venda,
      volume,
      imported_at
    )
    select
      s.sales_date,
      s.numped,
      s.codcli,
      s.codusur,
      s.codsupervisor,
      s.codgerente,
      s.codfornec,
      s.venda,
      s.volume,
      s.imported_at
    from public.etl_stg_sales_daily_snapshots s
    where s.run_id = p_run_id
    on conflict (sales_date, numped, codcli, codusur, codfornec)
    do update
      set codsupervisor = excluded.codsupervisor,
          codgerente = excluded.codgerente,
          venda = excluded.venda,
          volume = excluded.volume,
          imported_at = excluded.imported_at
    where public.app_sales_daily_snapshots.codsupervisor is distinct from excluded.codsupervisor
       or public.app_sales_daily_snapshots.codgerente is distinct from excluded.codgerente
       or public.app_sales_daily_snapshots.venda is distinct from excluded.venda
       or public.app_sales_daily_snapshots.volume is distinct from excluded.volume;
  end if;

  delete from public.etl_stg_sales_daily_snapshots
  where run_id = p_run_id;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_rows_staged,
         rows_inserted = v_rows_inserted,
         rows_updated = v_rows_updated,
         rows_deleted = v_rows_deleted,
         finished_at = timezone('utc', now()),
         error_message = null
   where id = p_run_id;

  return jsonb_build_object(
    'rows_staged', v_rows_staged,
    'rows_inserted', v_rows_inserted,
    'rows_updated', v_rows_updated,
    'rows_deleted', v_rows_deleted
  );
end;
$$;

grant execute on function public.apply_sales_sync(uuid) to authenticated, service_role;

create or replace function public.apply_financial_sync(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.etl_sync_runs%rowtype;
  v_rows_staged integer := 0;
  v_rows_inserted integer := 0;
  v_rows_updated integer := 0;
  v_rows_deleted integer := 0;
begin
  select *
    into v_run
  from public.etl_sync_runs
  where id = p_run_id;

  if not found then
    raise exception 'Sync run not found.';
  end if;

  select count(*)
    into v_rows_staged
  from public.etl_stg_financial_snapshots s
  where s.run_id = p_run_id;

  if v_rows_staged > 0 then
    select count(*)
      into v_rows_inserted
    from public.etl_stg_financial_snapshots s
    left join public.app_financial_snapshots t
      on t.snapshot_type = s.snapshot_type
     and t.snapshot_date = s.snapshot_date
     and t.numped = s.numped
     and t.codcli = s.codcli
     and t.codusur = s.codusur
     and t.codfornec = s.codfornec
    where s.run_id = p_run_id
      and t.id is null;

    select count(*)
      into v_rows_updated
    from public.etl_stg_financial_snapshots s
    join public.app_financial_snapshots t
      on t.snapshot_type = s.snapshot_type
     and t.snapshot_date = s.snapshot_date
     and t.numped = s.numped
     and t.codcli = s.codcli
     and t.codusur = s.codusur
     and t.codfornec = s.codfornec
    where s.run_id = p_run_id
      and (
        t.codsupervisor is distinct from s.codsupervisor
        or t.codgerente is distinct from s.codgerente
        or t.faturamento is distinct from s.faturamento
        or t.volume is distinct from s.volume
        or t.custo is distinct from s.custo
        or t.lucro is distinct from s.lucro
        or t.mix is distinct from s.mix
      );

    select count(*)
      into v_rows_deleted
    from public.app_financial_snapshots t
    where t.snapshot_date between v_run.window_start and v_run.window_end
      and exists (
        select 1
        from public.etl_stg_financial_snapshots scoped
        where scoped.run_id = p_run_id
          and scoped.snapshot_type = t.snapshot_type
      )
      and not exists (
        select 1
        from public.etl_stg_financial_snapshots s
        where s.run_id = p_run_id
          and s.snapshot_type = t.snapshot_type
          and s.snapshot_date = t.snapshot_date
          and s.numped = t.numped
          and s.codcli = t.codcli
          and s.codusur = t.codusur
          and s.codfornec = t.codfornec
      );

    delete from public.app_financial_snapshots t
    where t.snapshot_date between v_run.window_start and v_run.window_end
      and exists (
        select 1
        from public.etl_stg_financial_snapshots scoped
        where scoped.run_id = p_run_id
          and scoped.snapshot_type = t.snapshot_type
      )
      and not exists (
        select 1
        from public.etl_stg_financial_snapshots s
        where s.run_id = p_run_id
          and s.snapshot_type = t.snapshot_type
          and s.snapshot_date = t.snapshot_date
          and s.numped = t.numped
          and s.codcli = t.codcli
          and s.codusur = t.codusur
          and s.codfornec = t.codfornec
      );

    insert into public.app_financial_snapshots (
      snapshot_type,
      snapshot_date,
      numped,
      codcli,
      codusur,
      codsupervisor,
      codgerente,
      codfornec,
      faturamento,
      volume,
      custo,
      lucro,
      mix,
      imported_at
    )
    select
      s.snapshot_type,
      s.snapshot_date,
      s.numped,
      s.codcli,
      s.codusur,
      s.codsupervisor,
      s.codgerente,
      s.codfornec,
      s.faturamento,
      s.volume,
      s.custo,
      s.lucro,
      s.mix,
      s.imported_at
    from public.etl_stg_financial_snapshots s
    where s.run_id = p_run_id
    on conflict (snapshot_type, snapshot_date, numped, codcli, codusur, codfornec)
    do update
      set codsupervisor = excluded.codsupervisor,
          codgerente = excluded.codgerente,
          faturamento = excluded.faturamento,
          volume = excluded.volume,
          custo = excluded.custo,
          lucro = excluded.lucro,
          mix = excluded.mix,
          imported_at = excluded.imported_at
    where public.app_financial_snapshots.codsupervisor is distinct from excluded.codsupervisor
       or public.app_financial_snapshots.codgerente is distinct from excluded.codgerente
       or public.app_financial_snapshots.faturamento is distinct from excluded.faturamento
       or public.app_financial_snapshots.volume is distinct from excluded.volume
       or public.app_financial_snapshots.custo is distinct from excluded.custo
       or public.app_financial_snapshots.lucro is distinct from excluded.lucro
       or public.app_financial_snapshots.mix is distinct from excluded.mix;
  end if;

  delete from public.etl_stg_financial_snapshots
  where run_id = p_run_id;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_rows_staged,
         rows_inserted = v_rows_inserted,
         rows_updated = v_rows_updated,
         rows_deleted = v_rows_deleted,
         finished_at = timezone('utc', now()),
         error_message = null
   where id = p_run_id;

  return jsonb_build_object(
    'rows_staged', v_rows_staged,
    'rows_inserted', v_rows_inserted,
    'rows_updated', v_rows_updated,
    'rows_deleted', v_rows_deleted
  );
end;
$$;

grant execute on function public.apply_financial_sync(uuid) to authenticated, service_role;

create or replace function public.apply_return_items_sync(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.etl_sync_runs%rowtype;
  v_rows_staged integer := 0;
  v_rows_inserted integer := 0;
  v_rows_updated integer := 0;
  v_rows_deleted integer := 0;
begin
  select *
    into v_run
  from public.etl_sync_runs
  where id = p_run_id;

  if not found then
    raise exception 'Sync run not found.';
  end if;

  select count(*)
    into v_rows_staged
  from public.etl_stg_return_order_items s
  where s.run_id = p_run_id;

  if v_rows_staged > 0 then
    select count(*)
      into v_rows_inserted
    from public.etl_stg_return_order_items s
    left join public.app_return_order_items t
      on t.return_date = s.return_date
     and t.numped = s.numped
     and t.codprod = s.codprod
     and t.codfornec = s.codfornec
     and t.codusur = s.codusur
     and t.return_reason = s.return_reason
    where s.run_id = p_run_id
      and t.id is null;

    select count(*)
      into v_rows_updated
    from public.etl_stg_return_order_items s
    join public.app_return_order_items t
      on t.return_date = s.return_date
     and t.numped = s.numped
     and t.codprod = s.codprod
     and t.codfornec = s.codfornec
     and t.codusur = s.codusur
     and t.return_reason = s.return_reason
    where s.run_id = p_run_id
      and (
        t.codcli is distinct from s.codcli
        or t.client_name is distinct from s.client_name
        or t.codsupervisor is distinct from s.codsupervisor
        or t.codgerente is distinct from s.codgerente
        or t.product_name is distinct from s.product_name
        or t.item_value is distinct from s.item_value
        or t.quantity is distinct from s.quantity
        or t.volume is distinct from s.volume
      );

    select count(*)
      into v_rows_deleted
    from public.app_return_order_items t
    where t.return_date between v_run.window_start and v_run.window_end
      and not exists (
        select 1
        from public.etl_stg_return_order_items s
        where s.run_id = p_run_id
          and s.return_date = t.return_date
          and s.numped = t.numped
          and s.codprod = t.codprod
          and s.codfornec = t.codfornec
          and s.codusur = t.codusur
          and s.return_reason = t.return_reason
      );

    delete from public.app_return_order_items t
    where t.return_date between v_run.window_start and v_run.window_end
      and not exists (
        select 1
        from public.etl_stg_return_order_items s
        where s.run_id = p_run_id
          and s.return_date = t.return_date
          and s.numped = t.numped
          and s.codprod = t.codprod
          and s.codfornec = t.codfornec
          and s.codusur = t.codusur
          and s.return_reason = t.return_reason
      );

    insert into public.app_return_order_items (
      return_date,
      numped,
      codcli,
      client_name,
      codusur,
      codsupervisor,
      codgerente,
      codfornec,
      return_reason,
      codprod,
      product_name,
      item_value,
      quantity,
      volume,
      imported_at
    )
    select
      s.return_date,
      s.numped,
      s.codcli,
      s.client_name,
      s.codusur,
      s.codsupervisor,
      s.codgerente,
      s.codfornec,
      s.return_reason,
      s.codprod,
      s.product_name,
      s.item_value,
      s.quantity,
      s.volume,
      s.imported_at
    from public.etl_stg_return_order_items s
    where s.run_id = p_run_id
    on conflict (return_date, numped, codprod, codfornec, codusur, return_reason)
    do update
      set codcli = excluded.codcli,
          client_name = excluded.client_name,
          codsupervisor = excluded.codsupervisor,
          codgerente = excluded.codgerente,
          product_name = excluded.product_name,
          item_value = excluded.item_value,
          quantity = excluded.quantity,
          volume = excluded.volume,
          imported_at = excluded.imported_at
    where public.app_return_order_items.codcli is distinct from excluded.codcli
       or public.app_return_order_items.client_name is distinct from excluded.client_name
       or public.app_return_order_items.codsupervisor is distinct from excluded.codsupervisor
       or public.app_return_order_items.codgerente is distinct from excluded.codgerente
       or public.app_return_order_items.product_name is distinct from excluded.product_name
       or public.app_return_order_items.item_value is distinct from excluded.item_value
       or public.app_return_order_items.quantity is distinct from excluded.quantity
       or public.app_return_order_items.volume is distinct from excluded.volume;
  end if;

  delete from public.etl_stg_return_order_items
  where run_id = p_run_id;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_rows_staged,
         rows_inserted = v_rows_inserted,
         rows_updated = v_rows_updated,
         rows_deleted = v_rows_deleted,
         finished_at = timezone('utc', now()),
         error_message = null
   where id = p_run_id;

  return jsonb_build_object(
    'rows_staged', v_rows_staged,
    'rows_inserted', v_rows_inserted,
    'rows_updated', v_rows_updated,
    'rows_deleted', v_rows_deleted
  );
end;
$$;

grant execute on function public.apply_return_items_sync(uuid) to authenticated, service_role;
