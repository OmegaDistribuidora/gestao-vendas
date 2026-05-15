alter table public.app_users
  drop constraint if exists app_users_code_key;

drop index if exists idx_app_users_profile_code_unique;

create unique index idx_app_users_profile_code_unique
  on public.app_users (profile_id, code)
  where code is not null;
