alter table public.app_users
  add column if not exists login_alias text;

create unique index if not exists app_users_login_alias_unique_idx
  on public.app_users (lower(login_alias))
  where login_alias is not null and btrim(login_alias) <> '';

create or replace function public.resolve_login_context(login_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  normalized_input text;
  matched_email text;
  matched_requires_admin_password_definition boolean;
  exact_display_count integer;
  alias_count integer;
begin
  normalized_input := lower(trim(coalesce(login_identifier, '')));

  if normalized_input = '' then
    return null;
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(u.code) = normalized_input
    and coalesce(p.slug, '') in ('vendedor', 'admin')
  limit 1;

  if matched_email is not null then
    return jsonb_build_object(
      'technical_email', matched_email,
      'requires_admin_password_definition', matched_requires_admin_password_definition
    );
  end if;

  select count(*)
    into alias_count
  from public.app_users u
  where lower(trim(coalesce(u.login_alias, ''))) = normalized_input
    and trim(coalesce(u.login_alias, '')) <> '';

  if alias_count > 1 then
    raise exception 'Login personalizado duplicado.';
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  where lower(trim(coalesce(u.login_alias, ''))) = normalized_input
    and trim(coalesce(u.login_alias, '')) <> ''
  limit 1;

  if matched_email is not null then
    return jsonb_build_object(
      'technical_email', matched_email,
      'requires_admin_password_definition', matched_requires_admin_password_definition
    );
  end if;

  select count(*)
    into exact_display_count
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(trim(coalesce(u.display_name, ''))) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor';

  if exact_display_count > 1 then
    raise exception 'Nome de exibicao duplicado.';
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(trim(coalesce(u.display_name, ''))) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor'
  limit 1;

  if matched_email is not null then
    return jsonb_build_object(
      'technical_email', matched_email,
      'requires_admin_password_definition', matched_requires_admin_password_definition
    );
  end if;

  select count(*)
    into alias_count
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(
      split_part(
        trim(split_part(coalesce(u.display_name, ''), '/', 1)),
        ' ',
        1
      )
    ) = normalized_input
    and coalesce(p.slug, '') in ('supervisor', 'coordenador')
    and trim(coalesce(u.login_alias, '')) = '';

  if alias_count > 1 then
    raise exception 'Primeiro nome duplicado.';
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(
      split_part(
        trim(split_part(coalesce(u.display_name, ''), '/', 1)),
        ' ',
        1
      )
    ) = normalized_input
    and coalesce(p.slug, '') in ('supervisor', 'coordenador')
    and trim(coalesce(u.login_alias, '')) = ''
  limit 1;

  if matched_email is null then
    return null;
  end if;

  return jsonb_build_object(
    'technical_email', matched_email,
    'requires_admin_password_definition', matched_requires_admin_password_definition
  );
end;
$$;

grant execute on function public.resolve_login_context(text) to anon, authenticated;
