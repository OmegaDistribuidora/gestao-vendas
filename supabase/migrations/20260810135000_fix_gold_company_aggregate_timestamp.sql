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
  select coalesce(p.slug, 'sem_perfil'), u.code into viewer_profile, viewer_code
  from public.app_users u left join public.app_profiles p on p.id=u.profile_id
  where u.auth_user_id=auth.uid() and u.is_active limit 1;
  if viewer_profile is null then raise exception 'Usuario nao encontrado.'; end if;
  if selected_month < date '2026-08-01' then
    return public.get_performance_overview(selected_month,'venda',target_scope_profile_slug,target_scope_owner_code);
  end if;
  if viewer_profile='vendedor' then effective_profile:='vendedor'; effective_code:=viewer_code;
  elsif viewer_profile='supervisor' then
    if requested_profile='vendedor' and exists(select 1 from public.app_gold_performance g
      where g.competencia_data=selected_month and g.tipo_performance='Geral' and g.perfil_usuario='Vendedor'
        and g.codigo_usuario=requested_code and g.codigo_supervisor::text=viewer_code)
    then effective_profile:='vendedor';effective_code:=requested_code;
    else effective_profile:='supervisor';effective_code:=viewer_code; end if;
  elsif viewer_profile='coordenador' then
    if requested_profile in ('supervisor','vendedor') and exists(select 1 from public.app_gold_performance g
      where g.competencia_data=selected_month and g.tipo_performance='Geral'
        and lower(g.perfil_usuario)=requested_profile and g.codigo_usuario=requested_code
        and g.codigo_coordenador::text=viewer_code)
    then effective_profile:=requested_profile;effective_code:=requested_code;
    else effective_profile:='coordenador';effective_code:=viewer_code; end if;
  elsif viewer_profile<>'sem_perfil' then
    if requested_profile in ('coordenador','supervisor','vendedor') and exists(select 1
      from public.app_gold_performance g where g.competencia_data=selected_month and g.tipo_performance='Geral'
        and lower(g.perfil_usuario)=requested_profile and g.codigo_usuario=requested_code)
    then effective_profile:=requested_profile;effective_code:=requested_code;
    else aggregate_company:=true;effective_profile:=viewer_profile; end if;
  else return jsonb_build_object('supported',false,'items','[]'::jsonb); end if;

  select coalesce(jsonb_agg(jsonb_build_object('profile_slug',lower(g.perfil_usuario),
    'owner_code',g.codigo_usuario,'display_name',coalesce(g.payload->>'nome_usuario',g.codigo_usuario),
    'label',g.codigo_usuario||' - '||coalesce(g.payload->>'nome_usuario',g.codigo_usuario))
    order by case g.perfil_usuario when 'Coordenador' then 1 when 'Supervisor' then 2 else 3 end,
    g.payload->>'nome_usuario'),'[]'::jsonb) into available_scopes
  from public.app_gold_performance g where g.competencia_data=selected_month and g.tipo_performance='Geral'
    and ((viewer_profile='supervisor' and g.perfil_usuario='Vendedor' and g.codigo_supervisor::text=viewer_code)
      or (viewer_profile='coordenador' and g.perfil_usuario in ('Supervisor','Vendedor') and g.codigo_coordenador::text=viewer_code)
      or viewer_profile not in ('vendedor','supervisor','coordenador','sem_perfil'));

  select coalesce(jsonb_agg(jsonb_build_object('month_start',m.month_start,
    'label',to_char(m.month_start,'TMMonth / YYYY')) order by m.month_start desc),'[]'::jsonb)
  into available_months from (select distinct competencia_data month_start from public.app_gold_performance
    where competencia_data>=date '2026-08-01' union select month_start from public.app_performance_targets
    where month_start<date '2026-08-01') m;

  if aggregate_company then
    with source as (select * from public.app_gold_performance g where g.competencia_data=selected_month
      and g.perfil_usuario='Coordenador'), grouped as (
      select tipo_performance,codigo_fornecedor,coalesce(max(fornecedor),'Geral') fornecedor,
        max(source_updated_at) source_updated_at,
        jsonb_build_object(
          'tipo_usuario','Empresa','meta_financeira',sum(public.gold_number(payload,'meta_financeira')),
          'realizado_financeiro',sum(public.gold_number(payload,'realizado_financeiro')),
          'percentual_realizado_financeiro',sum(public.gold_number(payload,'realizado_financeiro'))/nullif(sum(public.gold_number(payload,'meta_financeira')),0),
          'premio_financeiro',sum(public.gold_number(payload,'premio_financeiro')),'possibilidade_financeiro',sum(public.gold_number(payload,'possibilidade_financeiro')),
          'meta_financeira_ate_dia_15',sum(public.gold_number(payload,'meta_financeira_ate_dia_15')),
          'realizado_financeiro_ate_dia_15',sum(public.gold_number(payload,'realizado_financeiro_ate_dia_15')),
          'percentual_realizado_financeiro_ate_dia_15',sum(public.gold_number(payload,'realizado_financeiro_ate_dia_15'))/nullif(sum(public.gold_number(payload,'meta_financeira_ate_dia_15')),0),
          'premio_financeiro_ate_dia_15',sum(public.gold_number(payload,'premio_financeiro_ate_dia_15')),
          'possibilidade_financeiro_ate_dia_15',sum(public.gold_number(payload,'possibilidade_financeiro_ate_dia_15')),
          'meta_positivacao',sum(public.gold_number(payload,'meta_positivacao')),'realizado_positivacao',sum(public.gold_number(payload,'realizado_positivacao')),
          'percentual_realizado_positivacao',sum(public.gold_number(payload,'realizado_positivacao'))/nullif(sum(public.gold_number(payload,'meta_positivacao')),0),
          'premio_positivacao',sum(public.gold_number(payload,'premio_positivacao')),'possibilidade_positivacao',sum(public.gold_number(payload,'possibilidade_positivacao')),
          'meta_volume',sum(public.gold_number(payload,'meta_volume')),'realizado_volume',sum(public.gold_number(payload,'realizado_volume')),
          'percentual_realizado_volume',sum(public.gold_number(payload,'realizado_volume'))/nullif(sum(public.gold_number(payload,'meta_volume')),0),
          'premio_volume',sum(public.gold_number(payload,'premio_volume')),'possibilidade_volume',sum(public.gold_number(payload,'possibilidade_volume')),
          'meta_efetividade',max(public.gold_number(payload,'meta_efetividade')),
          'realizado_efetividade',sum(public.gold_number(payload,'quantidade_pedidos_efetividade'))/nullif(sum(public.gold_number(payload,'quantidade_pedidos_roteirizados_no_dia')),0),
          'percentual_realizado_efetividade',(sum(public.gold_number(payload,'quantidade_pedidos_efetividade'))/nullif(sum(public.gold_number(payload,'quantidade_pedidos_roteirizados_no_dia')),0))/nullif(max(public.gold_number(payload,'meta_efetividade')),0),
          'premio_efetividade',sum(public.gold_number(payload,'premio_efetividade')),'possibilidade_efetividade',sum(public.gold_number(payload,'possibilidade_efetividade')),
          'meta_lucratividade',max(public.gold_number(payload,'meta_lucratividade')),
          'realizado_lucratividade',(sum(public.gold_number(payload,'realizado_financeiro'))-sum(public.gold_number(payload,'custo_faturamento'))+sum(public.gold_number(payload,'custo_devolucao')))/nullif(sum(public.gold_number(payload,'realizado_financeiro')),0),
          'percentual_realizado_lucratividade',((sum(public.gold_number(payload,'realizado_financeiro'))-sum(public.gold_number(payload,'custo_faturamento'))+sum(public.gold_number(payload,'custo_devolucao')))/nullif(sum(public.gold_number(payload,'realizado_financeiro')),0))/nullif(max(public.gold_number(payload,'meta_lucratividade')),0),
          'premio_lucratividade',sum(public.gold_number(payload,'premio_lucratividade')),'possibilidade_lucratividade',sum(public.gold_number(payload,'possibilidade_lucratividade')),
          'meta_percentual_inadimplencia',max(public.gold_number(payload,'meta_percentual_inadimplencia')),
          'realizado_percentual_inadimplencia',sum(public.gold_number(payload,'valor_inadimplencia'))/nullif(sum(public.gold_number(payload,'realizado_financeiro')),0),
          'percentual_da_meta_inadimplencia',(sum(public.gold_number(payload,'valor_inadimplencia'))/nullif(sum(public.gold_number(payload,'realizado_financeiro')),0))/nullif(max(public.gold_number(payload,'meta_percentual_inadimplencia')),0),
          'premio_inadimplencia',sum(public.gold_number(payload,'premio_inadimplencia')),'possibilidade_inadimplencia',sum(public.gold_number(payload,'possibilidade_inadimplencia')),
          'premio_total',sum(public.gold_number(payload,'premio_total')),'possibilidade_total',sum(public.gold_number(payload,'possibilidade_total')),
          'status_apuracao',case when bool_or((payload->>'status_apuracao')<>'Calculada') then 'Calculada com pendências' else 'Calculada' end,
          'observacoes_calculo','Consolidado da empresa pela soma dos coordenadores.') data
      from source group by tipo_performance,codigo_fornecedor)
    select coalesce(jsonb_agg(jsonb_build_object('code',case when tipo_performance='Geral' then '1' else codigo_fornecedor::text end,
      'supplier_name',fornecedor,'financial_metric_source','venda','secondary_metric_source','venda',
      'target_fin',public.gold_number(data,'meta_financeira'),'actual_fin',public.gold_number(data,'realizado_financeiro'),
      'target_pos',public.gold_number(data,'meta_positivacao'),'actual_pos',public.gold_number(data,'realizado_positivacao'),
      'secondary_metric_type','positivacao','type_user','Empresa','prize_total',public.gold_number(data,'premio_total'),
      'possibility_total',public.gold_number(data,'possibilidade_total'),'status',data->>'status_apuracao',
      'observations',data->>'observacoes_calculo','metrics',public.gold_metrics(data))
      order by case when tipo_performance='Geral' then 0 else 1 end,fornecedor),'[]'::jsonb),max(source_updated_at)
    into result_items,last_update from grouped;
  else
    select coalesce(jsonb_agg(jsonb_build_object('code',case when g.tipo_performance='Geral' then '1' else g.codigo_fornecedor::text end,
      'supplier_name',case when g.tipo_performance='Geral' then 'Geral' else coalesce(g.fornecedor,g.codigo_fornecedor::text) end,
      'financial_metric_source','venda','secondary_metric_source','venda','target_fin',public.gold_number(g.payload,'meta_financeira'),
      'actual_fin',public.gold_number(g.payload,'realizado_financeiro'),'fin_progress_pct',public.gold_number(g.payload,'percentual_realizado_financeiro')*100,
      'target_pos',public.gold_number(g.payload,'meta_positivacao'),'actual_pos',public.gold_number(g.payload,'realizado_positivacao'),
      'target_sku',public.gold_number(g.payload,'meta_sku'),'actual_sku',public.gold_number(g.payload,'realizado_sku'),
      'secondary_metric_type',case when g.tipo_usuario ilike '%Redes%' then 'sku' else 'positivacao' end,
      'type_user',g.tipo_usuario,'route_doubled',g.payload->>'rota_dobrada','prize_total',public.gold_number(g.payload,'premio_total'),
      'possibility_total',public.gold_number(g.payload,'possibilidade_total'),'status',g.payload->>'status_apuracao',
      'observations',g.payload->>'observacoes_calculo','metrics',public.gold_metrics(g.payload))
      order by case when g.tipo_performance='Geral' then 0 else 1 end,g.fornecedor),'[]'::jsonb),max(g.source_updated_at)
    into result_items,last_update from public.app_gold_performance g where g.competencia_data=selected_month
      and lower(g.perfil_usuario)=effective_profile and g.codigo_usuario=effective_code;
  end if;
  return jsonb_build_object('supported',true,'data_source','gold.performance','viewer_profile_slug',viewer_profile,
    'profile_slug',effective_profile,'selected_scope_profile_slug',case when aggregate_company then null else effective_profile end,
    'selected_scope_owner_code',case when aggregate_company then null else effective_code end,'metric_source','venda',
    'selected_month_start',selected_month,'available_scopes',available_scopes,'available_months',available_months,
    'items',result_items,'last_targets_updated_at',last_update,'last_sales_updated_at',last_update,
    'last_financial_updated_at',last_update,'last_sku_updated_at',last_update);
end;
$$;
