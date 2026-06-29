create or replace function public.get_home_kpis(
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
  gross_amount numeric(18, 2);
  gross_volume numeric(18, 4);
  gross_orders integer;
  gross_positivation integer;
  return_amount numeric(18, 2);
  return_volume numeric(18, 4);
  return_orders integer;
  return_positivation integer;
  distinct_products integer;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
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

  last_sales_updated_at := public.get_latest_sync_finished_at(
    array['oracle_sales_sync']
  );

  last_financial_updated_at := public.get_latest_sync_finished_at(
    array['oracle_billing_sync', 'oracle_returns_financial_sync']
  );

  if normalized_metric_source = 'venda' then
    select
      coalesce(round(sum(s.venda), 2), 0),
      coalesce(round(sum(s.volume), 4), 0),
      coalesce(count(distinct s.numped), 0),
      coalesce(count(distinct s.codcli), 0)
      into gross_amount, gross_volume, gross_orders, gross_positivation
    from public.app_sales_daily_snapshots s
    where s.sales_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then s.codusur = current_user_code
          when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
          else true
        end
      );
  else
    select
      coalesce(round(sum(f.faturamento), 2), 0),
      coalesce(round(sum(f.volume), 4), 0),
      coalesce(count(distinct f.numped), 0),
      coalesce(count(distinct f.codcli), 0)
      into gross_amount, gross_volume, gross_orders, gross_positivation
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then f.codusur = current_user_code
          when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
          else true
        end
      );
  end if;

  select
    coalesce(round(sum(f.faturamento), 2), 0),
    coalesce(round(sum(f.volume), 4), 0),
    coalesce(count(distinct f.numped), 0),
    coalesce(count(distinct f.codcli), 0)
    into return_amount, return_volume, return_orders, return_positivation
  from public.app_financial_snapshots f
  where f.snapshot_type = 'D'
    and f.snapshot_date between start_date and end_date
    and (
      case
        when current_profile_slug = 'vendedor' then f.codusur = current_user_code
        when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
        else true
      end
    );

  select coalesce(count(distinct soi.codprod), 0)
    into distinct_products
  from public.app_sales_order_items soi
  where soi.sales_date between start_date and end_date
    and (
      case
        when current_profile_slug = 'vendedor' then soi.codusur = current_user_code
        when current_profile_slug = 'supervisor' then soi.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then soi.codgerente = current_user_code
        else true
      end
    );

  return jsonb_build_object(
    'metric_source', normalized_metric_source,
    'gross_amount', coalesce(gross_amount, 0),
    'gross_volume', coalesce(gross_volume, 0),
    'gross_orders', coalesce(gross_orders, 0),
    'gross_positivation', coalesce(gross_positivation, 0),
    'return_amount', coalesce(return_amount, 0),
    'return_volume', coalesce(return_volume, 0),
    'return_orders', coalesce(return_orders, 0),
    'return_positivation', coalesce(return_positivation, 0),
    'distinct_products', coalesce(distinct_products, 0),
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz, text)
  to authenticated;
