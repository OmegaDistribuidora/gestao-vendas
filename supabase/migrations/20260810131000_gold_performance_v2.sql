create table if not exists public.app_gold_performance (
  id_apuracao text primary key,
  competencia_data date not null,
  codigo_usuario text not null,
  perfil_usuario text not null,
  tipo_usuario text not null,
  codigo_supervisor integer,
  codigo_coordenador integer,
  tipo_performance text not null check (tipo_performance in ('Geral', 'Fornecedor')),
  codigo_fornecedor integer,
  fornecedor text,
  payload jsonb not null,
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  constraint app_gold_performance_scope_key unique
    (competencia_data, perfil_usuario, codigo_usuario, tipo_performance, codigo_fornecedor)
);

create index if not exists idx_app_gold_performance_month_scope
  on public.app_gold_performance (competencia_data, perfil_usuario, codigo_usuario);

create index if not exists idx_app_gold_performance_hierarchy
  on public.app_gold_performance (competencia_data, codigo_coordenador, codigo_supervisor);

alter table public.app_gold_performance enable row level security;

revoke all on table public.app_gold_performance from public, anon, authenticated;
grant select, insert, update, delete on table public.app_gold_performance to service_role;

create or replace function public.gold_number(data jsonb, field_name text)
returns numeric
language sql
immutable
as $$
  select case
    when data ->> field_name is null or btrim(data ->> field_name) = '' then null
    else (data ->> field_name)::numeric
  end;
$$;

create or replace function public.gold_metric(
  data jsonb,
  metric_key text,
  metric_label text,
  metric_format text,
  target_field text,
  actual_field text,
  progress_field text,
  prize_field text,
  possibility_field text,
  lower_is_better boolean default false
)
returns jsonb
language sql
immutable
as $$
  select case
    when public.gold_number(data, target_field) is null
     and public.gold_number(data, actual_field) is null then null
    else jsonb_strip_nulls(jsonb_build_object(
      'key', metric_key,
      'label', metric_label,
      'format', metric_format,
      'target', public.gold_number(data, target_field),
      'actual', public.gold_number(data, actual_field),
      'progress_pct', case
        when public.gold_number(data, progress_field) is null then null
        else public.gold_number(data, progress_field) * 100
      end,
      'prize', coalesce(public.gold_number(data, prize_field), 0),
      'possibility', coalesce(public.gold_number(data, possibility_field), 0),
      'lower_is_better', lower_is_better
    ))
  end;
$$;

create or replace function public.gold_metrics(data jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(metric order by sequence_number) filter (where metric is not null), '[]'::jsonb)
  from (values
    (1, public.gold_metric(data, 'financial', 'Venda líquida', 'currency', 'meta_financeira', 'realizado_financeiro', 'percentual_realizado_financeiro', 'premio_financeiro', 'possibilidade_financeiro')),
    (2, public.gold_metric(data, 'financial_15', 'Venda líquida até dia 15', 'currency', 'meta_financeira_ate_dia_15', 'realizado_financeiro_ate_dia_15', 'percentual_realizado_financeiro_ate_dia_15', 'premio_financeiro_ate_dia_15', 'possibilidade_financeiro_ate_dia_15')),
    (3, public.gold_metric(data, 'positivation', 'Positivação', 'integer', 'meta_positivacao', 'realizado_positivacao', 'percentual_realizado_positivacao', 'premio_positivacao', 'possibilidade_positivacao')),
    (4, public.gold_metric(data, 'sku', 'SKU', 'integer', 'meta_sku', 'realizado_sku', 'percentual_realizado_sku', 'premio_sku', 'possibilidade_sku')),
    (5, public.gold_metric(data, 'volume', 'Volume', 'decimal', 'meta_volume', 'realizado_volume', 'percentual_realizado_volume', 'premio_volume', 'possibilidade_volume')),
    (6, public.gold_metric(data, 'effectiveness', 'Efetividade', 'percent', 'meta_efetividade', 'realizado_efetividade', 'percentual_realizado_efetividade', 'premio_efetividade', 'possibilidade_efetividade')),
    (7, public.gold_metric(data, 'profitability', 'Lucratividade', 'percent', 'meta_lucratividade', 'realizado_lucratividade', 'percentual_realizado_lucratividade', 'premio_lucratividade', 'possibilidade_lucratividade')),
    (8, public.gold_metric(data, 'average_items', 'Média de itens', 'decimal', 'meta_media_itens', 'realizado_media_itens', 'percentual_realizado_media_itens', 'premio_media_itens', 'possibilidade_media_itens')),
    (9, public.gold_metric(data, 'delinquency', 'Inadimplência', 'percent', 'meta_percentual_inadimplencia', 'realizado_percentual_inadimplencia', 'percentual_da_meta_inadimplencia', 'premio_inadimplencia', 'possibilidade_inadimplencia', true))
  ) as metrics(sequence_number, metric);
$$;

create or replace function public.get_performance_overview_v2(
  target_month_start date default null,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile text;
  viewer_code text;
  selected_month date := date_trunc('month', coalesce(target_month_start, timezone('America/Sao_Paulo', now())::date))::date;
  requested_profile text := nullif(lower(btrim(coalesce(target_scope_profile_slug, ''))), '');
  requested_code text := nullif(btrim(coalesce(target_scope_owner_code, '')), '');
  effective_profile text;
  effective_code text;
  aggregate_company boolean := false;
  result_items jsonb;
  available_scopes jsonb;
  available_months jsonb;
  last_update timestamptz;
begin
  select coalesce(p.slug, 'sem_perfil'), u.code
    into viewer_profile, viewer_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid() and u.is_active
  limit 1;

  if viewer_profile is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  if selected_month < date '2026-08-01' then
    return public.get_performance_overview(
      selected_month,
      'venda',
      target_scope_profile_slug,
      target_scope_owner_code
    );
  end if;

  if viewer_profile = 'vendedor' then
    effective_profile := 'vendedor';
    effective_code := viewer_code;
  elsif viewer_profile = 'supervisor' then
    if requested_profile = 'vendedor' and exists (
      select 1 from public.app_gold_performance g
      where g.competencia_data = selected_month and g.tipo_performance = 'Geral'
        and g.perfil_usuario = 'Vendedor' and g.codigo_usuario = requested_code
        and g.codigo_supervisor::text = viewer_code
    ) then
      effective_profile := 'vendedor'; effective_code := requested_code;
    else
      effective_profile := 'supervisor'; effective_code := viewer_code;
    end if;
  elsif viewer_profile = 'coordenador' then
    if requested_profile in ('supervisor', 'vendedor') and exists (
      select 1 from public.app_gold_performance g
      where g.competencia_data = selected_month and g.tipo_performance = 'Geral'
        and lower(g.perfil_usuario) = requested_profile and g.codigo_usuario = requested_code
        and g.codigo_coordenador::text = viewer_code
    ) then
      effective_profile := requested_profile; effective_code := requested_code;
    else
      effective_profile := 'coordenador'; effective_code := viewer_code;
    end if;
  elsif viewer_profile <> 'sem_perfil' then
    if requested_profile in ('coordenador', 'supervisor', 'vendedor') and exists (
      select 1 from public.app_gold_performance g
      where g.competencia_data = selected_month and g.tipo_performance = 'Geral'
        and lower(g.perfil_usuario) = requested_profile and g.codigo_usuario = requested_code
    ) then
      effective_profile := requested_profile; effective_code := requested_code;
    else
      aggregate_company := true;
      effective_profile := viewer_profile;
      effective_code := null;
    end if;
  else
    return jsonb_build_object('supported', false, 'items', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_slug', lower(g.perfil_usuario),
    'owner_code', g.codigo_usuario,
    'display_name', coalesce(g.payload ->> 'nome_usuario', g.codigo_usuario),
    'label', g.codigo_usuario || ' - ' || coalesce(g.payload ->> 'nome_usuario', g.codigo_usuario)
  ) order by case g.perfil_usuario when 'Coordenador' then 1 when 'Supervisor' then 2 else 3 end, g.payload ->> 'nome_usuario'), '[]'::jsonb)
  into available_scopes
  from public.app_gold_performance g
  where g.competencia_data = selected_month and g.tipo_performance = 'Geral'
    and (
      (viewer_profile = 'supervisor' and g.perfil_usuario = 'Vendedor' and g.codigo_supervisor::text = viewer_code)
      or (viewer_profile = 'coordenador' and g.perfil_usuario in ('Supervisor', 'Vendedor') and g.codigo_coordenador::text = viewer_code)
      or (viewer_profile not in ('vendedor', 'supervisor', 'coordenador', 'sem_perfil'))
    );

  select coalesce(jsonb_agg(jsonb_build_object(
    'month_start', m.month_start,
    'label', to_char(m.month_start, 'TMMonth / YYYY')
  ) order by m.month_start desc), '[]'::jsonb)
  into available_months
  from (
    select distinct competencia_data as month_start
    from public.app_gold_performance
    where competencia_data >= date '2026-08-01'
    union
    select month_start from public.app_performance_targets where month_start < date '2026-08-01'
  ) m;

  if aggregate_company then
    with source as (
      select * from public.app_gold_performance g
      where g.competencia_data = selected_month and g.perfil_usuario = 'Coordenador'
    ), grouped as (
      select
        tipo_performance,
        codigo_fornecedor,
        coalesce(max(fornecedor), 'Geral') as fornecedor,
        jsonb_build_object(
          'tipo_usuario', 'Empresa',
          'meta_financeira', sum(public.gold_number(payload, 'meta_financeira')),
          'valor_venda_bruta', sum(public.gold_number(payload, 'valor_venda_bruta')),
          'valor_devolucao', sum(public.gold_number(payload, 'valor_devolucao')),
          'realizado_financeiro', sum(public.gold_number(payload, 'realizado_financeiro')),
          'percentual_realizado_financeiro', sum(public.gold_number(payload, 'realizado_financeiro')) / nullif(sum(public.gold_number(payload, 'meta_financeira')), 0),
          'premio_financeiro', sum(public.gold_number(payload, 'premio_financeiro')),
          'possibilidade_financeiro', sum(public.gold_number(payload, 'possibilidade_financeiro')),
          'meta_financeira_ate_dia_15', sum(public.gold_number(payload, 'meta_financeira_ate_dia_15')),
          'realizado_financeiro_ate_dia_15', sum(public.gold_number(payload, 'realizado_financeiro_ate_dia_15')),
          'percentual_realizado_financeiro_ate_dia_15', sum(public.gold_number(payload, 'realizado_financeiro_ate_dia_15')) / nullif(sum(public.gold_number(payload, 'meta_financeira_ate_dia_15')), 0),
          'premio_financeiro_ate_dia_15', sum(public.gold_number(payload, 'premio_financeiro_ate_dia_15')),
          'possibilidade_financeiro_ate_dia_15', sum(public.gold_number(payload, 'possibilidade_financeiro_ate_dia_15')),
          'meta_positivacao', sum(public.gold_number(payload, 'meta_positivacao')),
          'realizado_positivacao', sum(public.gold_number(payload, 'realizado_positivacao')),
          'percentual_realizado_positivacao', sum(public.gold_number(payload, 'realizado_positivacao')) / nullif(sum(public.gold_number(payload, 'meta_positivacao')), 0),
          'premio_positivacao', sum(public.gold_number(payload, 'premio_positivacao')),
          'possibilidade_positivacao', sum(public.gold_number(payload, 'possibilidade_positivacao')),
          'meta_volume', sum(public.gold_number(payload, 'meta_volume')),
          'realizado_volume', sum(public.gold_number(payload, 'realizado_volume')),
          'percentual_realizado_volume', sum(public.gold_number(payload, 'realizado_volume')) / nullif(sum(public.gold_number(payload, 'meta_volume')), 0),
          'premio_volume', sum(public.gold_number(payload, 'premio_volume')),
          'possibilidade_volume', sum(public.gold_number(payload, 'possibilidade_volume')),
          'meta_efetividade', max(public.gold_number(payload, 'meta_efetividade')),
          'quantidade_pedidos_efetividade', sum(public.gold_number(payload, 'quantidade_pedidos_efetividade')),
          'quantidade_pedidos_roteirizados_no_dia', sum(public.gold_number(payload, 'quantidade_pedidos_roteirizados_no_dia')),
          'realizado_efetividade', sum(public.gold_number(payload, 'quantidade_pedidos_efetividade')) / nullif(sum(public.gold_number(payload, 'quantidade_pedidos_roteirizados_no_dia')), 0),
          'percentual_realizado_efetividade', (sum(public.gold_number(payload, 'quantidade_pedidos_efetividade')) / nullif(sum(public.gold_number(payload, 'quantidade_pedidos_roteirizados_no_dia')), 0)) / nullif(max(public.gold_number(payload, 'meta_efetividade')), 0),
          'premio_efetividade', sum(public.gold_number(payload, 'premio_efetividade')),
          'possibilidade_efetividade', sum(public.gold_number(payload, 'possibilidade_efetividade')),
          'meta_lucratividade', max(public.gold_number(payload, 'meta_lucratividade')),
          'realizado_lucratividade', (sum(public.gold_number(payload, 'realizado_financeiro')) - sum(public.gold_number(payload, 'custo_faturamento')) + sum(public.gold_number(payload, 'custo_devolucao'))) / nullif(sum(public.gold_number(payload, 'realizado_financeiro')), 0),
          'percentual_realizado_lucratividade', ((sum(public.gold_number(payload, 'realizado_financeiro')) - sum(public.gold_number(payload, 'custo_faturamento')) + sum(public.gold_number(payload, 'custo_devolucao'))) / nullif(sum(public.gold_number(payload, 'realizado_financeiro')), 0)) / nullif(max(public.gold_number(payload, 'meta_lucratividade')), 0),
          'premio_lucratividade', sum(public.gold_number(payload, 'premio_lucratividade')),
          'possibilidade_lucratividade', sum(public.gold_number(payload, 'possibilidade_lucratividade')),
          'meta_percentual_inadimplencia', max(public.gold_number(payload, 'meta_percentual_inadimplencia')),
          'valor_inadimplencia', sum(public.gold_number(payload, 'valor_inadimplencia')),
          'realizado_percentual_inadimplencia', sum(public.gold_number(payload, 'valor_inadimplencia')) / nullif(sum(public.gold_number(payload, 'realizado_financeiro')), 0),
          'percentual_da_meta_inadimplencia', (sum(public.gold_number(payload, 'valor_inadimplencia')) / nullif(sum(public.gold_number(payload, 'realizado_financeiro')), 0)) / nullif(max(public.gold_number(payload, 'meta_percentual_inadimplencia')), 0),
          'premio_inadimplencia', sum(public.gold_number(payload, 'premio_inadimplencia')),
          'possibilidade_inadimplencia', sum(public.gold_number(payload, 'possibilidade_inadimplencia')),
          'premio_total', sum(public.gold_number(payload, 'premio_total')),
          'possibilidade_total', sum(public.gold_number(payload, 'possibilidade_total')),
          'status_apuracao', case when bool_or((payload ->> 'status_apuracao') <> 'Calculada') then 'Calculada com pendências' else 'Calculada' end,
          'observacoes_calculo', 'Consolidado da empresa pela soma dos coordenadores.'
        ) as data,
        max(source_updated_at) as source_updated_at
      from source
      group by tipo_performance, codigo_fornecedor
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', case when tipo_performance = 'Geral' then '1' else codigo_fornecedor::text end,
      'supplier_name', fornecedor,
      'financial_metric_source', 'venda',
      'secondary_metric_source', 'venda',
      'target_fin', public.gold_number(data, 'meta_financeira'),
      'actual_fin', public.gold_number(data, 'realizado_financeiro'),
      'target_pos', public.gold_number(data, 'meta_positivacao'),
      'actual_pos', public.gold_number(data, 'realizado_positivacao'),
      'secondary_metric_type', 'positivacao',
      'type_user', data ->> 'tipo_usuario',
      'prize_total', public.gold_number(data, 'premio_total'),
      'possibility_total', public.gold_number(data, 'possibilidade_total'),
      'status', data ->> 'status_apuracao',
      'observations', data ->> 'observacoes_calculo',
      'metrics', public.gold_metrics(data)
    ) order by case when tipo_performance = 'Geral' then 0 else 1 end, fornecedor), '[]'::jsonb), max(source_updated_at)
    into result_items, last_update
    from grouped;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', case when g.tipo_performance = 'Geral' then '1' else g.codigo_fornecedor::text end,
      'supplier_name', case when g.tipo_performance = 'Geral' then 'Geral' else coalesce(g.fornecedor, g.codigo_fornecedor::text) end,
      'financial_metric_source', 'venda',
      'secondary_metric_source', 'venda',
      'target_fin', public.gold_number(g.payload, 'meta_financeira'),
      'actual_fin', public.gold_number(g.payload, 'realizado_financeiro'),
      'fin_progress_pct', public.gold_number(g.payload, 'percentual_realizado_financeiro') * 100,
      'target_pos', public.gold_number(g.payload, 'meta_positivacao'),
      'actual_pos', public.gold_number(g.payload, 'realizado_positivacao'),
      'target_sku', public.gold_number(g.payload, 'meta_sku'),
      'actual_sku', public.gold_number(g.payload, 'realizado_sku'),
      'secondary_metric_type', case when g.tipo_usuario ilike '%Redes%' then 'sku' else 'positivacao' end,
      'type_user', g.tipo_usuario,
      'route_doubled', g.payload ->> 'rota_dobrada',
      'prize_total', public.gold_number(g.payload, 'premio_total'),
      'possibility_total', public.gold_number(g.payload, 'possibilidade_total'),
      'status', g.payload ->> 'status_apuracao',
      'observations', g.payload ->> 'observacoes_calculo',
      'metrics', public.gold_metrics(g.payload)
    ) order by case when g.tipo_performance = 'Geral' then 0 else 1 end, g.fornecedor), '[]'::jsonb), max(g.source_updated_at)
    into result_items, last_update
    from public.app_gold_performance g
    where g.competencia_data = selected_month
      and lower(g.perfil_usuario) = effective_profile
      and g.codigo_usuario = effective_code;
  end if;

  return jsonb_build_object(
    'supported', true,
    'data_source', 'gold.performance',
    'viewer_profile_slug', viewer_profile,
    'profile_slug', effective_profile,
    'selected_scope_profile_slug', case when aggregate_company then null else effective_profile end,
    'selected_scope_owner_code', case when aggregate_company then null else effective_code end,
    'metric_source', 'venda',
    'selected_month_start', selected_month,
    'available_scopes', available_scopes,
    'available_months', available_months,
    'items', result_items,
    'last_targets_updated_at', last_update,
    'last_sales_updated_at', last_update,
    'last_financial_updated_at', last_update,
    'last_sku_updated_at', last_update
  );
end;
$$;

grant execute on function public.get_performance_overview_v2(date, text, text) to authenticated;

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
  base jsonb;
  viewer_profile text;
  viewer_code text;
  reference_date date := date(window_start at time zone 'America/Sao_Paulo');
  month_start date;
  yesterday date;
  remaining_days integer;
  monthly_fin_target numeric;
  monthly_secondary_target numeric;
  prior_fin_actual numeric;
  prior_secondary_actual numeric;
  daily_fin_target numeric;
  daily_secondary_target numeric;
  secondary_type text := 'positivacao';
  gold_updated_at timestamptz;
begin
  base := public.get_home_kpis(window_start, window_end, 'venda');
  month_start := date_trunc('month', reference_date)::date;
  yesterday := reference_date - 1;
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

  select coalesce(sum(s.venda), 0), coalesce(count(distinct s.codcli), 0)
  into prior_fin_actual, prior_secondary_actual
  from public.app_sales_daily_snapshots s
  where s.sales_date between month_start and yesterday
    and (case
      when viewer_profile = 'vendedor' then s.codusur = viewer_code
      when viewer_profile = 'supervisor' then s.codsupervisor = viewer_code
      when viewer_profile = 'coordenador' then s.codgerente = viewer_code
      else true
    end);

  if secondary_type = 'sku' then
    select coalesce(count(distinct nullif(soi.codprod, '')), 0)
    into prior_secondary_actual
    from public.app_sales_order_items soi
    where soi.sales_date between month_start and yesterday
      and (case
        when viewer_profile = 'vendedor' then soi.codusur = viewer_code
        when viewer_profile = 'supervisor' then soi.codsupervisor = viewer_code
        when viewer_profile = 'coordenador' then soi.codgerente = viewer_code
        else true
      end);
  end if;

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
    'gold_updated_at', gold_updated_at
  );
end;
$$;

grant execute on function public.get_home_kpis_v2(timestamptz, timestamptz) to authenticated;
