-- Perfis amplos, como Gerencia, podem nao possuir codigo comercial.
-- Usa o id interno do app_user somente como chave estavel do seletor nesses
-- casos, sem alterar o significado de owner_code para a hierarquia comercial.

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
        'owner_code', candidate.scope_key,
        'display_name', candidate.display_name,
        'label', case
          when candidate.profile_slug = 'gerencia' then
            'Gerencia - ' || candidate.display_name
          else candidate.profile_name || ' - ' || candidate.scope_key ||
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
        candidate.scope_key
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
      case
        when profile.slug = 'gerencia' then coalesce(
          nullif(btrim(app_user.code), ''),
          app_user.id::text
        )
        else btrim(app_user.code)
      end as scope_key,
      coalesce(
        nullif(btrim(app_user.display_name), ''),
        nullif(btrim(app_user.code), ''),
        'Gerencia'
      ) as display_name
    from public.app_users app_user
    join public.app_profiles profile on profile.id = app_user.profile_id
    where app_user.is_active
      and app_user.auth_user_id is not null
      and profile.slug = any(normalized_allowed_profiles)
      and (
        profile.slug = 'gerencia'
        or nullif(btrim(app_user.code), '') is not null
      )
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
    and case
      when profile.slug = 'gerencia' then coalesce(
        nullif(btrim(app_user.code), ''),
        app_user.id::text
      )
      else btrim(app_user.code)
    end = normalized_target_owner
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

revoke all on function public.app_view_scope_options(text[]) from public, anon;
grant execute on function public.app_view_scope_options(text[])
  to authenticated, service_role;

revoke all on function public.app_resolve_view_scope_auth_user(
  text, text, text[]
) from public, anon;
grant execute on function public.app_resolve_view_scope_auth_user(
  text, text, text[]
) to authenticated, service_role;

comment on function public.app_view_scope_options(text[]) is
  'Lista segura de visoes; Gerencia usa app_user.id quando nao possui codigo.';
