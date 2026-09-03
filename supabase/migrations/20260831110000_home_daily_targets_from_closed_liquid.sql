create or replace function public.get_home_closed_month_liquid_actuals(
  target_profile_slug text,
  target_owner_code text,
  target_reference_date date
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with parameters as (
    select
      lower(btrim(coalesce(target_profile_slug, ''))) as profile_slug,
      btrim(coalesce(target_owner_code, '')) as owner_code,
      date_trunc('month', target_reference_date)::date as month_start,
      target_reference_date - 1 as closed_through
  ),
  gross_orders as (
    select
      case
        when parameters.profile_slug in ('vendedor', 'supervisor', 'coordenador')
          then parameters.owner_code
        else coalesce(nullif(s.codgerente, ''), '__sem_coordenador__')
      end as scope_key,
      s.codfornec,
      s.numped,
      s.codcli,
      s.codusur,
      sum(s.venda)::numeric as gross_amount
    from public.app_sales_daily_snapshots s
    cross join parameters
    where s.sales_date between parameters.month_start and parameters.closed_through
      and case
        when parameters.profile_slug = 'vendedor' then s.codusur = parameters.owner_code
        when parameters.profile_slug = 'supervisor' then s.codsupervisor = parameters.owner_code
        when parameters.profile_slug = 'coordenador' then s.codgerente = parameters.owner_code
        else true
      end
    group by 1, s.codfornec, s.numped, s.codcli, s.codusur
  ),
  return_orders as (
    select
      g.scope_key,
      g.codfornec,
      g.numped,
      g.codcli,
      g.codusur,
      coalesce(sum(d.faturamento), 0)::numeric as return_amount
    from gross_orders g
    cross join parameters
    left join public.app_financial_snapshots d
      on d.snapshot_type = 'D'
     and d.numped = g.numped
     and d.codcli = g.codcli
     and d.codusur = g.codusur
     and d.codfornec = g.codfornec
     and d.snapshot_date <= parameters.closed_through
    group by g.scope_key, g.codfornec, g.numped, g.codcli, g.codusur
  ),
  order_balances as (
    select
      g.scope_key,
      g.codcli,
      g.gross_amount + r.return_amount as net_amount
    from gross_orders g
    join return_orders r
      on r.scope_key = g.scope_key
     and r.codfornec = g.codfornec
     and r.numped = g.numped
     and r.codcli = g.codcli
     and r.codusur = g.codusur
  ),
  client_balances as (
    select scope_key, codcli, sum(net_amount) as net_amount
    from order_balances
    group by scope_key, codcli
  ),
  gross_product_orders as (
    select
      case
        when parameters.profile_slug in ('vendedor', 'supervisor', 'coordenador')
          then parameters.owner_code
        else coalesce(nullif(soi.codgerente, ''), '__sem_coordenador__')
      end as scope_key,
      soi.codfornec,
      soi.numped,
      soi.codcli,
      soi.codusur,
      soi.codprod,
      sum(soi.quantity)::numeric as gross_quantity
    from public.app_sales_order_items soi
    cross join parameters
    where soi.sales_date between parameters.month_start and parameters.closed_through
      and case
        when parameters.profile_slug = 'vendedor' then soi.codusur = parameters.owner_code
        when parameters.profile_slug = 'supervisor' then soi.codsupervisor = parameters.owner_code
        when parameters.profile_slug = 'coordenador' then soi.codgerente = parameters.owner_code
        else true
      end
    group by 1, soi.codfornec, soi.numped, soi.codcli, soi.codusur, soi.codprod
  ),
  return_product_orders as (
    select
      g.scope_key,
      g.codfornec,
      g.numped,
      g.codcli,
      g.codusur,
      g.codprod,
      coalesce(sum(abs(ri.quantity)), 0)::numeric as return_quantity
    from gross_product_orders g
    cross join parameters
    left join public.app_return_order_items ri
      on ri.numped = g.numped
     and ri.codcli = g.codcli
     and ri.codusur = g.codusur
     and ri.codfornec = g.codfornec
     and ri.codprod = g.codprod
     and ri.return_date <= parameters.closed_through
    group by
      g.scope_key,
      g.codfornec,
      g.numped,
      g.codcli,
      g.codusur,
      g.codprod
  ),
  product_balances as (
    select
      g.scope_key,
      g.codprod,
      sum(g.gross_quantity - r.return_quantity) as net_quantity
    from gross_product_orders g
    join return_product_orders r
      on r.scope_key = g.scope_key
     and r.codfornec = g.codfornec
     and r.numped = g.numped
     and r.codcli = g.codcli
     and r.codusur = g.codusur
     and r.codprod = g.codprod
    group by g.scope_key, g.codprod
  )
  select jsonb_build_object(
    'financial', coalesce((select sum(net_amount) from order_balances), 0),
    'positivation', coalesce((
      select count(*)
      from client_balances
      where net_amount > 0.01
    ), 0),
    'sku', coalesce((
      select count(*)
      from product_balances
      where net_quantity > 0.0001
    ), 0),
    'closed_through', (select closed_through from parameters)
  );
$$;

revoke all on function public.get_home_closed_month_liquid_actuals(text, text, date)
  from public, anon, authenticated;
grant execute on function public.get_home_closed_month_liquid_actuals(text, text, date)
  to service_role;

comment on function public.get_home_closed_month_liquid_actuals(text, text, date) is
  'Realizado mensal fechado ate ontem, liquido de devolucoes, para fixar as metas diarias da Home e dos pushes.';

create or replace function public.get_home_kpis_v2_daily_targets(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  base jsonb;
  viewer_profile text;
  viewer_code text;
  reference_date date := date(window_start at time zone 'America/Sao_Paulo');
  month_start date;
  remaining_days integer;
  monthly_fin_target numeric;
  monthly_secondary_target numeric;
  prior_fin_actual numeric;
  prior_secondary_actual numeric;
  daily_fin_target numeric;
  daily_secondary_target numeric;
  secondary_type text := 'positivacao';
  gold_updated_at timestamptz;
  closed_actuals jsonb;
begin
  base := public.get_home_kpis(window_start, window_end, 'venda');
  month_start := date_trunc('month', reference_date)::date;
  remaining_days := public.push_remaining_business_days(month_start, reference_date);

  select coalesce(p.slug, 'sem_perfil'), u.code into viewer_profile, viewer_code
  from public.app_users u left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid() and u.is_active limit 1;

  if viewer_profile in ('vendedor', 'supervisor', 'coordenador') then
    select
      public.gold_number(g.payload, 'meta_financeira'),
      case when g.tipo_usuario ilike '%Redes%' then 'sku' else 'positivacao' end,
      case when g.tipo_usuario ilike '%Redes%'
        then public.gold_number(g.payload, 'meta_sku')
        else public.gold_number(g.payload, 'meta_positivacao') end,
      g.source_updated_at
    into monthly_fin_target, secondary_type, monthly_secondary_target, gold_updated_at
    from public.app_gold_performance g
    where g.competencia_data = month_start and g.tipo_performance = 'Geral'
      and lower(g.perfil_usuario) = viewer_profile and g.codigo_usuario = viewer_code
    limit 1;
  else
    select
      sum(public.gold_number(g.payload, 'meta_financeira')),
      'positivacao',
      sum(public.gold_number(g.payload, 'meta_positivacao')),
      max(g.source_updated_at)
    into monthly_fin_target, secondary_type, monthly_secondary_target, gold_updated_at
    from public.app_gold_performance g
    where g.competencia_data = month_start and g.tipo_performance = 'Geral'
      and g.perfil_usuario = 'Coordenador';
  end if;

  closed_actuals := public.get_home_closed_month_liquid_actuals(
    viewer_profile,
    viewer_code,
    reference_date
  );
  prior_fin_actual := coalesce((closed_actuals ->> 'financial')::numeric, 0);
  prior_secondary_actual := case
    when secondary_type = 'sku'
      then coalesce((closed_actuals ->> 'sku')::numeric, 0)
    else coalesce((closed_actuals ->> 'positivation')::numeric, 0)
  end;

  daily_fin_target := case when monthly_fin_target > 0 and remaining_days > 0
    then greatest(monthly_fin_target - prior_fin_actual, 0) / remaining_days else null end;
  daily_secondary_target := case when monthly_secondary_target > 0 and remaining_days > 0
    then greatest(monthly_secondary_target - prior_secondary_actual, 0) / remaining_days else null end;

  return base || jsonb_build_object(
    'daily_financial_target', daily_fin_target,
    'daily_secondary_target', daily_secondary_target,
    'secondary_metric_type', secondary_type,
    'monthly_financial_target', monthly_fin_target,
    'monthly_secondary_target', monthly_secondary_target,
    'gold_updated_at', gold_updated_at,
    'daily_targets_actual_basis', 'closed_liquid',
    'daily_targets_closed_through', closed_actuals ->> 'closed_through'
  );
end;
$$;

revoke all on function public.get_home_kpis_v2_daily_targets(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.get_home_kpis_v2_daily_targets(timestamptz, timestamptz)
  to authenticated;

comment on function public.get_home_kpis_v2_daily_targets(timestamptz, timestamptz) is
  'KPIs brutos da Home com metas diarias fixadas pelo realizado liquido dos dias encerrados.';

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
  v_remaining_days integer;
  v_closed_actuals jsonb;
  v_prior_financial numeric := 0;
  v_prior_positivation numeric := 0;
  v_prior_sku numeric := 0;
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

  v_remaining_days := public.push_remaining_business_days(
    v_month_start,
    v_reference_date
  );
  v_closed_actuals := public.get_home_closed_month_liquid_actuals(
    v_profile,
    v_owner,
    v_reference_date
  );
  v_prior_financial := coalesce((v_closed_actuals ->> 'financial')::numeric, 0);
  v_prior_positivation := coalesce((v_closed_actuals ->> 'positivation')::numeric, 0);
  v_prior_sku := coalesce((v_closed_actuals ->> 'sku')::numeric, 0);

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
  ), monthly_targets as (
    select
      b.source_metric_key,
      max(b.source_target_value) filter (
        where b.source_period_key = 'monthly'
      ) as monthly_target
    from base_metrics b
    group by b.source_metric_key
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
      case
        when b.source_period_key = 'daily'
         and v_remaining_days > 0
         and mt.monthly_target > 0
          then greatest(
            mt.monthly_target - case b.source_metric_key
              when 'financial' then v_prior_financial
              when 'positivation' then v_prior_positivation
              when 'sku' then v_prior_sku
              else 0
            end,
            0
          ) / v_remaining_days
        else b.source_target_value
      end as adjusted_target_value
    from base_metrics b
    left join monthly_targets mt
      on mt.source_metric_key = b.source_metric_key
  )
  select
    a.source_metric_key,
    a.source_period_key,
    a.source_period_start,
    a.source_period_end,
    a.adjusted_actual_value,
    a.adjusted_target_value,
    round(
      (a.adjusted_actual_value / nullif(a.adjusted_target_value, 0)) * 100,
      2
    )
  from adjusted a;
end;
$$;

revoke all on function public.get_push_performance_metrics(text, text, date)
  from public, anon, authenticated;
grant execute on function public.get_push_performance_metrics(text, text, date)
  to service_role;

comment on function public.get_push_performance_metrics(text, text, date) is
  'Metricas mensais pela Gold; metas diarias pelo fechamento liquido ate ontem; realizados diarios brutos e positivacao diaria de clientes novos.';
