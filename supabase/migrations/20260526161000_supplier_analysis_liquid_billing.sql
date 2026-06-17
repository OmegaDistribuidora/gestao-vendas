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

  if normalized_metric_source = 'venda' then
    last_updated_at := public.get_latest_sync_finished_at(array['oracle_sales_sync']);

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
            'return_amount', 0,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
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
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  else
    last_updated_at := public.get_latest_sync_finished_at(
      array['oracle_billing_sync', 'oracle_returns_financial_sync']
    );

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
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by (bucket.gross_amount + bucket.return_amount) desc, bucket.supplier_name
        )
        from (
          select
            f.codfornec,
            coalesce(sp.supplier_name, f.codfornec) as supplier_name,
            round(coalesce(sum(f.faturamento) filter (where f.snapshot_type = 'F'), 0), 2) as gross_amount,
            round(coalesce(sum(f.faturamento) filter (where f.snapshot_type = 'D'), 0), 2) as return_amount,
            round(coalesce(sum(f.volume) filter (where f.snapshot_type = 'F'), 0), 4) as gross_volume,
            count(distinct f.numped) filter (where f.snapshot_type = 'F') as gross_orders,
            count(distinct f.codcli) filter (where f.snapshot_type = 'F') as gross_positivation
          from public.app_financial_snapshots f
          left join public.app_suppliers sp on sp.codfornec = f.codfornec
          where f.snapshot_type in ('F', 'D')
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
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  end if;

  return payload;
end;
$$;
