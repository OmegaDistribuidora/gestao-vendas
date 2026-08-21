alter function public.get_home_kpis_v2(timestamptz, timestamptz)
  rename to get_home_kpis_v2_daily_targets;

create or replace function public.get_home_kpis_v2(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  positive_customers jsonb;
begin
  payload := public.get_home_kpis_v2_daily_targets(window_start, window_end);
  positive_customers := public.get_home_positive_customers(window_start, window_end);

  return payload || jsonb_build_object(
    'daily_new_positivation',
    coalesce((positive_customers ->> 'total_new_customers')::integer, 0)
  );
end;
$$;

revoke all on function public.get_home_kpis_v2_daily_targets(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.get_home_kpis_v2_daily_targets(timestamptz, timestamptz)
  to authenticated;

revoke all on function public.get_home_kpis_v2(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.get_home_kpis_v2(timestamptz, timestamptz)
  to authenticated;

comment on function public.get_home_kpis_v2(timestamptz, timestamptz) is
  'KPIs da Home com meta diaria e realizado diario de positivacao baseado nos clientes novos do mes.';

alter function public.get_push_performance_metrics(text, text, date)
  rename to get_push_performance_metrics_gross_positivation;

create or replace function public.get_push_performance_metrics(
  target_profile_slug text,
  target_owner_code text,
  target_reference_date date default (timezone('America/Sao_Paulo', now()))::date
)
returns table (
  metric_key text,
  period_key text,
  period_start date,
  period_end date,
  actual_value numeric,
  target_value numeric,
  progress_pct numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile text := lower(btrim(coalesce(target_profile_slug, '')));
  v_owner text := btrim(coalesce(target_owner_code, ''));
  v_reference_date date := coalesce(
    target_reference_date,
    timezone('America/Sao_Paulo', now())::date
  );
  v_month_start date := date_trunc('month', v_reference_date)::date;
  v_yesterday date := v_reference_date - 1;
  v_is_named_profile boolean := v_profile in ('vendedor', 'supervisor', 'coordenador');
  v_day_new_positivation numeric := 0;
begin
  select count(distinct today.codcli)::numeric
    into v_day_new_positivation
  from public.app_sales_daily_snapshots today
  where today.sales_date = v_reference_date
    and (
      (not v_is_named_profile)
      or (v_profile = 'vendedor' and today.codusur = v_owner)
      or (v_profile = 'supervisor' and today.codsupervisor = v_owner)
      or (v_profile = 'coordenador' and today.codgerente = v_owner)
    )
    and not exists (
      select 1
      from public.app_sales_daily_snapshots prior
      where prior.codcli = today.codcli
        and prior.sales_date between v_month_start and v_yesterday
        and (
          (not v_is_named_profile)
          or (v_profile = 'vendedor' and prior.codusur = v_owner)
          or (v_profile = 'supervisor' and prior.codsupervisor = v_owner)
          or (v_profile = 'coordenador' and prior.codgerente = v_owner)
        )
    );

  return query
  with base_metrics as (
    select
      b.metric_key as source_metric_key,
      b.period_key as source_period_key,
      b.period_start as source_period_start,
      b.period_end as source_period_end,
      b.actual_value as source_actual_value,
      b.target_value as source_target_value
    from public.get_push_performance_metrics_gross_positivation(
      target_profile_slug,
      target_owner_code,
      target_reference_date
    ) b
  ), adjusted as (
    select
      b.source_metric_key,
      b.source_period_key,
      b.source_period_start,
      b.source_period_end,
      case
        when b.source_metric_key = 'positivation'
         and b.source_period_key = 'daily'
          then coalesce(v_day_new_positivation, 0)
        else b.source_actual_value
      end as adjusted_actual_value,
      b.source_target_value
    from base_metrics b
  )
  select
    a.source_metric_key,
    a.source_period_key,
    a.source_period_start,
    a.source_period_end,
    a.adjusted_actual_value,
    a.source_target_value,
    round(
      (a.adjusted_actual_value / nullif(a.source_target_value, 0)) * 100,
      2
    )
  from adjusted a;
end;
$$;

revoke all on function public.get_push_performance_metrics_gross_positivation(text, text, date)
  from public, anon, authenticated;
grant execute on function public.get_push_performance_metrics_gross_positivation(text, text, date)
  to service_role;

revoke all on function public.get_push_performance_metrics(text, text, date)
  from public, anon, authenticated;
grant execute on function public.get_push_performance_metrics(text, text, date)
  to service_role;

comment on function public.get_push_performance_metrics(text, text, date) is
  'Metricas de push: mensal pela Gold; financeiro e SKU diarios brutos; positivacao diaria somente com clientes novos do mes.';
