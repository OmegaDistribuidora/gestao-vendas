alter table public.app_users
  add column if not exists credentials_updated_at timestamptz;

update public.app_users
set credentials_updated_at = coalesce(credentials_updated_at, created_at, timezone('utc', now()))
where credentials_updated_at is null;

alter table public.app_users
  alter column credentials_updated_at set not null;

alter table public.app_users
  alter column credentials_updated_at set default timezone('utc', now());
