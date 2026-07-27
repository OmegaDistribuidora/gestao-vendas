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
  v_reference_date date := coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date);
  v_month_start date := date_trunc('month', coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date))::date;
  v_month_end date := (date_trunc('month', coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date)) + interval '1 month - 1 day')::date;
  v_financial_source text;
  v_secondary_source text;
  v_remaining_days integer;
begin
  if v_profile not in ('vendedor', 'supervisor', 'coordenador')
     or v_owner = '' then
    return;
  end if;

  v_financial_source := case
    when v_profile in ('supervisor', 'coordenador') then 'faturamento'
    else 'venda'
  end;
  v_secondary_source := case
    when v_profile = 'coordenador' then 'faturamento'
    else 'venda'
  end;
  v_remaining_days := public.push_remaining_business_days(v_month_start, v_reference_date);

  return query
  with target_row as (
    select
      coalesce(max(t.meta_fin), 0)::numeric as target_fin,
      max(t.meta_pos)::numeric as target_pos,
      max(t.meta_sku)::numeric as target_sku
    from public.app_performance_targets t
    where t.profile_slug = v_profile
      and t.owner_code = v_owner
      and t.month_start = v_month_start
      and t.codfornec = '1'
  ),
  sales_month as (
    select
      coalesce(round(sum(s.venda), 2), 0)::numeric as amount,
      coalesce(count(distinct s.codcli), 0)::numeric as pos
    from public.app_sales_daily_snapshots s
    where s.sales_date between v_month_start and v_reference_date
      and (
        case
          when v_profile = 'vendedor' then s.codusur = v_owner
          when v_profile = 'supervisor' then s.codsupervisor = v_owner
          when v_profile = 'coordenador' then s.codgerente = v_owner
        end
      )
  ),
  sales_day as (
    select
      coalesce(round(sum(s.venda), 2), 0)::numeric as amount,
      coalesce(count(distinct s.codcli), 0)::numeric as pos
    from public.app_sales_daily_snapshots s
    where s.sales_date = v_reference_date
      and (
        case
          when v_profile = 'vendedor' then s.codusur = v_owner
          when v_profile = 'supervisor' then s.codsupervisor = v_owner
          when v_profile = 'coordenador' then s.codgerente = v_owner
        end
      )
  ),
  financial_month as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date between v_month_start and v_reference_date
      and (
        case
          when v_profile = 'vendedor' then f.codusur = v_owner
          when v_profile = 'supervisor' then f.codsupervisor = v_owner
          when v_profile = 'coordenador' then f.codgerente = v_owner
        end
      )
  ),
  financial_day as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date = v_reference_date
      and (
        case
          when v_profile = 'vendedor' then f.codusur = v_owner
          when v_profile = 'supervisor' then f.codsupervisor = v_owner
          when v_profile = 'coordenador' then f.codgerente = v_owner
        end
      )
  ),
  returns_month as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'D'
      and f.snapshot_date between v_month_start and v_reference_date
      and (
        case
          when v_profile = 'vendedor' then f.codusur = v_owner
          when v_profile = 'supervisor' then f.codsupervisor = v_owner
          when v_profile = 'coordenador' then f.codgerente = v_owner
        end
      )
  ),
  returns_day as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'D'
      and f.snapshot_date = v_reference_date
      and (
        case
          when v_profile = 'vendedor' then f.codusur = v_owner
          when v_profile = 'supervisor' then f.codsupervisor = v_owner
          when v_profile = 'coordenador' then f.codgerente = v_owner
        end
      )
  ),
  sku_month as (
    select coalesce(max(s.sku_count), 0)::numeric as value
    from public.app_performance_sku_monthly s
    where s.profile_slug = v_profile
      and s.owner_code = v_owner
      and s.month_start = v_month_start
      and s.codfornec = '1'
      and s.metric_source = v_secondary_source
  ),
  sku_day as (
    select coalesce(count(distinct nullif(soi.codprod, '')), 0)::numeric as value
    from public.app_sales_order_items soi
    where soi.sales_date = v_reference_date
      and (
        case
          when v_profile = 'vendedor' then soi.codusur = v_owner
          when v_profile = 'supervisor' then soi.codsupervisor = v_owner
          when v_profile = 'coordenador' then soi.codgerente = v_owner
        end
      )
  ),
  computed as (
    select
      tr.target_fin,
      tr.target_pos,
      tr.target_sku,
      case
        when v_financial_source = 'faturamento' then fm.amount
        else sm.amount
      end + rm.amount as financial_month_actual,
      sd.amount + rd.amount as financial_day_actual,
      case
        when v_secondary_source = 'faturamento' then fm.pos
        else sm.pos
      end as pos_month_actual,
      greatest(sd.pos - rd.pos, 0) as pos_day_actual,
      skm.value as sku_month_actual,
      skd.value as sku_day_actual
    from target_row tr
    cross join sales_month sm
    cross join sales_day sd
    cross join financial_month fm
    cross join financial_day fd
    cross join returns_month rm
    cross join returns_day rd
    cross join sku_month skm
    cross join sku_day skd
  ),
  metric_rows as (
    select
      'financial'::text as metric_key,
      'monthly'::text as period_key,
      v_month_start as period_start,
      v_month_end as period_end,
      financial_month_actual as actual_value,
      target_fin as target_value
    from computed
    where target_fin > 0

    union all

    select
      'financial',
      'daily',
      v_reference_date,
      v_reference_date,
      financial_day_actual,
      case
        when target_fin <= 0 or v_remaining_days <= 0 then null::numeric
        when target_fin - financial_month_actual <= 0 then 0::numeric
        else (target_fin - financial_month_actual) / v_remaining_days
      end
    from computed
    where target_fin > 0

    union all

    select
      case when coalesce(target_sku, 0) > 0 then 'sku' else 'positivation' end,
      'monthly',
      v_month_start,
      v_month_end,
      case when coalesce(target_sku, 0) > 0 then sku_month_actual else pos_month_actual end,
      case when coalesce(target_sku, 0) > 0 then target_sku else target_pos end
    from computed
    where coalesce(target_sku, 0) > 0 or coalesce(target_pos, 0) > 0

    union all

    select
      case when coalesce(target_sku, 0) > 0 then 'sku' else 'positivation' end,
      'daily',
      v_reference_date,
      v_reference_date,
      case when coalesce(target_sku, 0) > 0 then sku_day_actual else pos_day_actual end,
      case
        when v_remaining_days <= 0 then null::numeric
        when coalesce(target_sku, 0) > 0 and target_sku - sku_month_actual > 0
          then (target_sku - sku_month_actual) / v_remaining_days
        when coalesce(target_sku, 0) > 0 then 0::numeric
        when coalesce(target_pos, 0) > 0 and target_pos - pos_month_actual > 0
          then (target_pos - pos_month_actual) / v_remaining_days
        when coalesce(target_pos, 0) > 0 then 0::numeric
        else null::numeric
      end
    from computed
    where coalesce(target_sku, 0) > 0 or coalesce(target_pos, 0) > 0
  )
  select
    mr.metric_key,
    mr.period_key,
    mr.period_start,
    mr.period_end,
    coalesce(mr.actual_value, 0)::numeric,
    mr.target_value::numeric,
    case
      when coalesce(mr.target_value, 0) > 0
        then round((coalesce(mr.actual_value, 0) / mr.target_value) * 100, 2)
      else null::numeric
    end as progress_pct
  from metric_rows mr
  where coalesce(mr.target_value, 0) > 0;
end;
$$;

revoke all on function public.get_push_performance_metrics(text, text, date)
  from public;
grant execute on function public.get_push_performance_metrics(text, text, date)
  to service_role;
