update public.app_users
set
  profile_id = (
    select id
    from public.app_profiles
    where slug = 'admin'
    limit 1
  ),
  is_active = true,
  display_name = coalesce(nullif(display_name, ''), 'Administrador')
where code = 'admin';
