-- Enrich the existing financial flow without changing the legacy columns.
-- Only the supplier analysis in billing mode consumes the adjusted fields.

alter table public.app_financial_snapshots
  add column if not exists original_order_date date,
  add column if not exists supplier_main_code text,
  add column if not exists adjusted_billing_amount numeric(18, 2);

alter table public.etl_stg_financial_snapshots
  add column if not exists original_order_date date,
  add column if not exists supplier_main_code text,
  add column if not exists adjusted_billing_amount numeric(18, 2);

-- Safe fallbacks until the reconciliation load fills the exact Oracle values.
update public.app_financial_snapshots
set original_order_date = coalesce(original_order_date, snapshot_date),
    supplier_main_code = coalesce(supplier_main_code, codfornec),
    adjusted_billing_amount = coalesce(adjusted_billing_amount, faturamento)
where original_order_date is null
   or supplier_main_code is null
   or adjusted_billing_amount is null;

create index if not exists idx_app_financial_snapshots_original_order
  on public.app_financial_snapshots (
    snapshot_type,
    original_order_date,
    numped,
    supplier_main_code
  );

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
  select * into v_run
  from public.etl_sync_runs
  where id = p_run_id;

  if not found then
    raise exception 'Sync run not found.';
  end if;

  select count(*) into v_rows_staged
  from public.etl_stg_financial_snapshots s
  where s.run_id = p_run_id;

  if v_rows_staged > 0 then
    select count(*) into v_rows_inserted
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

    select count(*) into v_rows_updated
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
        or (
          s.original_order_date is not null
          and t.original_order_date is distinct from s.original_order_date
        )
        or (
          s.supplier_main_code is not null
          and t.supplier_main_code is distinct from s.supplier_main_code
        )
        or (
          s.adjusted_billing_amount is not null
          and t.adjusted_billing_amount is distinct from s.adjusted_billing_amount
        )
      );

    select count(*) into v_rows_deleted
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
      original_order_date,
      supplier_main_code,
      faturamento,
      adjusted_billing_amount,
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
      coalesce(s.original_order_date, s.snapshot_date),
      coalesce(s.supplier_main_code, s.codfornec),
      s.faturamento,
      coalesce(s.adjusted_billing_amount, s.faturamento),
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
          original_order_date = excluded.original_order_date,
          supplier_main_code = excluded.supplier_main_code,
          faturamento = excluded.faturamento,
          adjusted_billing_amount = excluded.adjusted_billing_amount,
          volume = excluded.volume,
          custo = excluded.custo,
          lucro = excluded.lucro,
          mix = excluded.mix,
          imported_at = excluded.imported_at
    where public.app_financial_snapshots.codsupervisor is distinct from excluded.codsupervisor
       or public.app_financial_snapshots.codgerente is distinct from excluded.codgerente
       or public.app_financial_snapshots.original_order_date is distinct from excluded.original_order_date
       or public.app_financial_snapshots.supplier_main_code is distinct from excluded.supplier_main_code
       or public.app_financial_snapshots.faturamento is distinct from excluded.faturamento
       or public.app_financial_snapshots.adjusted_billing_amount is distinct from excluded.adjusted_billing_amount
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

grant execute on function public.apply_financial_sync(uuid)
  to authenticated, service_role;

-- Preserve all existing Venda behavior. Only Faturamento reads the adjusted
-- monetary amount and the table-driven principal supplier code.
create or replace function public.get_supplier_analysis_effective_balances(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  normalized_metric_source text;
  payload jsonb;
  last_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');
  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  last_updated_at := public.get_consistent_sync_finished_at(
    case
      when normalized_metric_source = 'venda' then
        array['oracle_sales_sync', 'oracle_returns_financial_sync']
      else
        array['oracle_billing_sync', 'oracle_returns_financial_sync']
    end
  );

  with gross_rows as (
    select
      s.codfornec,
      coalesce(sp.supplier_name, s.codfornec) as supplier_name,
      s.numped,
      s.codcli,
      s.codusur,
      s.venda::numeric as gross_amount,
      s.volume::numeric as gross_volume
    from public.app_sales_daily_snapshots s
    left join public.app_suppliers sp on sp.codfornec = s.codfornec
    where normalized_metric_source = 'venda'
      and s.sales_date between start_date and end_date
      and case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        when current_profile_slug = 'gerencia' then s.codgerente = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
        else true
      end

    union all

    select
      coalesce(f.supplier_main_code, f.codfornec) as codfornec,
      coalesce(
        sp.supplier_name,
        coalesce(f.supplier_main_code, f.codfornec)
      ) as supplier_name,
      f.numped,
      f.codcli,
      f.codusur,
      coalesce(f.adjusted_billing_amount, f.faturamento)::numeric as gross_amount,
      f.volume::numeric as gross_volume
    from public.app_financial_snapshots f
    left join public.app_suppliers sp
      on sp.codfornec = coalesce(f.supplier_main_code, f.codfornec)
    where normalized_metric_source = 'faturamento'
      and f.snapshot_type = 'F'
      and f.snapshot_date between start_date and end_date
      and case
        when current_profile_slug = 'vendedor' then f.codusur = current_user_code
        when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
        when current_profile_slug = 'gerencia' then f.codgerente = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
        else true
      end
  ),
  gross_orders as (
    select
      codfornec,
      max(supplier_name) as supplier_name,
      numped,
      codcli,
      codusur,
      sum(gross_amount) as gross_amount,
      sum(gross_volume) as gross_volume
    from gross_rows
    group by codfornec, numped, codcli, codusur
  ),
  return_orders as (
    select
      g.codfornec,
      g.numped,
      g.codcli,
      g.codusur,
      coalesce(sum(
        case
          when normalized_metric_source = 'faturamento' then
            coalesce(d.adjusted_billing_amount, d.faturamento)
          else d.faturamento
        end
      ), 0)::numeric as return_amount,
      coalesce(sum(d.volume), 0)::numeric as return_volume
    from gross_orders g
    left join public.app_financial_snapshots d
      on d.snapshot_type = 'D'
     and d.numped = g.numped
     and d.codcli = g.codcli
     and d.codusur = g.codusur
     and case
       when normalized_metric_source = 'faturamento' then
         coalesce(d.supplier_main_code, d.codfornec) = g.codfornec
       else d.codfornec = g.codfornec
     end
    group by g.codfornec, g.numped, g.codcli, g.codusur
  ),
  balances as (
    select
      g.codfornec,
      g.supplier_name,
      g.numped,
      g.codcli,
      g.codusur,
      g.gross_amount,
      r.return_amount,
      g.gross_volume,
      r.return_volume,
      g.gross_amount + r.return_amount as net_amount,
      g.gross_volume + r.return_volume as net_volume
    from gross_orders g
    join return_orders r
      on r.codfornec = g.codfornec
     and r.numped = g.numped
     and r.codcli = g.codcli
     and r.codusur = g.codusur
  ),
  supplier_orders as (
    select
      codfornec,
      max(supplier_name) as supplier_name,
      round(sum(gross_amount), 2) as gross_amount,
      round(sum(return_amount), 2) as return_amount,
      round(sum(gross_volume), 4) as gross_volume,
      round(sum(return_volume), 4) as return_volume,
      count(distinct numped) as gross_orders,
      count(distinct numped) filter (where return_amount <> 0) as return_orders,
      count(distinct numped) filter (where net_amount > 0.01) as net_orders,
      count(distinct codcli) as gross_positivation,
      count(distinct codcli) filter (where return_amount <> 0) as return_positivation
    from balances
    group by codfornec
  ),
  supplier_clients as (
    select codfornec, codcli, sum(net_amount) as net_amount
    from balances
    group by codfornec, codcli
  ),
  supplier_net_clients as (
    select
      codfornec,
      count(*) filter (where net_amount > 0.01) as net_positivation
    from supplier_clients
    group by codfornec
  ),
  overall_orders as (
    select
      numped,
      sum(gross_amount) as gross_amount,
      sum(return_amount) as return_amount,
      sum(gross_volume) as gross_volume,
      sum(return_volume) as return_volume,
      sum(net_amount) as net_amount
    from balances
    group by numped
  ),
  overall_clients as (
    select
      codcli,
      sum(gross_amount) as gross_amount,
      sum(return_amount) as return_amount,
      sum(net_amount) as net_amount
    from balances
    group by codcli
  ),
  overall_metrics as (
    select
      round(coalesce(sum(gross_amount), 0), 2) as gross_amount,
      round(coalesce(sum(return_amount), 0), 2) as return_amount,
      round(coalesce(sum(gross_volume), 0), 4) as gross_volume,
      round(coalesce(sum(return_volume), 0), 4) as return_volume,
      count(distinct numped) as gross_orders,
      count(distinct numped) filter (where return_amount <> 0) as return_orders,
      count(distinct numped) filter (where net_amount > 0.01) as net_orders
    from overall_orders
  ),
  overall_client_metrics as (
    select
      count(*) as gross_positivation,
      count(*) filter (where return_amount <> 0) as return_positivation,
      count(*) filter (where net_amount > 0.01) as net_positivation
    from overall_clients
  )
  select jsonb_build_object(
    'metric_source', normalized_metric_source,
    'last_updated_at', last_updated_at,
    'overall', case
      when exists (select 1 from balances) then (
        select jsonb_build_object(
          'code', '__geral__',
          'supplier_name', 'Geral',
          'gross_amount', om.gross_amount,
          'return_amount', om.return_amount,
          'gross_volume', om.gross_volume,
          'return_volume', om.return_volume,
          'gross_orders', om.gross_orders,
          'return_orders', om.return_orders,
          'net_orders', om.net_orders,
          'gross_positivation', ocm.gross_positivation,
          'return_positivation', ocm.return_positivation,
          'net_positivation', ocm.net_positivation
        )
        from overall_metrics om
        cross join overall_client_metrics ocm
      )
      else null
    end,
    'suppliers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', so.codfornec,
          'supplier_name', so.supplier_name,
          'gross_amount', so.gross_amount,
          'return_amount', so.return_amount,
          'gross_volume', so.gross_volume,
          'return_volume', so.return_volume,
          'gross_orders', so.gross_orders,
          'return_orders', so.return_orders,
          'net_orders', so.net_orders,
          'gross_positivation', so.gross_positivation,
          'return_positivation', so.return_positivation,
          'net_positivation', snc.net_positivation
        )
        order by (so.gross_amount + so.return_amount) desc, so.supplier_name
      )
      from supplier_orders so
      join supplier_net_clients snc on snc.codfornec = so.codfornec
    ), '[]'::jsonb)
  ) into payload;

  return coalesce(payload, jsonb_build_object(
    'metric_source', normalized_metric_source,
    'last_updated_at', last_updated_at,
    'overall', null,
    'suppliers', '[]'::jsonb
  ));
end;
$$;

revoke all on function public.get_supplier_analysis_effective_balances(
  timestamptz,
  timestamptz,
  text
) from public, anon;
grant execute on function public.get_supplier_analysis_effective_balances(
  timestamptz,
  timestamptz,
  text
) to authenticated;

comment on function public.get_supplier_analysis_effective_balances(
  timestamptz,
  timestamptz,
  text
) is
  'Analise por fornecedor: Venda preservada; Faturamento usa valor ajustado e fornecedor principal, mantendo devolucoes vinculadas ao pedido original.';

