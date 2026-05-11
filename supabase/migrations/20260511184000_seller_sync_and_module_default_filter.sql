alter table public.app_users
  add column if not exists cpf text,
  add column if not exists supervisor_code text,
  add column if not exists supervisor_name text,
  add column if not exists coordinator_code text,
  add column if not exists coordinator_name text,
  add column if not exists origin text not null default 'manual';

alter table public.app_modules
  add column if not exists seller_default_filter_id uuid references public.app_module_filters (id) on delete set null;

create index if not exists idx_app_users_origin_profile
  on public.app_users (origin, profile_id);
