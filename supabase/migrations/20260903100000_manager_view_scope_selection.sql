-- Seletores de visao consistentes entre os modulos do aplicativo.
--
-- As RPCs publicadas anteriormente permanecem intactas para que a versao do
-- app que ja esta em producao nao receba opcoes novas antes da nova release.
-- O app em desenvolvimento passa a usar apenas as RPCs versionadas abaixo.

create or replace function public.app_view_scope_user_allowed(
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
    when 'vendedor' then false
    when 'supervisor' then
      lower(btrim(coalesce(target_profile_slug, ''))) = 'vendedor'
      and btrim(coalesce(target_supervisor_code, '')) =
        btrim(coalesce(viewer_owner_code, ''))
    when 'coordenador' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'supervisor', 'vendedor'
      )
      and btrim(coalesce(target_coordinator_code, '')) =
        btrim(coalesce(viewer_owner_code, ''))
    when 'gerencia' then
      (
        lower(btrim(coalesce(target_profile_slug, ''))) = 'coordenador'
        and btrim(coalesce(target_owner_code, '')) = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
      )
      or (
        lower(btrim(coalesce(target_profile_slug, ''))) in (
          'supervisor', 'vendedor'
        )
        and btrim(coalesce(target_coordinator_code, '')) = any(
          public.app_allowed_coordinator_codes('gerencia')
        )
      )
    when 'diretoria' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'gerencia', 'coordenador', 'supervisor', 'vendedor'
      )
    when 'outros' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'gerencia', 'coordenador', 'supervisor', 'vendedor'
      )
    when 'admin' then
      lower(btrim(coalesce(target_profile_slug, ''))) in (
        'coordenador', 'supervisor', 'vendedor'
      )
    else false
  end
$$;

revoke all on function public.app_view_scope_user_allowed(
  text, text, text, text, text, text
) from public, anon;
grant execute on function public.app_view_scope_user_allowed(
  text, text, text, text, text, text
) to authenticated, service_role;

create or replace function public.app_view_scope_options(
  allowed_target_profiles text[] default array[
    'gerencia', 'coordenador', 'supervisor', 'vendedor'
  ]::text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_owner_code text;
  normalized_allowed_profiles text[];
  result jsonb;
begin
  select profile.slug, app_user.code
    into viewer_profile_slug, viewer_owner_code
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  select coalesce(array_agg(distinct lower(btrim(profile_slug))), array[]::text[])
    into normalized_allowed_profiles
  from unnest(coalesce(allowed_target_profiles, array[]::text[])) profile_slug
  where btrim(coalesce(profile_slug, '')) <> '';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_slug', candidate.profile_slug,
        'owner_code', candidate.owner_code,
        'display_name', candidate.display_name,
        'label', case
          when candidate.profile_slug = 'gerencia' then
            'Gerencia - ' || candidate.display_name
          else candidate.profile_name || ' - ' || candidate.owner_code ||
            ' - ' || candidate.display_name
        end
      )
      order by
        case candidate.profile_slug
          when 'gerencia' then 0
          when 'coordenador' then 1
          when 'supervisor' then 2
          when 'vendedor' then 3
          else 9
        end,
        lower(candidate.display_name),
        candidate.owner_code
    ),
    '[]'::jsonb
  )
  into result
  from (
    select
      profile.slug as profile_slug,
      case profile.slug
        when 'gerencia' then 'Gerencia'
        when 'coordenador' then 'Coordenador'
        when 'supervisor' then 'Supervisor'
        when 'vendedor' then 'Vendedor'
        else 'Usuario'
      end as profile_name,
      app_user.code as owner_code,
      coalesce(
        nullif(btrim(app_user.display_name), ''),
        app_user.code
      ) as display_name
    from public.app_users app_user
    join public.app_profiles profile on profile.id = app_user.profile_id
    where app_user.is_active
      and app_user.auth_user_id is not null
      and profile.slug = any(normalized_allowed_profiles)
      and public.app_view_scope_user_allowed(
        viewer_profile_slug,
        viewer_owner_code,
        profile.slug,
        app_user.code,
        app_user.supervisor_code,
        app_user.coordinator_code
      )
  ) candidate;

  return result;
end;
$$;

revoke all on function public.app_view_scope_options(text[]) from public, anon;
grant execute on function public.app_view_scope_options(text[])
  to authenticated, service_role;

create or replace function public.app_resolve_view_scope_auth_user(
  target_profile_slug text,
  target_owner_code text,
  allowed_target_profiles text[] default array[
    'gerencia', 'coordenador', 'supervisor', 'vendedor'
  ]::text[]
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_owner_code text;
  normalized_target_profile text := lower(
    btrim(coalesce(target_profile_slug, ''))
  );
  normalized_target_owner text := btrim(coalesce(target_owner_code, ''));
  target_auth_user_id uuid;
begin
  select profile.slug, app_user.code
    into viewer_profile_slug, viewer_owner_code
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  select app_user.auth_user_id
    into target_auth_user_id
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.is_active
    and app_user.auth_user_id is not null
    and profile.slug = normalized_target_profile
    and app_user.code = normalized_target_owner
    and profile.slug = any(coalesce(allowed_target_profiles, array[]::text[]))
    and public.app_view_scope_user_allowed(
      viewer_profile_slug,
      viewer_owner_code,
      profile.slug,
      app_user.code,
      app_user.supervisor_code,
      app_user.coordinator_code
    )
  limit 1;

  return target_auth_user_id;
end;
$$;

revoke all on function public.app_resolve_view_scope_auth_user(
  text, text, text[]
) from public, anon;
grant execute on function public.app_resolve_view_scope_auth_user(
  text, text, text[]
) to authenticated, service_role;

do $$
begin
  if not public.app_view_scope_user_allowed(
    'diretoria', '', 'gerencia', 'GER', '', ''
  ) or not public.app_view_scope_user_allowed(
    'outros', '', 'gerencia', 'GER', '', ''
  ) then
    raise exception 'Diretoria/Outros nao conseguem selecionar Gerencia.';
  end if;

  if public.app_view_scope_user_allowed(
    'admin', '', 'gerencia', 'GER', '', ''
  ) or public.app_view_scope_user_allowed(
    'gerencia', '', 'gerencia', 'GER', '', ''
  ) then
    raise exception 'Gerencia ficou visivel para um perfil nao autorizado.';
  end if;

  if not public.app_view_scope_user_allowed(
    'gerencia', '', 'coordenador', '10', '', ''
  ) or public.app_view_scope_user_allowed(
    'gerencia', '', 'coordenador', '7', '', ''
  ) or not public.app_view_scope_user_allowed(
    'coordenador', '10', 'vendedor', '3000', '20', '10'
  ) or not public.app_view_scope_user_allowed(
    'supervisor', '20', 'vendedor', '3000', '20', '10'
  ) or public.app_view_scope_user_allowed(
    'vendedor', '3000', 'vendedor', '3001', '20', '10'
  ) then
    raise exception 'A hierarquia dos seletores de visao ficou invalida.';
  end if;
end;
$$;

create or replace function public.get_home_dashboard_v4(
  window_start timestamptz,
  window_end timestamptz,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  requested_profile_slug text := nullif(
    lower(btrim(coalesce(target_scope_profile_slug, ''))), ''
  );
  requested_owner_code text := nullif(
    btrim(coalesce(target_scope_owner_code, '')), ''
  );
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb;
  payload jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid() and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then raise exception 'Usuario nao encontrado.'; end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Filtro da Home incompleto.';
  end if;

  available_scopes := public.app_view_scope_options();
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug, requested_owner_code
    );
    if target_auth_user_id is null then
      raise exception 'Filtro da Home indisponivel para este usuario.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config('request.jwt.claim.sub', target_auth_user_id::text, true);
    end if;
    payload := public.get_home_dashboard_v3(
      window_start, window_end, null, null
    );
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_home_dashboard_v4(
  timestamptz, timestamptz, text, text
) from public, anon;
grant execute on function public.get_home_dashboard_v4(
  timestamptz, timestamptz, text, text
) to authenticated;

create or replace function public.get_supplier_analysis_v3(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda',
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  requested_profile_slug text := nullif(lower(btrim(coalesce(target_scope_profile_slug, ''))), '');
  requested_owner_code text := nullif(btrim(coalesce(target_scope_owner_code, '')), '');
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb;
  payload jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid() and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then raise exception 'Usuario nao encontrado.'; end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Escopo da analise por fornecedor incompleto.';
  end if;

  available_scopes := public.app_view_scope_options();
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug, requested_owner_code
    );
    if target_auth_user_id is null then
      raise exception 'Escopo da analise por fornecedor invalido.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config('request.jwt.claim.sub', target_auth_user_id::text, true);
    end if;
    payload := public.get_supplier_analysis_v2(
      window_start, window_end, metric_source, null, null
    );
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_supplier_analysis_v3(
  timestamptz, timestamptz, text, text, text
) from public, anon;
grant execute on function public.get_supplier_analysis_v3(
  timestamptz, timestamptz, text, text, text
) to authenticated;

create or replace function public.get_performance_overview_v3(
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
  viewer_profile_slug text;
  requested_profile_slug text := nullif(lower(btrim(coalesce(target_scope_profile_slug, ''))), '');
  requested_owner_code text := nullif(btrim(coalesce(target_scope_owner_code, '')), '');
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb;
  payload jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid() and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then raise exception 'Usuario nao encontrado.'; end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Escopo da performance incompleto.';
  end if;

  available_scopes := public.app_view_scope_options();
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug, requested_owner_code
    );
    if target_auth_user_id is null then
      raise exception 'Escopo da performance invalido.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config('request.jwt.claim.sub', target_auth_user_id::text, true);
    end if;
    payload := public.get_performance_overview_v2(
      target_month_start, null, null
    );
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_performance_overview_v3(
  date, text, text
) from public, anon;
grant execute on function public.get_performance_overview_v3(
  date, text, text
) to authenticated;

create or replace function public.get_delinquency_overview_v3(
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  requested_profile_slug text := nullif(lower(btrim(coalesce(target_scope_profile_slug, ''))), '');
  requested_owner_code text := nullif(btrim(coalesce(target_scope_owner_code, '')), '');
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb;
  payload jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid() and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then raise exception 'Usuario nao encontrado.'; end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Escopo da inadimplencia incompleto.';
  end if;

  available_scopes := public.app_view_scope_options();
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug, requested_owner_code
    );
    if target_auth_user_id is null then
      raise exception 'Escopo da inadimplencia invalido.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config('request.jwt.claim.sub', target_auth_user_id::text, true);
    end if;
    payload := public.get_delinquency_overview_v2(null, null);
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_delinquency_overview_v3(text, text)
  from public, anon;
grant execute on function public.get_delinquency_overview_v3(text, text)
  to authenticated;

create or replace function public.get_commitment_overview_v2(
  target_start_date date default null,
  target_end_date date default null,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  requested_profile_slug text := nullif(lower(btrim(coalesce(target_scope_profile_slug, ''))), '');
  requested_owner_code text := nullif(btrim(coalesce(target_scope_owner_code, '')), '');
  target_auth_user_id uuid;
  original_auth_user_id text;
  allowed_profiles constant text[] := array[
    'gerencia', 'coordenador', 'supervisor'
  ]::text[];
  available_scopes jsonb;
  payload jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid() and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then raise exception 'Usuario nao encontrado.'; end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Escopo do compromisso incompleto.';
  end if;

  available_scopes := public.app_view_scope_options(allowed_profiles);
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug, requested_owner_code, allowed_profiles
    );
    if target_auth_user_id is null then
      raise exception 'Escopo do compromisso invalido.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config('request.jwt.claim.sub', target_auth_user_id::text, true);
    end if;
    payload := public.get_commitment_overview(
      target_start_date, target_end_date, null, null
    );
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(original_auth_user_id, ''), true);

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_commitment_overview_v2(
  date, date, text, text
) from public, anon;
grant execute on function public.get_commitment_overview_v2(
  date, date, text, text
) to authenticated;

comment on function public.app_view_scope_options(text[]) is
  'Lista hierarquica comum dos seletores de visao; Gerencia aparece apenas para Diretoria e Outros.';
comment on function public.get_home_dashboard_v4(
  timestamptz, timestamptz, text, text
) is 'Home com espelho real e seletor hierarquico incluindo Gerencia.';
