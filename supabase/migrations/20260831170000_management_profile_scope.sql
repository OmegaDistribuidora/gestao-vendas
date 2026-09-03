-- Escopo configuravel para perfis gerenciais. Esta estrutura nao altera o
-- comportamento dos perfis existentes enquanto nenhuma RPC a consultar.
create table if not exists public.app_profile_coordinator_scopes (
  profile_slug text not null,
  coordinator_code text not null,
  created_at timestamptz not null default now(),
  primary key (profile_slug, coordinator_code)
);

alter table public.app_profile_coordinator_scopes enable row level security;

revoke all on table public.app_profile_coordinator_scopes from public, anon, authenticated;
grant select, insert, update, delete on table public.app_profile_coordinator_scopes
  to service_role;

insert into public.app_profile_coordinator_scopes (
  profile_slug,
  coordinator_code
)
values
  ('gerencia', '9'),
  ('gerencia', '10'),
  ('gerencia', '12'),
  ('gerencia', '13'),
  ('gerencia', '14')
on conflict (profile_slug, coordinator_code) do nothing;

create or replace function public.app_allowed_coordinator_codes(
  target_profile_slug text
)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(scope.coordinator_code order by scope.coordinator_code),
    array[]::text[]
  )
  from public.app_profile_coordinator_scopes scope
  where scope.profile_slug = lower(btrim(coalesce(target_profile_slug, '')))
$$;

revoke all on function public.app_allowed_coordinator_codes(text) from public, anon;
grant execute on function public.app_allowed_coordinator_codes(text)
  to authenticated, service_role;

create or replace function public.app_scope_matches(
  viewer_profile_slug text,
  viewer_owner_code text,
  row_seller_code text,
  row_supervisor_code text,
  row_coordinator_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case lower(btrim(coalesce(viewer_profile_slug, '')))
    when 'vendedor' then
      btrim(coalesce(row_seller_code, '')) = btrim(coalesce(viewer_owner_code, ''))
    when 'supervisor' then
      btrim(coalesce(row_supervisor_code, '')) = btrim(coalesce(viewer_owner_code, ''))
    when 'coordenador' then
      btrim(coalesce(row_coordinator_code, '')) = btrim(coalesce(viewer_owner_code, ''))
    when 'gerencia' then
      btrim(coalesce(row_coordinator_code, '')) = any(
        public.app_allowed_coordinator_codes('gerencia')
      )
    when 'admin' then true
    when 'diretoria' then true
    when 'outros' then true
    else false
  end
$$;

revoke all on function public.app_scope_matches(text, text, text, text, text)
  from public, anon;
grant execute on function public.app_scope_matches(text, text, text, text, text)
  to authenticated, service_role;

create or replace function public.app_scope_user_allowed(
  viewer_profile_slug text,
  viewer_owner_code text,
  target_profile_slug text,
  target_owner_code text,
  target_supervisor_code text,
  target_coordinator_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case lower(btrim(coalesce(viewer_profile_slug, '')))
    when 'vendedor' then
      lower(btrim(coalesce(target_profile_slug, ''))) = 'vendedor'
      and btrim(coalesce(target_owner_code, '')) = btrim(coalesce(viewer_owner_code, ''))
    when 'supervisor' then
      lower(btrim(coalesce(target_profile_slug, ''))) = 'vendedor'
      and btrim(coalesce(target_supervisor_code, '')) = btrim(coalesce(viewer_owner_code, ''))
    when 'coordenador' then
      lower(btrim(coalesce(target_profile_slug, ''))) in ('supervisor', 'vendedor')
      and btrim(coalesce(target_coordinator_code, '')) = btrim(coalesce(viewer_owner_code, ''))
    when 'gerencia' then
      (
        lower(btrim(coalesce(target_profile_slug, ''))) = 'coordenador'
        and btrim(coalesce(target_owner_code, '')) = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
      )
      or (
        lower(btrim(coalesce(target_profile_slug, ''))) in ('supervisor', 'vendedor')
        and btrim(coalesce(target_coordinator_code, '')) = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
      )
    when 'admin' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'coordenador', 'supervisor', 'vendedor'
      )
    when 'diretoria' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'coordenador', 'supervisor', 'vendedor'
      )
    when 'outros' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'coordenador', 'supervisor', 'vendedor'
      )
    else false
  end
$$;

revoke all on function public.app_scope_user_allowed(
  text, text, text, text, text, text
) from public, anon;
grant execute on function public.app_scope_user_allowed(
  text, text, text, text, text, text
) to authenticated, service_role;

-- Guardas de regressao: os perfis amplos existentes precisam continuar vendo
-- inclusive o coordenador 7. Somente Gerencia recebe o novo recorte.
do $$
begin
  if not public.app_scope_matches('diretoria', '', '', '', '7')
     or not public.app_scope_matches('outros', '', '', '', '7') then
    raise exception 'O escopo amplo de Diretoria/Outros foi alterado.';
  end if;

  if public.app_scope_matches('gerencia', '', '', '', '7')
     or not public.app_scope_matches('gerencia', '', '', '', '9') then
    raise exception 'O recorte de coordenadores da Gerencia e invalido.';
  end if;

  if not public.app_scope_user_allowed(
    'diretoria', '', 'coordenador', '7', '', ''
  ) or not public.app_scope_user_allowed(
    'outros', '', 'vendedor', '9999', '99', '7'
  ) then
    raise exception 'Os filtros amplos de Diretoria/Outros foram alterados.';
  end if;

  if public.app_scope_user_allowed(
    'gerencia', '', 'coordenador', '7', '', ''
  ) or public.app_scope_user_allowed(
    'gerencia', '', 'vendedor', '9999', '99', '7'
  ) or not public.app_scope_user_allowed(
    'gerencia', '', 'coordenador', '10', '', ''
  ) or not public.app_scope_user_allowed(
    'gerencia', '', 'vendedor', '9999', '99', '10'
  ) then
    raise exception 'Os filtros hierarquicos da Gerencia sao invalidos.';
  end if;
end;
$$;

comment on table public.app_profile_coordinator_scopes is
  'Coordenadores visiveis por perfis gerenciais de escopo restrito.';

create or replace function public.get_agenda_visible_owners()
returns table (
  profile_slug text,
  owner_code text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
begin
  select profile.slug
    into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile_slug <> 'gerencia' then
    return;
  end if;

  return query
  select profile.slug, app_user.code
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.is_active
    and (
      (
        profile.slug = 'coordenador'
        and app_user.code = any(public.app_allowed_coordinator_codes('gerencia'))
      )
      or (
        profile.slug = 'supervisor'
        and coalesce(app_user.coordinator_code, '') = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
      )
    )
  order by
    case profile.slug when 'coordenador' then 1 else 2 end,
    app_user.code;
end;
$$;

-- Clientes recuperados nao carregam o coordenador na propria tabela. O
-- recorte e obtido pela carteira atual do cliente e pelo vendedor vinculado.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_recovered_customer_opportunities(text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'where normalized_search = ''''
       or lower(extensions.unaccent(r.tax_id)) like ''%'' || normalized_search || ''%''',
    'where (
      viewer_profile_slug <> ''gerencia''
      or exists (
        select 1
        from public.app_customer_seller_bases customer_base
        join public.app_users seller
          on seller.code = customer_base.codusur
         and seller.is_active
        join public.app_profiles seller_profile
          on seller_profile.id = seller.profile_id
         and seller_profile.slug = ''vendedor''
        where customer_base.codcli = r.source_customer_code
          and coalesce(seller.coordinator_code, '''') = any(
            public.app_allowed_coordinator_codes(''gerencia'')
          )
      )
    )
      and (
       normalized_search = ''''
       or lower(extensions.unaccent(r.tax_id)) like ''%'' || normalized_search || ''%'''
  );
  scoped_definition := replace(
    scoped_definition,
    'or lower(extensions.unaccent(r.activity_name)) like ''%'' || normalized_search || ''%''
  )',
    'or lower(extensions.unaccent(r.activity_name)) like ''%'' || normalized_search || ''%''
      )
  )'
  );
  if scoped_definition = original_definition
     or position('viewer_profile_slug <> ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar Clientes Recuperados.';
  end if;
  execute scoped_definition;
end;
$$;

-- Performance historica (antes da Gold): preserva a regra antiga, mas limita
-- metas, realizados e filtros da Gerencia pelos mesmos coordenadores.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_performance_overview(date,text,text,text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'elsif viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') then',
    'elsif viewer_profile_slug in (''admin'', ''diretoria'', ''outros'', ''gerencia'') then'
  );
  scoped_definition := replace(
    scoped_definition,
    'and p.slug = requested_profile_slug
          and u.code = requested_owner_code',
    'and p.slug = requested_profile_slug
          and u.code = requested_owner_code
          and public.app_scope_user_allowed(
            viewer_profile_slug,
            viewer_user_code,
            p.slug,
            u.code,
            u.supervisor_code,
            u.coordinator_code
          )'
  );
  scoped_definition := replace(
    scoped_definition,
    '((not is_effective_named_profile) and t.profile_slug = ''coordenador'')',
    '((not is_effective_named_profile) and t.profile_slug = ''coordenador''
          and (
            effective_profile_slug <> ''gerencia''
            or t.owner_code = any(public.app_allowed_coordinator_codes(''gerencia''))
          ))'
  );
  scoped_definition := replace(
    scoped_definition,
    '(viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') and p.slug in (''coordenador'', ''supervisor'', ''vendedor''))',
    '(viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') and p.slug in (''coordenador'', ''supervisor'', ''vendedor''))
        or
        (viewer_profile_slug = ''gerencia'' and public.app_scope_user_allowed(
          viewer_profile_slug,
          viewer_user_code,
          p.slug,
          u.code,
          u.supervisor_code,
          u.coordinator_code
        ))'
  );
  if scoped_definition = original_definition
     or position('effective_profile_slug <> ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar a Performance historica.';
  end if;
  execute scoped_definition;
end;
$$;

-- Notificacoes de meta e devolucao respeitam o mesmo recorte gerencial.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_push_performance_metrics_gross_positivation(text,text,date)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'and g.perfil_usuario = ''Coordenador'';',
    'and g.perfil_usuario = ''Coordenador''
      and (
        v_profile <> ''gerencia''
        or g.codigo_usuario = any(public.app_allowed_coordinator_codes(''gerencia''))
      );'
  );
  scoped_definition := replace(
    scoped_definition,
    '(not v_is_named_profile)
      or (v_profile = ''vendedor'' and s.codusur = v_owner)',
    '((not v_is_named_profile) and (
        v_profile <> ''gerencia''
        or s.codgerente = any(public.app_allowed_coordinator_codes(''gerencia''))
      ))
      or (v_profile = ''vendedor'' and s.codusur = v_owner)'
  );
  if scoped_definition = original_definition
     or position('v_profile <> ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar a base das notificacoes da Gerencia.';
  end if;
  execute scoped_definition;

  original_definition := pg_get_functiondef(
    'public.get_push_performance_metrics(text,text,date)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    '(not v_is_named_profile)
      or (v_profile = ''vendedor'' and today.codusur = v_owner)',
    '((not v_is_named_profile) and (
        v_profile <> ''gerencia''
        or today.codgerente = any(public.app_allowed_coordinator_codes(''gerencia''))
      ))
      or (v_profile = ''vendedor'' and today.codusur = v_owner)'
  );
  scoped_definition := replace(
    scoped_definition,
    '(not v_is_named_profile)
          or (v_profile = ''vendedor'' and prior.codusur = v_owner)',
    '((not v_is_named_profile) and (
            v_profile <> ''gerencia''
            or prior.codgerente = any(public.app_allowed_coordinator_codes(''gerencia''))
          ))
          or (v_profile = ''vendedor'' and prior.codusur = v_owner)'
  );
  if scoped_definition = original_definition
     or position('today.codgerente = any' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar o progresso diario da Gerencia.';
  end if;
  execute scoped_definition;

  original_definition := pg_get_functiondef(
    'public.evaluate_push_return_notifications_all_profiles(date,timestamptz)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'select ri.return_date,ri.numped,ri.codusur,
        round(sum(ri.item_value),2)::numeric total_value',
    'select ri.return_date,ri.numped,ri.codusur,ri.codgerente,
        round(sum(ri.item_value),2)::numeric total_value'
  );
  scoped_definition := replace(
    scoped_definition,
    'group by ri.return_date,ri.numped,ri.codusur',
    'group by ri.return_date,ri.numped,ri.codusur,ri.codgerente'
  );
  scoped_definition := replace(
    scoped_definition,
    'from active_recipients ar cross join return_orders ro',
    'from active_recipients ar
    join return_orders ro
      on ar.profile_slug <> ''gerencia''
      or ro.codgerente = any(public.app_allowed_coordinator_codes(''gerencia''))'
  );
  if scoped_definition = original_definition
     or position('ro.codgerente = any' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar as devolucoes da Gerencia.';
  end if;
  execute scoped_definition;
end;
$$;

revoke all on function public.get_agenda_visible_owners() from public, anon;
grant execute on function public.get_agenda_visible_owners() to authenticated;

-- As funcoes abaixo ja possuem o recorte consolidado correto para todos os
-- perfis existentes. Acrescentamos somente o ramo Gerencia aos CASEs de
-- escopo das tabelas fato, preservando integralmente os demais ramos.
do $$
declare
  function_signature text;
  original_definition text;
  scoped_definition text;
  scope_pattern text :=
    'when[[:space:]]+([a-z_][a-z0-9_]*)[[:space:]]*=[[:space:]]*''coordenador'''
    || '[[:space:]]+then[[:space:]]+([a-z_][a-z0-9_]*)\.codgerente'
    || '[[:space:]]*=[[:space:]]*([a-z_][a-z0-9_]*)'
    || '[[:space:]]+else[[:space:]]+true';
  scope_replacement text :=
    'when \1 = ''coordenador'' then \2.codgerente = \3 '
    || 'when \1 = ''gerencia'' then \2.codgerente = any('
    || 'public.app_allowed_coordinator_codes(''gerencia'')) else true';
begin
  foreach function_signature in array array[
    'public.get_home_kpis(timestamptz,timestamptz,text)',
    'public.get_home_positive_customers(timestamptz,timestamptz)',
    'public.get_supplier_analysis_effective_balances(timestamptz,timestamptz,text)',
    'public.get_supplier_analysis(timestamptz,timestamptz,text)',
    'public.get_return_analysis(timestamptz,timestamptz)',
    'public.get_return_order_details(date,text)',
    'public.get_blocked_orders_overview()',
    'public.get_delinquency_overview(text,text)',
    'public.get_performance_overview(date,text,text,text)'
  ] loop
    original_definition := pg_get_functiondef(function_signature::regprocedure);
    scoped_definition := regexp_replace(
      original_definition,
      scope_pattern,
      scope_replacement,
      'gi'
    );

    if scoped_definition = original_definition then
      raise exception
        'Nao foi possivel adicionar o escopo Gerencia em %.',
        function_signature;
    end if;

    execute scoped_definition;
  end loop;
end;
$$;

-- Compromissos: a Gerencia consulta somente coordenadores permitidos e os
-- supervisores vinculados a eles. O total exibido pelo app passa a ser a soma
-- desses coordenadores porque os itens recebidos ja chegam filtrados.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_commitment_overview_base(date,date,text,text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    '''supervisor'', ''coordenador'', ''diretoria'', ''outros''',
    '''supervisor'', ''coordenador'', ''diretoria'', ''outros'', ''gerencia'''
  );
  scoped_definition := replace(
    scoped_definition,
    'viewer_profile_slug not in (''diretoria'', ''outros'')',
    'viewer_profile_slug not in (''diretoria'', ''outros'', ''gerencia'')'
  );
  scoped_definition := replace(
    scoped_definition,
    '      else true
    end
  )',
    '      when viewer_profile_slug = ''gerencia'' then
        (
          commitment.profile_slug = ''coordenador''
          and commitment.owner_code = any(
            public.app_allowed_coordinator_codes(''gerencia'')
          )
        ) or (
          commitment.profile_slug = ''supervisor''
          and exists (
            select 1
            from public.app_users subordinate
            join public.app_profiles subordinate_profile
              on subordinate_profile.id = subordinate.profile_id
            where subordinate.is_active
              and subordinate_profile.slug = ''supervisor''
              and subordinate.code = commitment.owner_code
              and coalesce(subordinate.coordinator_code, '''') = any(
                public.app_allowed_coordinator_codes(''gerencia'')
              )
          )
        )
      else true
    end
  )'
  );
  scoped_definition := replace(
    scoped_definition,
    'and commitment.end_date = selected_end_date
  ), coordinator_scopes as (',
    'and commitment.end_date = selected_end_date
      and (
        viewer_profile_slug <> ''gerencia''
        or coalesce(app_user.coordinator_code, '''') = any(
          public.app_allowed_coordinator_codes(''gerencia'')
        )
      )
  ), coordinator_scopes as ('
  );
  scoped_definition := replace(
    scoped_definition,
    'and coordinator_profile.slug = ''coordenador''
      and (',
    'and coordinator_profile.slug = ''coordenador''
      and (
        viewer_profile_slug <> ''gerencia''
        or coordinator.code = any(public.app_allowed_coordinator_codes(''gerencia''))
      )
      and ('
  );
  scoped_definition := replace(
    scoped_definition,
    'and commitment.end_date = selected_end_date
    ), coordinator_targets as (',
    'and commitment.end_date = selected_end_date
        and (
          viewer_profile_slug <> ''gerencia''
          or coalesce(app_user.coordinator_code, '''') = any(
            public.app_allowed_coordinator_codes(''gerencia'')
          )
        )
    ), coordinator_targets as ('
  );
  scoped_definition := replace(
    scoped_definition,
    'when viewer_profile_slug in (''diretoria'', ''outros'')
        then available_scopes',
    'when viewer_profile_slug in (''diretoria'', ''outros'', ''gerencia'')
        then available_scopes'
  );

  if scoped_definition = original_definition
     or position('viewer_profile_slug = ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar os Compromissos da Gerencia.';
  end if;
  execute scoped_definition;
end;
$$;

-- Mapa de oportunidades: limita os seletores e tambem o endpoint de detalhe,
-- evitando acesso por chamada manual com um vendedor do coordenador 7.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_customer_opportunities_v2(text,text,text,text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    '(viewer_profile <> ''coordenador'' or coalesce(seller.coordinator_code,'''')=viewer_code)',
    '(
          viewer_profile not in (''coordenador'', ''gerencia'')
          or (viewer_profile = ''coordenador'' and coalesce(seller.coordinator_code, '''') = viewer_code)
          or (viewer_profile = ''gerencia'' and coalesce(seller.coordinator_code, '''') = any(
            public.app_allowed_coordinator_codes(''gerencia'')
          ))
        )'
  );
  scoped_definition := replace(
    scoped_definition,
    '(viewer_profile <> ''coordenador'' or coalesce(u.coordinator_code,'''')=viewer_code)',
    '(
          viewer_profile not in (''coordenador'', ''gerencia'')
          or (viewer_profile = ''coordenador'' and coalesce(u.coordinator_code, '''') = viewer_code)
          or (viewer_profile = ''gerencia'' and coalesce(u.coordinator_code, '''') = any(
            public.app_allowed_coordinator_codes(''gerencia'')
          ))
        )'
  );
  if scoped_definition = original_definition
     or position('viewer_profile = ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar o Mapa da Gerencia.';
  end if;
  execute scoped_definition;

  original_definition := pg_get_functiondef(
    'public.get_customer_opportunity_details_v2(text,text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'viewer_profile not in (''supervisor'',''coordenador'')
        or (viewer_profile=''supervisor'' and u.supervisor_code=viewer_code)
        or (viewer_profile=''coordenador'' and u.coordinator_code=viewer_code)',
    'viewer_profile not in (''supervisor'',''coordenador'',''gerencia'')
        or (viewer_profile=''supervisor'' and u.supervisor_code=viewer_code)
        or (viewer_profile=''coordenador'' and u.coordinator_code=viewer_code)
        or (viewer_profile=''gerencia'' and u.coordinator_code = any(
          public.app_allowed_coordinator_codes(''gerencia'')
        ))'
  );
  if scoped_definition = original_definition
     or position('viewer_profile=''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar o detalhe do Mapa da Gerencia.';
  end if;
  execute scoped_definition;
end;
$$;

-- Inadimplencia: consolidado, agrupamento e seletores restritos.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_delinquency_overview(text,text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'elsif viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') then',
    'elsif viewer_profile_slug in (''admin'', ''diretoria'', ''outros'', ''gerencia'') then'
  );
  scoped_definition := replace(
    scoped_definition,
    'and p.slug = requested_profile_slug
          and u.code = requested_owner_code',
    'and p.slug = requested_profile_slug
          and u.code = requested_owner_code
          and public.app_scope_user_allowed(
            viewer_profile_slug,
            viewer_user_code,
            p.slug,
            u.code,
            u.supervisor_code,
            u.coordinator_code
          )'
  );
  scoped_definition := replace(
    scoped_definition,
    'when aggregate_all_mode or effective_profile_slug in (''admin'', ''diretoria'', ''outros'')
      then ''coordenador''',
    'when aggregate_all_mode or effective_profile_slug in (
      ''admin'', ''diretoria'', ''outros'', ''gerencia''
    ) then ''coordenador'''
  );
  scoped_definition := replace(
    scoped_definition,
    '(viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') and p.slug in (''coordenador'', ''supervisor'', ''vendedor''))',
    '(viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') and p.slug in (''coordenador'', ''supervisor'', ''vendedor''))
        or
        (viewer_profile_slug = ''gerencia'' and public.app_scope_user_allowed(
          viewer_profile_slug,
          viewer_user_code,
          p.slug,
          u.code,
          u.supervisor_code,
          u.coordinator_code
        ))'
  );

  if scoped_definition = original_definition
     or position('viewer_profile_slug = ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar a Inadimplencia da Gerencia.';
  end if;
  execute scoped_definition;
end;
$$;

-- Filtro hierarquico da Analise por Fornecedor.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_supplier_analysis_v2(timestamptz,timestamptz,text,text,text)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'when viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') then true
        else false',
    'when viewer_profile_slug in (''admin'', ''diretoria'', ''outros'') then true
        when viewer_profile_slug = ''gerencia'' then
          public.app_scope_user_allowed(
            viewer_profile_slug,
            viewer_user_code,
            profile.slug,
            candidate.code,
            candidate.supervisor_code,
            candidate.coordinator_code
          )
        else false'
  );
  if scoped_definition = original_definition
     or position('viewer_profile_slug = ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar a Analise por Fornecedor.';
  end if;
  execute scoped_definition;
end;
$$;

-- Performance Gold: o consolidado e os filtros da Gerencia usam apenas as
-- linhas dos coordenadores autorizados. Os demais perfis mantem a definicao
-- anterior sem mudanca de calculo.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_performance_overview_v2(date,text,text)'::regprocedure
  );

  scoped_definition := replace(
    original_definition,
    'and lower(g.perfil_usuario)=requested_profile and g.codigo_usuario=requested_code)
    then effective_profile:=requested_profile;effective_code:=requested_code;
    else aggregate_company:=true;effective_profile:=viewer_profile; end if;',
    'and lower(g.perfil_usuario)=requested_profile and g.codigo_usuario=requested_code
        and (
          viewer_profile <> ''gerencia''
          or (
            requested_profile = ''coordenador''
            and requested_code = any(public.app_allowed_coordinator_codes(''gerencia''))
          )
          or (
            requested_profile in (''supervisor'', ''vendedor'')
            and g.codigo_coordenador::text = any(
              public.app_allowed_coordinator_codes(''gerencia'')
            )
          )
        ))
    then effective_profile:=requested_profile;effective_code:=requested_code;
    else aggregate_company:=true;effective_profile:=viewer_profile; end if;'
  );

  scoped_definition := replace(
    scoped_definition,
    'or viewer_profile not in (''vendedor'',''supervisor'',''coordenador'',''sem_perfil''));',
    'or (
        viewer_profile not in (''vendedor'',''supervisor'',''coordenador'',''sem_perfil'')
        and (
          viewer_profile <> ''gerencia''
          or (
            g.perfil_usuario = ''Coordenador''
            and g.codigo_usuario = any(public.app_allowed_coordinator_codes(''gerencia''))
          )
          or (
            g.perfil_usuario in (''Supervisor'', ''Vendedor'')
            and g.codigo_coordenador::text = any(
              public.app_allowed_coordinator_codes(''gerencia'')
            )
          )
        )
      ));'
  );

  scoped_definition := replace(
    scoped_definition,
    'and g.perfil_usuario=''Coordenador''), grouped as (',
    'and g.perfil_usuario=''Coordenador''
      and (
        viewer_profile <> ''gerencia''
        or g.codigo_usuario = any(public.app_allowed_coordinator_codes(''gerencia''))
      )), grouped as ('
  );

  if scoped_definition = original_definition
     or position('viewer_profile <> ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar a Performance da Gerencia.';
  end if;
  execute scoped_definition;
end;
$$;

-- Metas diarias da Home: a meta mensal e o realizado fechado da Gerencia
-- consideram somente os coordenadores configurados.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.compute_home_closed_month_liquid_actuals(text,text,date)'::regprocedure
  );

  scoped_definition := replace(
    original_definition,
    'when parameters.profile_slug = ''coordenador'' then s.codgerente = parameters.owner_code
        else true',
    'when parameters.profile_slug = ''coordenador'' then s.codgerente = parameters.owner_code
        when parameters.profile_slug = ''gerencia'' then
          s.codgerente = any(public.app_allowed_coordinator_codes(''gerencia''))
        else true'
  );
  scoped_definition := replace(
    scoped_definition,
    'when parameters.profile_slug = ''coordenador'' then soi.codgerente = parameters.owner_code
        else true',
    'when parameters.profile_slug = ''coordenador'' then soi.codgerente = parameters.owner_code
        when parameters.profile_slug = ''gerencia'' then
          soi.codgerente = any(public.app_allowed_coordinator_codes(''gerencia''))
        else true'
  );

  if scoped_definition = original_definition
     or position('parameters.profile_slug = ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar o realizado fechado da Gerencia.';
  end if;
  execute scoped_definition;

  original_definition := pg_get_functiondef(
    'public.get_home_closed_month_liquid_actuals(text,text,date)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'if normalized_profile in (''vendedor'', ''supervisor'', ''coordenador'') then
    cache_profile := normalized_profile;
    cache_owner := normalized_owner;
  else',
    'if normalized_profile in (''vendedor'', ''supervisor'', ''coordenador'') then
    cache_profile := normalized_profile;
    cache_owner := normalized_owner;
  elsif normalized_profile = ''gerencia'' then
    cache_profile := ''gerencia'';
    cache_owner := ''gerencia'';
  else'
  );
  if scoped_definition = original_definition
     or position('cache_profile := ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel separar o cache diario da Gerencia.';
  end if;
  execute scoped_definition;

  original_definition := pg_get_functiondef(
    'public.get_home_kpis_v2_daily_targets(timestamptz,timestamptz)'::regprocedure
  );
  scoped_definition := replace(
    original_definition,
    'and g.perfil_usuario = ''Coordenador'';',
    'and g.perfil_usuario = ''Coordenador''
      and (
        viewer_profile <> ''gerencia''
        or g.codigo_usuario = any(public.app_allowed_coordinator_codes(''gerencia''))
      );'
  );

  if scoped_definition = original_definition
     or position('viewer_profile <> ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel limitar as metas diarias da Gerencia.';
  end if;
  execute scoped_definition;
end;
$$;

-- Home atomica: libera somente os usuarios pertencentes aos coordenadores
-- configurados e inclui Compromisso para o novo perfil.
do $$
declare
  original_definition text;
  scoped_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_home_dashboard_v3(timestamptz,timestamptz,text,text)'::regprocedure
  );

  scoped_definition := replace(
    original_definition,
    'when viewer_profile_slug in (''diretoria'', ''outros'') then true
        else false',
    'when viewer_profile_slug in (''diretoria'', ''outros'') then true
        when viewer_profile_slug = ''gerencia'' then
          public.app_scope_user_allowed(
            viewer_profile_slug,
            viewer_owner_code,
            profile.slug,
            app_user.code,
            app_user.supervisor_code,
            app_user.coordinator_code
          )
        else false'
  );

  scoped_definition := replace(
    scoped_definition,
    '''supervisor'', ''coordenador'', ''diretoria'', ''outros''',
    '''supervisor'', ''coordenador'', ''diretoria'', ''outros'', ''gerencia'''
  );

  if scoped_definition = original_definition
     or position('viewer_profile_slug = ''gerencia''' in scoped_definition) = 0 then
    raise exception 'Nao foi possivel adicionar o escopo Gerencia na Home.';
  end if;

  execute scoped_definition;
end;
$$;
