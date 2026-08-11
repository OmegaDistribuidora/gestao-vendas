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
  v_month_end date := (date_trunc('month', v_reference_date) + interval '1 month - 1 day')::date;
  v_yesterday date := v_reference_date - 1;
  v_is_named_profile boolean;
  v_secondary_type text := 'positivation';
  v_remaining_days integer;
  v_month_target_fin numeric;
  v_month_actual_fin numeric;
  v_month_target_secondary numeric;
  v_month_actual_secondary numeric;
  v_prior_actual_fin numeric := 0;
  v_prior_actual_secondary numeric := 0;
  v_day_actual_fin numeric := 0;
  v_day_actual_secondary numeric := 0;
  v_day_target_fin numeric;
  v_day_target_secondary numeric;
begin
  if v_profile = '' or v_profile = 'sem_perfil' then
    return;
  end if;

  v_is_named_profile := v_profile in ('vendedor', 'supervisor', 'coordenador');
  if v_is_named_profile and v_owner = '' then
    return;
  end if;

  -- A meta e o realizado mensal sao oficiais da Gold. O financeiro mensal
  -- e liquido, exatamente como a apuracao de premio.
  if v_is_named_profile then
    select
      public.gold_number(g.payload, 'meta_financeira'),
      public.gold_number(g.payload, 'realizado_financeiro'),
      case when g.tipo_usuario ilike '%Redes%' then 'sku' else 'positivation' end,
      case when g.tipo_usuario ilike '%Redes%'
        then public.gold_number(g.payload, 'meta_sku')
        else public.gold_number(g.payload, 'meta_positivacao')
      end,
      case when g.tipo_usuario ilike '%Redes%'
        then public.gold_number(g.payload, 'realizado_sku')
        else public.gold_number(g.payload, 'realizado_positivacao')
      end
    into
      v_month_target_fin,
      v_month_actual_fin,
      v_secondary_type,
      v_month_target_secondary,
      v_month_actual_secondary
    from public.app_gold_performance g
    where g.competencia_data = v_month_start
      and g.tipo_performance = 'Geral'
      and lower(g.perfil_usuario) = v_profile
      and g.codigo_usuario = v_owner
    limit 1;
  else
    select
      sum(public.gold_number(g.payload, 'meta_financeira')),
      sum(public.gold_number(g.payload, 'realizado_financeiro')),
      sum(public.gold_number(g.payload, 'meta_positivacao')),
      sum(public.gold_number(g.payload, 'realizado_positivacao'))
    into
      v_month_target_fin,
      v_month_actual_fin,
      v_month_target_secondary,
      v_month_actual_secondary
    from public.app_gold_performance g
    where g.competencia_data = v_month_start
      and g.tipo_performance = 'Geral'
      and g.perfil_usuario = 'Coordenador';
    v_secondary_type := 'positivation';
  end if;

  if coalesce(v_month_target_fin, 0) <= 0 then
    return;
  end if;

  v_remaining_days := public.push_remaining_business_days(
    v_month_start,
    v_reference_date
  );

  -- O acompanhamento diario usa venda bruta. Devolucoes nao reduzem o
  -- realizado de hoje nem o realizado anterior usado para fixar a meta.
  select
    coalesce(sum(s.venda), 0),
    coalesce(count(distinct s.codcli), 0)
  into v_prior_actual_fin, v_prior_actual_secondary
  from public.app_sales_daily_snapshots s
  where s.sales_date between v_month_start and v_yesterday
    and (
      (not v_is_named_profile)
      or (v_profile = 'vendedor' and s.codusur = v_owner)
      or (v_profile = 'supervisor' and s.codsupervisor = v_owner)
      or (v_profile = 'coordenador' and s.codgerente = v_owner)
    );

  select
    coalesce(sum(s.venda), 0),
    coalesce(count(distinct s.codcli), 0)
  into v_day_actual_fin, v_day_actual_secondary
  from public.app_sales_daily_snapshots s
  where s.sales_date = v_reference_date
    and (
      (not v_is_named_profile)
      or (v_profile = 'vendedor' and s.codusur = v_owner)
      or (v_profile = 'supervisor' and s.codsupervisor = v_owner)
      or (v_profile = 'coordenador' and s.codgerente = v_owner)
    );

  if v_secondary_type = 'sku' then
    select coalesce(count(distinct nullif(soi.codprod, '')), 0)
      into v_prior_actual_secondary
    from public.app_sales_order_items soi
    where soi.sales_date between v_month_start and v_yesterday
      and (
        (v_profile = 'vendedor' and soi.codusur = v_owner)
        or (v_profile = 'supervisor' and soi.codsupervisor = v_owner)
        or (v_profile = 'coordenador' and soi.codgerente = v_owner)
      );

    select coalesce(count(distinct nullif(soi.codprod, '')), 0)
      into v_day_actual_secondary
    from public.app_sales_order_items soi
    where soi.sales_date = v_reference_date
      and (
        (v_profile = 'vendedor' and soi.codusur = v_owner)
        or (v_profile = 'supervisor' and soi.codsupervisor = v_owner)
        or (v_profile = 'coordenador' and soi.codgerente = v_owner)
      );
  end if;

  v_day_target_fin := case
    when v_remaining_days > 0 then
      greatest(v_month_target_fin - v_prior_actual_fin, 0) / v_remaining_days
    else null
  end;
  v_day_target_secondary := case
    when v_remaining_days > 0 and coalesce(v_month_target_secondary, 0) > 0 then
      greatest(v_month_target_secondary - v_prior_actual_secondary, 0) / v_remaining_days
    else null
  end;

  return query
  with metric_rows as (
    select
      'financial'::text as metric_key,
      'monthly'::text as period_key,
      v_month_start as period_start,
      v_month_end as period_end,
      coalesce(v_month_actual_fin, 0)::numeric as actual_value,
      v_month_target_fin::numeric as target_value

    union all

    select
      v_secondary_type,
      'monthly',
      v_month_start,
      v_month_end,
      coalesce(v_month_actual_secondary, 0),
      v_month_target_secondary
    where coalesce(v_month_target_secondary, 0) > 0

    union all

    select
      'financial',
      'daily',
      v_reference_date,
      v_reference_date,
      v_day_actual_fin,
      v_day_target_fin
    where coalesce(v_day_target_fin, 0) > 0

    union all

    select
      v_secondary_type,
      'daily',
      v_reference_date,
      v_reference_date,
      v_day_actual_secondary,
      v_day_target_secondary
    where coalesce(v_day_target_secondary, 0) > 0
  )
  select
    mr.metric_key,
    mr.period_key,
    mr.period_start,
    mr.period_end,
    mr.actual_value,
    mr.target_value,
    round((mr.actual_value / nullif(mr.target_value, 0)) * 100, 2)
  from metric_rows mr
  where coalesce(mr.target_value, 0) > 0;
end;
$$;

revoke all on function public.get_push_performance_metrics(text, text, date)
  from public;
grant execute on function public.get_push_performance_metrics(text, text, date)
  to service_role;

create or replace function public.evaluate_push_notifications_after_gold_sync(
  target_reference_date date default (timezone('America/Sao_Paulo', now()))::date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  return public.evaluate_push_notifications(
    target_reference_date,
    timezone('utc', now()) - interval '10 minutes',
    false
  );
end;
$$;

revoke all on function public.evaluate_push_notifications_after_gold_sync(date)
  from public;
grant execute on function public.evaluate_push_notifications_after_gold_sync(date)
  to authenticated;
