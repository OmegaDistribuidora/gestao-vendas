alter table public.app_user_module_accesses
  add column if not exists has_filtered_data boolean not null default false;

alter table public.app_user_module_accesses
  alter column filter_value set default '';

create table if not exists public.app_module_filters (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.app_modules (id) on delete cascade,
  label text,
  filter_table text not null,
  filter_column text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_user_module_filter_values (
  id uuid primary key default gen_random_uuid(),
  access_id uuid not null references public.app_user_module_accesses (id) on delete cascade,
  module_filter_id uuid not null references public.app_module_filters (id) on delete cascade,
  filter_value text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (access_id, module_filter_id)
);

create index if not exists idx_app_module_filters_module_id
  on public.app_module_filters (module_id, sort_order);

create index if not exists idx_app_user_module_filter_values_access_id
  on public.app_user_module_filter_values (access_id);

drop trigger if exists set_app_module_filters_updated_at on public.app_module_filters;
create trigger set_app_module_filters_updated_at
before update on public.app_module_filters
for each row
execute function public.set_updated_at();

drop trigger if exists set_app_user_module_filter_values_updated_at on public.app_user_module_filter_values;
create trigger set_app_user_module_filter_values_updated_at
before update on public.app_user_module_filter_values
for each row
execute function public.set_updated_at();

insert into public.app_module_filters (
  module_id,
  label,
  filter_table,
  filter_column,
  sort_order,
  is_active
)
select
  m.id,
  null,
  m.filter_table,
  m.filter_column,
  0,
  true
from public.app_modules m
where coalesce(m.filter_table, '') <> ''
  and coalesce(m.filter_column, '') <> ''
  and not exists (
    select 1
    from public.app_module_filters mf
    where mf.module_id = m.id
  );

insert into public.app_user_module_filter_values (
  access_id,
  module_filter_id,
  filter_value
)
select
  a.id,
  mf.id,
  a.filter_value
from public.app_user_module_accesses a
join lateral (
  select id
  from public.app_module_filters mf
  where mf.module_id = a.module_id
  order by mf.sort_order, mf.created_at
  limit 1
) mf on true
where coalesce(a.filter_value, '') <> ''
  and not exists (
    select 1
    from public.app_user_module_filter_values fv
    where fv.access_id = a.id
  );

update public.app_user_module_accesses a
set has_filtered_data = exists (
  select 1
  from public.app_user_module_filter_values fv
  where fv.access_id = a.id
)
where a.has_filtered_data = false;

create or replace function public.resolve_auth_email(login_identifier text)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  normalized_input text;
  code_match text;
  display_match text;
  display_count integer;
begin
  normalized_input := lower(trim(coalesce(login_identifier, '')));

  if normalized_input = '' then
    return null;
  end if;

  select u.technical_email
    into code_match
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(u.code) = normalized_input
    and coalesce(p.slug, '') = 'vendedor'
  limit 1;

  if code_match is not null then
    return code_match;
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

  select u.technical_email
    into display_match
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(coalesce(u.display_name, '')) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor'
  limit 1;

  return display_match;
end;
$$;

grant execute on function public.resolve_auth_email(text) to anon, authenticated;

grant select, insert, update, delete on public.app_module_filters to authenticated, service_role;
grant select, insert, update, delete on public.app_user_module_filter_values to authenticated, service_role;

alter table public.app_module_filters enable row level security;
alter table public.app_user_module_filter_values enable row level security;

drop policy if exists "module_filters_select_authenticated" on public.app_module_filters;
create policy "module_filters_select_authenticated"
on public.app_module_filters
for select
to authenticated
using (true);

drop policy if exists "module_filters_admin_manage" on public.app_module_filters;
create policy "module_filters_admin_manage"
on public.app_module_filters
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "module_filter_values_select_self_or_admin" on public.app_user_module_filter_values;
create policy "module_filter_values_select_self_or_admin"
on public.app_user_module_filter_values
for select
to authenticated
using (
  exists (
    select 1
    from public.app_user_module_accesses a
    where a.id = access_id
      and (a.user_id = auth.uid() or public.is_admin())
  )
);

drop policy if exists "module_filter_values_admin_manage" on public.app_user_module_filter_values;
create policy "module_filter_values_admin_manage"
on public.app_user_module_filter_values
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());
