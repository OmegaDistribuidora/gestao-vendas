drop function if exists public.get_performance_overview(date);
drop function if exists public.get_performance_overview(date, text);

create or replace function public.get_performance_overview(
  target_month_start date default null,
  metric_source text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  resolved_month_start date;
  current_month_start date;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  sku_metric_source text;
  payload jsonb;
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

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  sku_metric_source := case
    when current_profile_slug = 'coordenador' then 'faturamento'
    else 'venda'
  end;

  select max(updated_at)
    into last_targets_updated_at
  from public.app_performance_targets t
  where t.profile_slug = current_profile_slug
    and t.owner_code = current_user_code;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots;

  select max(updated_at)
    into last_sku_updated_at
  from public.app_performance_sku_monthly s
  where s.profile_slug = current_profile_slug
    and s.owner_code = current_user_code
    and s.metric_source = sku_metric_source;

  if current_profile_slug not in ('vendedor', 'supervisor', 'coordenador') then
    return jsonb_build_object(
      'supported', false,
      'profile_slug', current_profile_slug,
      'selected_month_start', target_month_start,
      'last_targets_updated_at', last_targets_updated_at,
      'last_sales_updated_at', last_sales_updated_at,
      'last_financial_updated_at', last_financial_updated_at,
      'last_sku_updated_at', last_sku_updated_at,
      'available_months', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start;
  end if;

  with available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      max(coalesce(t.meta_fin, 0))::numeric(18, 2) as target_fin,
      max(t.meta_pos) as target_pos,
      max(t.meta_sku) as target_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and resolved_month_start is not null
      and t.month_start = resolved_month_start
    group by
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end
  ),
  resolved_targets as (
    select
      t.*,
      case
        when current_profile_slug = 'coordenador' then 'faturamento'
        when current_profile_slug = 'supervisor' and t.codfornec = '1' then 'faturamento'
        else 'venda'
      end as financial_metric_source,
      case
        when current_profile_slug = 'coordenador' then 'faturamento'
        else 'venda'
      end as secondary_metric_source
    from targets t
  ),
  sales_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        s.codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  financial_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        f.codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  return_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as return_amount
    from (
      select
        f.codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.metric_source,
      s.sku_count
    from public.app_performance_sku_monthly s
    where s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.financial_metric_source,
      t.secondary_metric_source,
      t.target_fin,
      round(
        coalesce(
          case
            when t.financial_metric_source = 'faturamento' then fa.actual_fin
            else sa.actual_fin
          end,
          0
        ) + coalesce(ra.return_amount, 0),
        2
      )::numeric(18, 2) as actual_fin,
      t.target_pos,
      coalesce(
        case
          when t.secondary_metric_source = 'faturamento' then fa.actual_pos
          else sa.actual_pos
        end,
        0
      ) as actual_pos,
      t.target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when coalesce(t.target_sku, 0) > 0 then 'sku'
        when coalesce(t.target_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from resolved_targets t
    left join sales_actuals sa on sa.codfornec = t.codfornec
    left join financial_actuals fa on fa.codfornec = t.codfornec
    left join return_actuals ra on ra.codfornec = t.codfornec
    left join sku_actuals sk
      on sk.codfornec = t.codfornec
     and sk.metric_source = t.secondary_metric_source
  ),
  computed_items as (
    select
      item.codfornec,
      item.supplier_name,
      item.financial_metric_source,
      item.secondary_metric_source,
      item.target_fin,
      item.actual_fin,
      case
        when item.target_fin > 0
          then round((item.actual_fin / item.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      item.target_pos,
      item.actual_pos,
      case
        when coalesce(item.target_pos, 0) > 0
          then round((item.actual_pos::numeric / item.target_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      item.target_sku,
      item.actual_sku,
      case
        when coalesce(item.target_sku, 0) > 0
          then round((item.actual_sku::numeric / item.target_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      item.secondary_metric_type
    from merged_items item
  )
  select jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'financial_metric_source', item.financial_metric_source,
          'secondary_metric_source', item.secondary_metric_source,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from computed_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_performance_overview(date, text) to authenticated;
