drop function if exists public.get_performance_overview(date, text, text, text);

create or replace function public.get_performance_overview(
  target_month_start date,
  metric_source text,
  target_scope_profile_slug text,
  target_scope_owner_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_profile_slug text;
  requested_owner_code text;
  effective_profile_slug text;
  effective_owner_code text;
  aggregate_all_mode boolean := false;
  is_effective_named_profile boolean;
  resolved_month_start date;
  current_month_start date;
  normalized_metric_source text;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  sku_metric_source text;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));
  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  requested_profile_slug := nullif(
    lower(trim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code := nullif(trim(coalesce(target_scope_owner_code, '')), '');

  if viewer_profile_slug = 'vendedor' then
    effective_profile_slug := 'vendedor';
    effective_owner_code := viewer_user_code;
  elsif viewer_profile_slug = 'supervisor' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'supervisor';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'vendedor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'vendedor'
        and u.code = requested_owner_code
        and coalesce(u.supervisor_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'vendedor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de performance invalido para supervisor.';
    end if;
  elsif viewer_profile_slug = 'coordenador' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'coordenador';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'supervisor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'supervisor'
        and u.code = requested_owner_code
        and coalesce(u.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'supervisor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de performance invalido para coordenador.';
    end if;
  elsif viewer_profile_slug in ('admin', 'diretoria', 'outros') then
    if requested_profile_slug is null or requested_owner_code is null then
      aggregate_all_mode := true;
      effective_profile_slug := viewer_profile_slug;
      effective_owner_code := null;
    elsif requested_profile_slug in ('coordenador', 'supervisor', 'vendedor')
      and exists (
        select 1
        from public.app_users u
        join public.app_profiles p on p.id = u.profile_id
        where u.is_active = true
          and p.slug = requested_profile_slug
          and u.code = requested_owner_code
      ) then
      effective_profile_slug := requested_profile_slug;
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de performance invalido para o perfil atual.';
    end if;
  else
    aggregate_all_mode := true;
    effective_profile_slug := viewer_profile_slug;
    effective_owner_code := null;
  end if;

  is_effective_named_profile := effective_profile_slug in (
    'vendedor',
    'supervisor',
    'coordenador'
  );

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  sku_metric_source := case
    when effective_profile_slug = 'coordenador' then 'faturamento'
    else 'venda'
  end;

  if is_effective_named_profile then
    select max(updated_at)
      into last_targets_updated_at
    from public.app_performance_targets t
    where t.profile_slug = effective_profile_slug
      and t.owner_code = effective_owner_code;

    select max(updated_at)
      into last_sku_updated_at
    from public.app_performance_sku_monthly s
    where s.profile_slug = effective_profile_slug
      and s.owner_code = effective_owner_code
      and s.metric_source = sku_metric_source;
  else
    select max(updated_at)
      into last_targets_updated_at
    from public.app_performance_targets t
    where t.profile_slug = 'coordenador';

    last_sku_updated_at := null;
  end if;

  last_sales_updated_at := public.get_latest_sync_finished_at(
    array['oracle_sales_sync']
  );

  last_financial_updated_at := public.get_latest_sync_finished_at(
    array['oracle_billing_sync', 'oracle_returns_financial_sync']
  );

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.month_start <= current_month_start
      and (
        (is_effective_named_profile and t.profile_slug = effective_profile_slug and t.owner_code = effective_owner_code)
        or
        ((not is_effective_named_profile) and t.profile_slug = 'coordenador')
      );
  end if;

  with available_scope_rows as (
    select
      p.slug as profile_slug,
      u.code as owner_code,
      coalesce(nullif(btrim(u.display_name), ''), u.code) as display_name,
      trim(
        case
          when btrim(coalesce(u.code, '')) <> '' and btrim(coalesce(u.display_name, '')) <> ''
            then u.code || ' - ' || u.display_name
          when btrim(coalesce(u.display_name, '')) <> ''
            then u.display_name
          else u.code
        end
      ) as label
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.is_active = true
      and (
        (viewer_profile_slug = 'supervisor' and p.slug = 'vendedor' and coalesce(u.supervisor_code, '') = viewer_user_code)
        or
        (viewer_profile_slug = 'coordenador' and p.slug = 'supervisor' and coalesce(u.coordinator_code, '') = viewer_user_code)
        or
        (viewer_profile_slug in ('admin', 'diretoria', 'outros') and p.slug in ('coordenador', 'supervisor', 'vendedor'))
      )
  ),
  available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.month_start <= current_month_start
      and (
        (is_effective_named_profile and t.profile_slug = effective_profile_slug and t.owner_code = effective_owner_code)
        or
        ((not is_effective_named_profile) and t.profile_slug = 'coordenador')
      )
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      case
        when is_effective_named_profile then max(coalesce(t.meta_fin, 0))::numeric(18, 2)
        else coalesce(sum(coalesce(t.meta_fin, 0)), 0)::numeric(18, 2)
      end as target_fin,
      case
        when is_effective_named_profile then max(t.meta_pos)
        else sum(coalesce(t.meta_pos, 0))::integer
      end as target_pos,
      case
        when is_effective_named_profile then max(t.meta_sku)
        else null::integer
      end as target_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where resolved_month_start is not null
      and t.month_start = resolved_month_start
      and (
        (is_effective_named_profile and t.profile_slug = effective_profile_slug and t.owner_code = effective_owner_code)
        or
        ((not is_effective_named_profile) and t.profile_slug = 'coordenador')
      )
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
        when not is_effective_named_profile then normalized_metric_source
        when effective_profile_slug = 'coordenador' then 'faturamento'
        when effective_profile_slug = 'supervisor' and t.codfornec = '1' then 'faturamento'
        else 'venda'
      end as financial_metric_source,
      case
        when not is_effective_named_profile then normalized_metric_source
        when effective_profile_slug = 'coordenador' then 'faturamento'
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
            when effective_profile_slug = 'vendedor' then s.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then s.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then s.codgerente = effective_owner_code
            else true
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
            when effective_profile_slug = 'vendedor' then s.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then s.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then s.codgerente = effective_owner_code
            else true
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
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
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
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
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
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
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
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
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
    where is_effective_named_profile
      and s.profile_slug = effective_profile_slug
      and s.owner_code = effective_owner_code
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
        when not is_effective_named_profile and coalesce(t.target_pos, 0) > 0 then 'positivacao'
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
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_scopes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile_slug', scope.profile_slug,
          'owner_code', scope.owner_code,
          'display_name', scope.display_name,
          'label', scope.label
        )
        order by
          case scope.profile_slug
            when 'coordenador' then 1
            when 'supervisor' then 2
            when 'vendedor' then 3
            else 9
          end,
          scope.display_name,
          scope.owner_code
      )
      from available_scope_rows scope
    ), '[]'::jsonb),
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
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_scopes', '[]'::jsonb,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

create or replace function public.get_performance_overview(
  target_month_start date default null,
  metric_source text default 'venda'
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select public.get_performance_overview(
    target_month_start,
    metric_source,
    null,
    null
  );
$$;

grant execute on function public.get_performance_overview(date, text, text, text) to authenticated;
grant execute on function public.get_performance_overview(date, text) to authenticated;
