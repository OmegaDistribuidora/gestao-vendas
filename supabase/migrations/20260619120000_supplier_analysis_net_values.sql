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

  last_updated_at := public.get_latest_sync_finished_at(
    case
      when normalized_metric_source = 'venda' then
        array['oracle_sales_sync', 'oracle_returns_financial_sync']
      else
        array['oracle_billing_sync', 'oracle_returns_financial_sync']
    end
  );

  if normalized_metric_source = 'venda' then
    with gross as (
      select
        s.codfornec,
        coalesce(sp.supplier_name, s.codfornec) as supplier_name,
        round(sum(s.venda), 2) as gross_amount,
        round(sum(s.volume), 4) as gross_volume,
        count(distinct s.numped) as gross_orders,
        count(distinct s.codcli) as gross_positivation
      from public.app_sales_daily_snapshots s
      left join public.app_suppliers sp on sp.codfornec = s.codfornec
      where s.sales_date between start_date and end_date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else true
          end
        )
      group by s.codfornec, coalesce(sp.supplier_name, s.codfornec)
    ),
    return_rows as (
      select
        f.codfornec,
        coalesce(sp.supplier_name, f.codfornec) as supplier_name,
        round(sum(f.faturamento), 2) as return_amount,
        round(sum(f.volume), 4) as return_volume,
        count(distinct f.numped) as return_orders,
        count(distinct f.codcli) as return_positivation
      from public.app_financial_snapshots f
      left join public.app_suppliers sp on sp.codfornec = f.codfornec
      where f.snapshot_type = 'D'
        and f.snapshot_date between start_date and end_date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )
      group by f.codfornec, coalesce(sp.supplier_name, f.codfornec)
    ),
    bucket as (
      select
        coalesce(g.codfornec, r.codfornec) as codfornec,
        coalesce(g.supplier_name, r.supplier_name, g.codfornec, r.codfornec) as supplier_name,
        coalesce(g.gross_amount, 0) as gross_amount,
        coalesce(r.return_amount, 0) as return_amount,
        coalesce(g.gross_volume, 0) as gross_volume,
        coalesce(r.return_volume, 0) as return_volume,
        coalesce(g.gross_orders, 0) as gross_orders,
        coalesce(r.return_orders, 0) as return_orders,
        coalesce(g.gross_positivation, 0) as gross_positivation,
        coalesce(r.return_positivation, 0) as return_positivation
      from gross g
      full outer join return_rows r on r.codfornec = g.codfornec
    )
    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'return_amount', bucket.return_amount,
            'gross_volume', bucket.gross_volume,
            'return_volume', bucket.return_volume,
            'gross_orders', bucket.gross_orders,
            'return_orders', bucket.return_orders,
            'gross_positivation', bucket.gross_positivation,
            'return_positivation', bucket.return_positivation
          )
          order by (bucket.gross_amount + bucket.return_amount) desc, bucket.supplier_name
        )
        from bucket
      ), '[]'::jsonb)
    ) into payload;
  else
    with gross as (
      select
        f.codfornec,
        coalesce(sp.supplier_name, f.codfornec) as supplier_name,
        round(sum(f.faturamento), 2) as gross_amount,
        round(sum(f.volume), 4) as gross_volume,
        count(distinct f.numped) as gross_orders,
        count(distinct f.codcli) as gross_positivation
      from public.app_financial_snapshots f
      left join public.app_suppliers sp on sp.codfornec = f.codfornec
      where f.snapshot_type = 'F'
        and f.snapshot_date between start_date and end_date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )
      group by f.codfornec, coalesce(sp.supplier_name, f.codfornec)
    ),
    return_rows as (
      select
        f.codfornec,
        coalesce(sp.supplier_name, f.codfornec) as supplier_name,
        round(sum(f.faturamento), 2) as return_amount,
        round(sum(f.volume), 4) as return_volume,
        count(distinct f.numped) as return_orders,
        count(distinct f.codcli) as return_positivation
      from public.app_financial_snapshots f
      left join public.app_suppliers sp on sp.codfornec = f.codfornec
      where f.snapshot_type = 'D'
        and f.snapshot_date between start_date and end_date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )
      group by f.codfornec, coalesce(sp.supplier_name, f.codfornec)
    ),
    bucket as (
      select
        coalesce(g.codfornec, r.codfornec) as codfornec,
        coalesce(g.supplier_name, r.supplier_name, g.codfornec, r.codfornec) as supplier_name,
        coalesce(g.gross_amount, 0) as gross_amount,
        coalesce(r.return_amount, 0) as return_amount,
        coalesce(g.gross_volume, 0) as gross_volume,
        coalesce(r.return_volume, 0) as return_volume,
        coalesce(g.gross_orders, 0) as gross_orders,
        coalesce(r.return_orders, 0) as return_orders,
        coalesce(g.gross_positivation, 0) as gross_positivation,
        coalesce(r.return_positivation, 0) as return_positivation
      from gross g
      full outer join return_rows r on r.codfornec = g.codfornec
    )
    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'return_amount', bucket.return_amount,
            'gross_volume', bucket.gross_volume,
            'return_volume', bucket.return_volume,
            'gross_orders', bucket.gross_orders,
            'return_orders', bucket.return_orders,
            'gross_positivation', bucket.gross_positivation,
            'return_positivation', bucket.return_positivation
          )
          order by (bucket.gross_amount + bucket.return_amount) desc, bucket.supplier_name
        )
        from bucket
      ), '[]'::jsonb)
    ) into payload;
  end if;

  return coalesce(payload, jsonb_build_object(
    'metric_source', normalized_metric_source,
    'last_updated_at', last_updated_at,
    'suppliers', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_supplier_analysis(timestamptz, timestamptz, text) to authenticated;
