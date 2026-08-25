create or replace function public.get_home_dashboard_v3(
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
  viewer_owner_code text;
  requested_profile_slug text;
  requested_owner_code text;
  effective_profile_slug text;
  effective_owner_code text;
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb := '[]'::jsonb;
  home_kpis jsonb := '{}'::jsonb;
  positive_customers jsonb := '{}'::jsonb;
  performance_overview jsonb := '{}'::jsonb;
  commitment_overview jsonb := jsonb_build_object(
    'viewer_profile_slug', '',
    'selected_start_date', null,
    'selected_end_date', null,
    'selected_scope_profile_slug', null,
    'selected_scope_owner_code', null,
    'available_periods', '[]'::jsonb,
    'available_scopes', '[]'::jsonb,
    'items', '[]'::jsonb,
    'last_updated_at', null
  );
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

  requested_profile_slug := nullif(
    lower(btrim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code := nullif(
    btrim(coalesce(target_scope_owner_code, '')),
    ''
  );

  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Filtro da Home incompleto.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_slug', candidate.profile_slug,
        'owner_code', candidate.owner_code,
        'display_name', candidate.display_name,
        'label', candidate.profile_name || ' - '
          || candidate.owner_code || ' - ' || candidate.display_name
      )
      order by
        case candidate.profile_slug
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
  into available_scopes
  from (
    select
      profile.slug as profile_slug,
      case profile.slug
        when 'coordenador' then 'Coordenador'
        when 'supervisor' then 'Supervisor'
        else 'Vendedor'
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
      and profile.slug in ('coordenador', 'supervisor', 'vendedor')
      and case
        when viewer_profile_slug = 'supervisor' then
          profile.slug = 'vendedor'
          and coalesce(app_user.supervisor_code, '') = viewer_owner_code
        when viewer_profile_slug = 'coordenador' then
          profile.slug in ('supervisor', 'vendedor')
          and coalesce(app_user.coordinator_code, '') = viewer_owner_code
        when viewer_profile_slug in ('diretoria', 'outros') then true
        else false
      end
  ) candidate;

  if requested_profile_slug is not null then
    select app_user.auth_user_id, profile.slug, app_user.code
      into target_auth_user_id, effective_profile_slug, effective_owner_code
    from public.app_users app_user
    join public.app_profiles profile on profile.id = app_user.profile_id
    where app_user.is_active
      and app_user.auth_user_id is not null
      and profile.slug = requested_profile_slug
      and app_user.code = requested_owner_code
      and profile.slug in ('coordenador', 'supervisor', 'vendedor')
      and case
        when viewer_profile_slug = 'supervisor' then
          profile.slug = 'vendedor'
          and coalesce(app_user.supervisor_code, '') = viewer_owner_code
        when viewer_profile_slug = 'coordenador' then
          profile.slug in ('supervisor', 'vendedor')
          and coalesce(app_user.coordinator_code, '') = viewer_owner_code
        when viewer_profile_slug in ('diretoria', 'outros') then true
        else false
      end
    limit 1;

    if target_auth_user_id is null then
      raise exception 'Filtro da Home indisponivel para este usuario.';
    end if;
  else
    effective_profile_slug := viewer_profile_slug;
    effective_owner_code := viewer_owner_code;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);

  begin
    if target_auth_user_id is not null then
      perform set_config(
        'request.jwt.claim.sub',
        target_auth_user_id::text,
        true
      );
    end if;

    home_kpis := public.get_home_kpis_v2(window_start, window_end);
    positive_customers := public.get_home_positive_customers(
      window_start,
      window_end
    );
    performance_overview := public.get_performance_overview_v2(
      date(window_start at time zone 'America/Sao_Paulo'),
      null,
      null
    );

    if effective_profile_slug in (
      'supervisor', 'coordenador', 'diretoria', 'outros'
    ) then
      commitment_overview := public.get_commitment_overview(
        null,
        null,
        null,
        null
      );
    end if;
  exception when others then
    perform set_config(
      'request.jwt.claim.sub',
      coalesce(original_auth_user_id, ''),
      true
    );
    raise;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    coalesce(original_auth_user_id, ''),
    true
  );

  return jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'effective_profile_slug', effective_profile_slug,
    'effective_owner_code', effective_owner_code,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes,
    'home_kpis', home_kpis,
    'positive_customers', positive_customers,
    'performance_overview', performance_overview,
    'commitment_overview', commitment_overview
  );
end;
$$;

revoke all on function public.get_home_dashboard_v3(
  timestamptz,
  timestamptz,
  text,
  text
) from public, anon;
grant execute on function public.get_home_dashboard_v3(
  timestamptz,
  timestamptz,
  text,
  text
) to authenticated;

comment on function public.get_home_dashboard_v3(
  timestamptz,
  timestamptz,
  text,
  text
) is
  'Home atomica com filtro hierarquico: supervisor ve vendedores; coordenador ve supervisores e vendedores; diretoria e outros veem todos.';
