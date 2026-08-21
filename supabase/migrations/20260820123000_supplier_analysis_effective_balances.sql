create index if not exists idx_app_financial_snapshots_type_order_scope
  on public.app_financial_snapshots (
    snapshot_type,
    numped,
    codcli,
    codusur,
    codfornec
  );

create or replace function public.get_consistent_sync_finished_at(
  job_names text[]
)
returns timestamptz
language sql
security definer
set search_path = public
as $$
  with requested as (
    select distinct unnest(job_names) as job_name
  ),
  latest_by_job as (
    select
      requested.job_name,
      max(r.finished_at) as finished_at
    from requested
    left join public.etl_sync_runs r
      on r.job_name = requested.job_name
     and r.status = 'applied'
    group by requested.job_name
  )
  select case
    when count(*) = count(finished_at) then min(finished_at)
    else null
  end
  from latest_by_job
$$;

grant execute on function public.get_consistent_sync_finished_at(text[])
  to authenticated, service_role;

create or replace function public.get_supplier_analysis(
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
        else true
      end

    union all

    select
      f.codfornec,
      coalesce(sp.supplier_name, f.codfornec) as supplier_name,
      f.numped,
      f.codcli,
      f.codusur,
      f.faturamento::numeric as gross_amount,
      f.volume::numeric as gross_volume
    from public.app_financial_snapshots f
    left join public.app_suppliers sp on sp.codfornec = f.codfornec
    where normalized_metric_source = 'faturamento'
      and f.snapshot_type = 'F'
      and f.snapshot_date between start_date and end_date
      and case
        when current_profile_slug = 'vendedor' then f.codusur = current_user_code
        when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
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
      coalesce(sum(d.faturamento), 0)::numeric as return_amount,
      coalesce(sum(d.volume), 0)::numeric as return_volume
    from gross_orders g
    left join public.app_financial_snapshots d
      on d.snapshot_type = 'D'
     and d.numped = g.numped
     and d.codcli = g.codcli
     and d.codusur = g.codusur
     and d.codfornec = g.codfornec
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
    select
      codfornec,
      codcli,
      sum(net_amount) as net_amount
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

grant execute on function public.get_supplier_analysis(timestamptz, timestamptz, text)
  to authenticated;

comment on function public.get_supplier_analysis(timestamptz, timestamptz, text) is
  'Analise por fornecedor com devolucoes atribuidas ao pedido original e pedidos/clientes contados apenas quando o saldo permanece positivo.';
