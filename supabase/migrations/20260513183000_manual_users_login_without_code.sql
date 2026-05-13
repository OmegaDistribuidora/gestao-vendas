alter table public.app_users
  alter column code drop not null;

update public.app_users u
set login_alias = 'admin'
from public.app_profiles p
where p.id = u.profile_id
  and p.slug = 'admin'
  and coalesce(nullif(btrim(u.login_alias), ''), '') = '';

update public.app_users u
set login_alias = u.code
from public.app_profiles p
where p.id = u.profile_id
  and p.slug not in ('admin', 'vendedor', 'supervisor', 'coordenador')
  and coalesce(nullif(btrim(u.login_alias), ''), '') = ''
  and coalesce(nullif(btrim(u.code), ''), '') <> '';

update public.app_users u
set code = null
from public.app_profiles p
where p.id = u.profile_id
  and p.slug not in ('admin', 'vendedor', 'supervisor', 'coordenador');
