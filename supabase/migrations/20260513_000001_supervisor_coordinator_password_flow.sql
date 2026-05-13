alter table public.app_users
  add column if not exists requires_admin_password_definition boolean not null default false;

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
  display_count integer;
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
    and coalesce(p.slug, '') = 'vendedor'
  limit 1;

  if matched_email is not null then
    return jsonb_build_object(
      'technical_email', matched_email,
      'requires_admin_password_definition', matched_requires_admin_password_definition
    );
  end if;

  select count(*)
    into display_count
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(coalesce(u.display_name, '')) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor';

  if display_count > 1 then
    raise exception 'Nome de exibição duplicado.';
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
  where lower(coalesce(u.display_name, '')) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor'
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
