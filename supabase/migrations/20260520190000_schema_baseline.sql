-- Consolidated baseline generated locally on 2026-05-20.
-- Source of truth for this baseline: migration chain stored in .codex-local/supabase-recovery/migrations_pre_baseline.
-- This file replaces the legacy split migrations to restore a clean Supabase CLI history.


-- >>> BEGIN 20260511112200_initial_app_schema.sql >>>

create extension if not exists pgcrypto;

create table if not exists public.app_profiles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  is_system boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_users (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique,
  technical_email text not null unique,
  display_name text,
  profile_id uuid references public.app_profiles (id),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_modules (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  panel_url text not null default '',
  filter_table text not null default '',
  filter_column text not null default '',
  type text not null default 'acompanhamento_bi',
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_user_module_accesses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  module_id uuid not null references public.app_modules (id) on delete cascade,
  filter_value text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, module_id)
);

create table if not exists public.app_login_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  profile_slug text,
  logged_in_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_module_usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  module_id uuid not null references public.app_modules (id) on delete cascade,
  opened_at timestamptz not null default timezone('utc', now()),
  closed_at timestamptz,
  duration_seconds numeric
);

create index if not exists idx_app_users_profile_id
  on public.app_users (profile_id);

create index if not exists idx_app_user_module_accesses_user_module
  on public.app_user_module_accesses (user_id, module_id);

create index if not exists idx_app_login_events_logged_in_at
  on public.app_login_events (logged_in_at desc);

create index if not exists idx_app_module_usage_events_opened_at
  on public.app_module_usage_events (opened_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists set_app_profiles_updated_at on public.app_profiles;
create trigger set_app_profiles_updated_at
before update on public.app_profiles
for each row
execute function public.set_updated_at();

drop trigger if exists set_app_users_updated_at on public.app_users;
create trigger set_app_users_updated_at
before update on public.app_users
for each row
execute function public.set_updated_at();

drop trigger if exists set_app_modules_updated_at on public.app_modules;
create trigger set_app_modules_updated_at
before update on public.app_modules
for each row
execute function public.set_updated_at();

drop trigger if exists set_app_user_module_accesses_updated_at on public.app_user_module_accesses;
create trigger set_app_user_module_accesses_updated_at
before update on public.app_user_module_accesses
for each row
execute function public.set_updated_at();

insert into public.app_profiles (name, slug, is_system)
values
  ('Admin', 'admin', true),
  ('Vendedor', 'vendedor', true),
  ('Supervisor', 'supervisor', true),
  ('Coordenador', 'coordenador', true),
  ('Diretoria', 'diretoria', true),
  ('Outros', 'outros', true),
  ('Sem perfil', 'sem_perfil', true)
on conflict (slug) do update
set
  name = excluded.name,
  is_system = excluded.is_system,
  updated_at = timezone('utc', now());

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.auth_user_id = auth.uid()
      and u.is_active = true
      and p.slug = 'admin'
  );
$$;

grant execute on function public.is_admin() to authenticated;

create or replace function public.handle_auth_user_upsert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  unassigned_profile_id uuid;
  derived_code text;
  derived_name text;
begin
  select id
    into unassigned_profile_id
  from public.app_profiles
  where slug = 'sem_perfil'
  limit 1;

  derived_code := split_part(coalesce(new.email, ''), '@', 1);
  derived_name := coalesce(
    new.raw_user_meta_data ->> 'display_name',
    nullif(derived_code, '')
  );

  insert into public.app_users (
    auth_user_id,
    code,
    technical_email,
    display_name,
    profile_id,
    is_active
  )
  values (
    new.id,
    derived_code,
    coalesce(new.email, ''),
    derived_name,
    unassigned_profile_id,
    true
  )
  on conflict (auth_user_id) do update
  set
    code = excluded.code,
    technical_email = excluded.technical_email,
    display_name = coalesce(public.app_users.display_name, excluded.display_name),
    updated_at = timezone('utc', now());

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email, raw_user_meta_data on auth.users
for each row
execute function public.handle_auth_user_upsert();

create or replace function public.delete_app_profile(target_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_slug text;
  unassigned_profile_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  select slug into target_slug
  from public.app_profiles
  where id = target_profile_id;

  if target_slug is null then
    raise exception 'Perfil não encontrado.';
  end if;

  if target_slug = 'sem_perfil' then
    raise exception 'O perfil "Sem perfil" não pode ser excluído.';
  end if;

  if exists (
    select 1
    from public.app_profiles
    where id = target_profile_id
      and is_system = true
  ) then
    raise exception 'Perfis do sistema não podem ser excluídos.';
  end if;

  select id
    into unassigned_profile_id
  from public.app_profiles
  where slug = 'sem_perfil'
  limit 1;

  update public.app_users
  set profile_id = unassigned_profile_id
  where profile_id = target_profile_id;

  delete from public.app_profiles
  where id = target_profile_id;
end;
$$;

grant execute on function public.delete_app_profile(uuid) to authenticated;

create or replace function public.get_usage_report(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  select jsonb_build_object(
    'total_logins',
      coalesce((
        select count(*)
        from public.app_login_events le
        where le.logged_in_at between window_start and window_end
      ), 0),
    'total_module_opens',
      coalesce((
        select count(*)
        from public.app_module_usage_events mu
        where mu.opened_at between window_start and window_end
      ), 0),
    'total_minutes',
      coalesce((
        select round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1)
        from public.app_module_usage_events mu
        where mu.opened_at between window_start and window_end
      ), 0),
    'logins_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            coalesce(nullif(u.display_name, ''), u.code) as label,
            count(*)::numeric as value
          from public.app_login_events le
          join public.app_users u on u.auth_user_id = le.user_id
          where le.logged_in_at between window_start and window_end
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'modules_by_open_count',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            m.name as label,
            count(*)::numeric as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'minutes_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            m.name as label,
            round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1) as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_hour',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order
        )
        from (
          select
            lpad(extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as label,
            count(*)::numeric as value,
            extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int as sort_order
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
          group by 1, 3
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_weekday',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order
        )
        from (
          select
            case extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int
              when 0 then 'Domingo'
              when 1 then 'Segunda'
              when 2 then 'Terça'
              when 3 then 'Quarta'
              when 4 then 'Quinta'
              when 5 then 'Sexta'
              else 'Sábado'
            end as label,
            count(*)::numeric as value,
            extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int as sort_order
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
          group by 1, 3
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            coalesce(p.name, 'Sem perfil') as label,
            count(*)::numeric as value
          from public.app_login_events le
          left join public.app_profiles p on p.slug = le.profile_slug
          where le.logged_in_at between window_start and window_end
          group by 1
        ) as bucket
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz) to authenticated;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.app_profiles to authenticated;
grant select, insert, update, delete on public.app_users to authenticated;
grant select, insert, update, delete on public.app_modules to authenticated;
grant select, insert, update, delete on public.app_user_module_accesses to authenticated;
grant select, insert, update, delete on public.app_login_events to authenticated;
grant select, insert, update, delete on public.app_module_usage_events to authenticated;

alter table public.app_profiles enable row level security;
alter table public.app_users enable row level security;
alter table public.app_modules enable row level security;
alter table public.app_user_module_accesses enable row level security;
alter table public.app_login_events enable row level security;
alter table public.app_module_usage_events enable row level security;

drop policy if exists "profiles_select_authenticated" on public.app_profiles;
create policy "profiles_select_authenticated"
on public.app_profiles
for select
to authenticated
using (true);

drop policy if exists "profiles_admin_manage" on public.app_profiles;
create policy "profiles_admin_manage"
on public.app_profiles
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "users_select_self_or_admin" on public.app_users;
create policy "users_select_self_or_admin"
on public.app_users
for select
to authenticated
using (auth.uid() = auth_user_id or public.is_admin());

drop policy if exists "users_update_admin_only" on public.app_users;
create policy "users_update_admin_only"
on public.app_users
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "users_insert_admin_only" on public.app_users;
create policy "users_insert_admin_only"
on public.app_users
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "modules_select_authenticated" on public.app_modules;
create policy "modules_select_authenticated"
on public.app_modules
for select
to authenticated
using (true);

drop policy if exists "modules_admin_manage" on public.app_modules;
create policy "modules_admin_manage"
on public.app_modules
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "accesses_select_self_or_admin" on public.app_user_module_accesses;
create policy "accesses_select_self_or_admin"
on public.app_user_module_accesses
for select
to authenticated
using (auth.uid() = user_id or public.is_admin());

drop policy if exists "accesses_admin_manage" on public.app_user_module_accesses;
create policy "accesses_admin_manage"
on public.app_user_module_accesses
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "login_events_select_admin" on public.app_login_events;
create policy "login_events_select_admin"
on public.app_login_events
for select
to authenticated
using (public.is_admin());

drop policy if exists "login_events_insert_self" on public.app_login_events;
create policy "login_events_insert_self"
on public.app_login_events
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "module_usage_select_self_or_admin" on public.app_module_usage_events;
create policy "module_usage_select_self_or_admin"
on public.app_module_usage_events
for select
to authenticated
using (auth.uid() = user_id or public.is_admin());

drop policy if exists "module_usage_insert_self" on public.app_module_usage_events;
create policy "module_usage_insert_self"
on public.app_module_usage_events
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "module_usage_update_self_or_admin" on public.app_module_usage_events;
create policy "module_usage_update_self_or_admin"
on public.app_module_usage_events
for update
to authenticated
using (auth.uid() = user_id or public.is_admin())
with check (auth.uid() = user_id or public.is_admin());

-- <<< END 20260511112200_initial_app_schema.sql <<<

-- >>> BEGIN 20260511122400_promote_default_admin.sql >>>

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

-- <<< END 20260511122400_promote_default_admin.sql <<<

-- >>> BEGIN 20260511130000_grant_service_role_app_tables.sql >>>

grant usage on schema public to service_role;
grant select, insert, update, delete on public.app_profiles to service_role;
grant select, insert, update, delete on public.app_users to service_role;
grant select, insert, update, delete on public.app_modules to service_role;
grant select, insert, update, delete on public.app_user_module_accesses to service_role;
grant select, insert, update, delete on public.app_login_events to service_role;
grant select, insert, update, delete on public.app_module_usage_events to service_role;

-- <<< END 20260511130000_grant_service_role_app_tables.sql <<<

-- >>> BEGIN 20260511142000_multi_filters_and_login_resolution.sql >>>

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

-- <<< END 20260511142000_multi_filters_and_login_resolution.sql <<<

-- >>> BEGIN 20260511161000_report_user_filter_and_text_fix.sql >>>

update public.app_users
set display_name = replace(display_name, 'UsuÃ¡rio', 'Usuário')
where display_name like '%UsuÃ¡rio%';

update public.app_users
set display_name = replace(display_name, 'Usu�rio', 'Usuário')
where display_name like '%Usu�rio%';

drop function if exists public.get_usage_report(timestamptz, timestamptz, uuid);

create function public.get_usage_report(
  window_start timestamptz,
  window_end timestamptz,
  target_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  select jsonb_build_object(
    'active_users',
      coalesce((
        select count(*)
        from (
          select le.user_id
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          union
          select mu.user_id
          from public.app_module_usage_events mu
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
        ) active_users
        join public.app_users u on u.auth_user_id = active_users.user_id
        where u.is_active = true
      ), 0),
    'total_logins',
      coalesce((
        select count(*)
        from public.app_login_events le
        where le.logged_in_at between window_start and window_end
          and (target_user_id is null or le.user_id = target_user_id)
      ), 0),
    'total_module_opens',
      coalesce((
        select count(*)
        from public.app_module_usage_events mu
        where mu.opened_at between window_start and window_end
          and (target_user_id is null or mu.user_id = target_user_id)
      ), 0),
    'total_minutes',
      coalesce((
        select round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1)
        from public.app_module_usage_events mu
        where mu.opened_at between window_start and window_end
          and (target_user_id is null or mu.user_id = target_user_id)
      ), 0),
    'logins_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            coalesce(nullif(u.display_name, ''), u.code) as label,
            count(*)::numeric as value
          from public.app_login_events le
          join public.app_users u on u.auth_user_id = le.user_id
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'modules_by_open_count',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            m.name as label,
            count(*)::numeric as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'minutes_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            m.name as label,
            round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1) as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_hour',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order
        )
        from (
          select
            lpad(extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as label,
            count(*)::numeric as value,
            extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int as sort_order
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1, 3
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_weekday',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order
        )
        from (
          select
            case extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int
              when 0 then 'Domingo'
              when 1 then 'Segunda'
              when 2 then 'Terça'
              when 3 then 'Quarta'
              when 4 then 'Quinta'
              when 5 then 'Sexta'
              else 'Sábado'
            end as label,
            count(*)::numeric as value,
            extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int as sort_order
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1, 3
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            coalesce(p.name, 'Sem perfil') as label,
            count(*)::numeric as value
          from public.app_login_events le
          left join public.app_profiles p on p.slug = le.profile_slug
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1
        ) as bucket
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid) to authenticated;

-- <<< END 20260511161000_report_user_filter_and_text_fix.sql <<<

-- >>> BEGIN 20260511173000_oracle_sales_kpis.sql >>>

create table if not exists public.app_sales_daily_snapshots (
  id uuid primary key default gen_random_uuid(),
  sales_date date not null,
  numped text not null,
  codcli text not null,
  codusur text not null,
  venda numeric not null default 0,
  volume numeric not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (sales_date, numped, codcli, codusur)
);

create index if not exists idx_app_sales_daily_snapshots_date_user
  on public.app_sales_daily_snapshots (sales_date, codusur);

drop trigger if exists set_app_sales_daily_snapshots_updated_at on public.app_sales_daily_snapshots;
create trigger set_app_sales_daily_snapshots_updated_at
before update on public.app_sales_daily_snapshots
for each row
execute function public.set_updated_at();

grant select, insert, update, delete on public.app_sales_daily_snapshots to authenticated, service_role;

alter table public.app_sales_daily_snapshots enable row level security;

drop policy if exists "sales_daily_snapshots_admin_manage" on public.app_sales_daily_snapshots;
create policy "sales_daily_snapshots_admin_manage"
on public.app_sales_daily_snapshots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.get_seller_home_kpis(target_user_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text;
  current_profile_slug text;
  current_user_code text;
  payload jsonb;
begin
  normalized_code := trim(coalesce(target_user_code, ''));

  if normalized_code = '' then
    return jsonb_build_object(
      'venda_hoje', 0,
      'volume_hoje', 0,
      'pedidos_hoje', 0,
      'positivacao_hoje', 0
    );
  end if;

  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuário não encontrado.';
  end if;

  if current_profile_slug <> 'admin' and current_user_code <> normalized_code then
    raise exception 'Acesso negado.';
  end if;

  select jsonb_build_object(
    'venda_hoje', coalesce(round(sum(s.venda), 2), 0),
    'volume_hoje', coalesce(round(sum(s.volume), 2), 0),
    'pedidos_hoje', coalesce(count(distinct s.numped), 0),
    'positivacao_hoje', coalesce(count(distinct s.codcli), 0)
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date = current_date
    and s.codusur = normalized_code;

  return coalesce(
    payload,
    jsonb_build_object(
      'venda_hoje', 0,
      'volume_hoje', 0,
      'pedidos_hoje', 0,
      'positivacao_hoje', 0
    )
  );
end;
$$;

grant execute on function public.get_seller_home_kpis(text) to authenticated;

-- <<< END 20260511173000_oracle_sales_kpis.sql <<<

-- >>> BEGIN 20260511184000_seller_sync_and_module_default_filter.sql >>>

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

-- <<< END 20260511184000_seller_sync_and_module_default_filter.sql <<<

-- >>> BEGIN 20260513110000_sales_hierarchy_kpis.sql >>>

alter table public.app_sales_daily_snapshots
  add column if not exists codsupervisor text not null default '',
  add column if not exists codgerente text not null default '',
  add column if not exists codfornec text not null default '';

alter table public.app_sales_daily_snapshots
  drop constraint if exists app_sales_daily_snapshots_sales_date_numped_codcli_codusur_key;

truncate table public.app_sales_daily_snapshots;

alter table public.app_sales_daily_snapshots
  drop constraint if exists app_sales_daily_snapshots_unique_snapshot;

alter table public.app_sales_daily_snapshots
  add constraint app_sales_daily_snapshots_unique_snapshot
  unique (sales_date, numped, codcli, codusur, codfornec);

drop index if exists idx_app_sales_daily_snapshots_date_user;

create index if not exists idx_app_sales_daily_snapshots_date_user
  on public.app_sales_daily_snapshots (sales_date, codusur);

create index if not exists idx_app_sales_daily_snapshots_date_supervisor
  on public.app_sales_daily_snapshots (sales_date, codsupervisor);

create index if not exists idx_app_sales_daily_snapshots_date_manager
  on public.app_sales_daily_snapshots (sales_date, codgerente);

create index if not exists idx_app_sales_daily_snapshots_date_supplier
  on public.app_sales_daily_snapshots (sales_date, codfornec);

create or replace function public.get_home_kpis()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuário não encontrado.';
  end if;

  select jsonb_build_object(
    'venda_hoje', coalesce(round(sum(s.venda), 2), 0),
    'volume_hoje', coalesce(round(sum(s.volume), 2), 2),
    'pedidos_hoje', coalesce(count(distinct s.numped), 0),
    'positivacao_hoje', coalesce(count(distinct s.codcli), 0)
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date = current_date
    and (
      case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        else true
      end
    );

  return coalesce(
    payload,
    jsonb_build_object(
      'venda_hoje', 0,
      'volume_hoje', 0,
      'pedidos_hoje', 0,
      'positivacao_hoje', 0
    )
  );
end;
$$;

grant execute on function public.get_home_kpis() to authenticated;

-- <<< END 20260513110000_sales_hierarchy_kpis.sql <<<

-- >>> BEGIN 20260513153000_home_period_and_login_aliases.sql >>>

drop function if exists public.get_home_kpis();

create or replace function public.get_home_kpis(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null then
    raise exception 'Periodo invalido.';
  end if;

  if end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select jsonb_build_object(
    'total_venda', coalesce(round(sum(s.venda), 2), 0),
    'total_volume', coalesce(round(sum(s.volume), 2), 0),
    'total_pedidos', coalesce(count(distinct s.numped), 0),
    'total_positivacao', coalesce(count(distinct s.codcli), 0)
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date between start_date and end_date
    and (
      case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        else true
      end
    );

  return coalesce(
    payload,
    jsonb_build_object(
      'total_venda', 0,
      'total_volume', 0,
      'total_pedidos', 0,
      'total_positivacao', 0
    )
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz) to authenticated;

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
    and coalesce(p.slug, '') in ('supervisor', 'coordenador');

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

-- <<< END 20260513153000_home_period_and_login_aliases.sql <<<

-- >>> BEGIN 20260513170000_login_alias_for_named_roles.sql >>>

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

-- <<< END 20260513170000_login_alias_for_named_roles.sql <<<

-- >>> BEGIN 20260513183000_manual_users_login_without_code.sql >>>

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

-- <<< END 20260513183000_manual_users_login_without_code.sql <<<

-- >>> BEGIN 20260513_000001_supervisor_coordinator_password_flow.sql >>>

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

-- <<< END 20260513_000001_supervisor_coordinator_password_flow.sql <<<

-- >>> BEGIN 20260514_000001_home_last_sales_updated_at.sql >>>

drop function if exists public.get_home_kpis();

create or replace function public.get_home_kpis(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  payload jsonb;
  last_sales_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null then
    raise exception 'Periodo invalido.';
  end if;

  if end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select jsonb_build_object(
    'total_venda', coalesce(round(sum(s.venda), 2), 0),
    'total_volume', coalesce(round(sum(s.volume), 2), 0),
    'total_pedidos', coalesce(count(distinct s.numped), 0),
    'total_positivacao', coalesce(count(distinct s.codcli), 0),
    'last_sales_updated_at', last_sales_updated_at
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date between start_date and end_date
    and (
      case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        else true
      end
    );

  return coalesce(
    payload,
    jsonb_build_object(
      'total_venda', 0,
      'total_volume', 0,
      'total_pedidos', 0,
      'total_positivacao', 0,
      'last_sales_updated_at', last_sales_updated_at
    )
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz) to authenticated;

-- <<< END 20260514_000001_home_last_sales_updated_at.sql <<<

-- >>> BEGIN 20260514_000002_grouped_usage_report.sql >>>

drop function if exists public.get_usage_report(timestamptz, timestamptz, uuid);

create function public.get_usage_report(
  window_start timestamptz,
  window_end timestamptz,
  target_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  with user_scope as (
    select
      u.auth_user_id as user_id,
      coalesce(nullif(u.display_name, ''), nullif(u.code, ''), u.technical_email) as user_label,
      coalesce(p.name, 'Sem perfil') as profile_name,
      coalesce(p.slug, 'sem_perfil') as profile_slug,
      u.is_active
    from public.app_users u
    left join public.app_profiles p on p.id = u.profile_id
    where target_user_id is null or u.auth_user_id = target_user_id
  ),
  profile_order as (
    select *
    from (
      values
        ('admin', 1),
        ('diretoria', 2),
        ('coordenador', 3),
        ('supervisor', 4),
        ('vendedor', 5),
        ('outros', 6),
        ('sem_perfil', 7)
    ) as t(slug, sort_order)
  )
  select jsonb_build_object(
    'active_users',
      coalesce((
        select count(*)
        from (
          select distinct le.user_id
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          union
          select distinct mu.user_id
          from public.app_module_usage_events mu
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
        ) active_users
        join user_scope us on us.user_id = active_users.user_id
        where us.is_active = true
      ), 0),
    'total_logins',
      coalesce((
        select count(*)
        from public.app_login_events le
        where le.logged_in_at between window_start and window_end
          and (target_user_id is null or le.user_id = target_user_id)
      ), 0),
    'active_users_details',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.profile_sort, bucket.label
        )
        from (
          select
            us.user_label as label,
            1::numeric as value,
            coalesce(po.sort_order, 99) as profile_sort
          from (
            select distinct le.user_id
            from public.app_login_events le
            where le.logged_in_at between window_start and window_end
              and (target_user_id is null or le.user_id = target_user_id)
            union
            select distinct mu.user_id
            from public.app_module_usage_events mu
            where mu.opened_at between window_start and window_end
              and (target_user_id is null or mu.user_id = target_user_id)
          ) active_users
          join user_scope us on us.user_id = active_users.user_id
          left join profile_order po on po.slug = us.profile_slug
          where us.is_active = true
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            us.user_label as label,
            count(*)::numeric as value
          from public.app_login_events le
          join user_scope us on us.user_id = le.user_id
          where le.logged_in_at between window_start and window_end
          group by 1
        ) bucket
      ), '[]'::jsonb),
    'logins_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order, bucket.label
        )
        from (
          select
            us.profile_name as label,
            count(*)::numeric as value,
            coalesce(po.sort_order, 99) as sort_order
          from public.app_login_events le
          join user_scope us on us.user_id = le.user_id
          left join profile_order po on po.slug = us.profile_slug
          where le.logged_in_at between window_start and window_end
          group by 1, 3
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              us.profile_name,
              us.user_label,
              count(*)::numeric as value,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'modules_by_open_count_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.module_name,
                'value', bucket.value
              )
              order by bucket.value desc, bucket.module_name
            ) as items
          from (
            select
              us.profile_name,
              m.name as module_name,
              count(*)::numeric as value,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_module_usage_events mu
            join user_scope us on us.user_id = mu.user_id
            join public.app_modules m on m.id = mu.module_id
            left join profile_order po on po.slug = us.profile_slug
            where mu.opened_at between window_start and window_end
            group by 1, 2, 4
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'minutes_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            m.name as label,
            round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1) as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
          group by 1
        ) bucket
      ), '[]'::jsonb),
    'logins_by_hour_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.hour_label,
                'value', bucket.value
              )
              order by bucket.hour_sort
            ) as items
          from (
            select
              us.profile_name,
              lpad(extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as hour_label,
              count(*)::numeric as value,
              extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int as hour_sort,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_weekday_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.weekday_label,
                'value', bucket.value
              )
              order by bucket.weekday_sort
            ) as items
          from (
            select
              us.profile_name,
              case extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int
                when 0 then 'Domingo'
                when 1 then 'Segunda'
                when 2 then 'Terça'
                when 3 then 'Quarta'
                when 4 then 'Quinta'
                when 5 then 'Sexta'
                else 'Sábado'
              end as weekday_label,
              count(*)::numeric as value,
              extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int as weekday_sort,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid) to authenticated;

-- <<< END 20260514_000002_grouped_usage_report.sql <<<

-- >>> BEGIN 20260514_000003_allow_duplicate_codes_across_profiles.sql >>>

alter table public.app_users
  drop constraint if exists app_users_code_key;

drop index if exists idx_app_users_profile_code_unique;

create unique index idx_app_users_profile_code_unique
  on public.app_users (profile_id, code)
  where code is not null;

-- <<< END 20260514_000003_allow_duplicate_codes_across_profiles.sql <<<

-- >>> BEGIN 20260515_000001_financial_snapshots_and_supplier_analysis.sql >>>

create table if not exists public.app_financial_snapshots (
  id uuid primary key default gen_random_uuid(),
  snapshot_type text not null check (snapshot_type in ('F', 'D')),
  snapshot_date date not null,
  numped text not null,
  codcli text not null,
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  faturamento numeric(18, 2) not null default 0,
  volume numeric(18, 4) not null default 0,
  custo numeric(18, 2) not null default 0,
  lucro numeric(18, 2) not null default 0,
  mix numeric(18, 2) not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (snapshot_type, snapshot_date, numped, codcli, codusur, codfornec)
);

create index if not exists idx_app_financial_snapshots_type_date_user
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codusur);

create index if not exists idx_app_financial_snapshots_type_date_supervisor
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codsupervisor);

create index if not exists idx_app_financial_snapshots_type_date_manager
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codgerente);

create index if not exists idx_app_financial_snapshots_type_date_supplier
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codfornec);

drop trigger if exists set_app_financial_snapshots_updated_at on public.app_financial_snapshots;
create trigger set_app_financial_snapshots_updated_at
before update on public.app_financial_snapshots
for each row
execute function public.set_updated_at();

alter table public.app_financial_snapshots enable row level security;

grant select, insert, update, delete on public.app_financial_snapshots to authenticated, service_role;

drop policy if exists "financial_snapshots_admin_manage" on public.app_financial_snapshots;
create policy "financial_snapshots_admin_manage"
on public.app_financial_snapshots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create table if not exists public.app_suppliers (
  codfornec text primary key,
  supplier_name text not null,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_app_suppliers_updated_at on public.app_suppliers;
create trigger set_app_suppliers_updated_at
before update on public.app_suppliers
for each row
execute function public.set_updated_at();

alter table public.app_suppliers enable row level security;

grant select, insert, update, delete on public.app_suppliers to authenticated, service_role;

drop policy if exists "suppliers_admin_manage" on public.app_suppliers;
create policy "suppliers_admin_manage"
on public.app_suppliers
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_home_kpis(timestamptz, timestamptz);
drop function if exists public.get_home_kpis(timestamptz, timestamptz, text);

create or replace function public.get_home_kpis(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  normalized_metric_source text;
  gross_amount numeric(18, 2);
  gross_volume numeric(18, 4);
  gross_orders integer;
  gross_positivation integer;
  return_amount numeric(18, 2);
  return_volume numeric(18, 4);
  return_orders integer;
  return_positivation integer;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');
  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots;

  if normalized_metric_source = 'venda' then
    select
      coalesce(round(sum(s.venda), 2), 0),
      coalesce(round(sum(s.volume), 4), 0),
      coalesce(count(distinct s.numped), 0),
      coalesce(count(distinct s.codcli), 0)
      into gross_amount, gross_volume, gross_orders, gross_positivation
    from public.app_sales_daily_snapshots s
    where s.sales_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then s.codusur = current_user_code
          when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
          else true
        end
      );
  else
    select
      coalesce(round(sum(f.faturamento), 2), 0),
      coalesce(round(sum(f.volume), 4), 0),
      coalesce(count(distinct f.numped), 0),
      coalesce(count(distinct f.codcli), 0)
      into gross_amount, gross_volume, gross_orders, gross_positivation
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then f.codusur = current_user_code
          when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
          else true
        end
      );
  end if;

  select
    coalesce(round(sum(f.faturamento), 2), 0),
    coalesce(round(sum(f.volume), 4), 0),
    coalesce(count(distinct f.numped), 0),
    coalesce(count(distinct f.codcli), 0)
    into return_amount, return_volume, return_orders, return_positivation
  from public.app_financial_snapshots f
  where f.snapshot_type = 'D'
    and f.snapshot_date between start_date and end_date
    and (
      case
        when current_profile_slug = 'vendedor' then f.codusur = current_user_code
        when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
        else true
      end
    );

  return jsonb_build_object(
    'metric_source', normalized_metric_source,
    'gross_amount', coalesce(gross_amount, 0),
    'gross_volume', coalesce(gross_volume, 0),
    'gross_orders', coalesce(gross_orders, 0),
    'gross_positivation', coalesce(gross_positivation, 0),
    'return_amount', coalesce(return_amount, 0),
    'return_volume', coalesce(return_volume, 0),
    'return_orders', coalesce(return_orders, 0),
    'return_positivation', coalesce(return_positivation, 0),
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz, text) to authenticated;

drop function if exists public.get_supplier_analysis(timestamptz, timestamptz, text);

create or replace function public.get_supplier_analysis(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  normalized_metric_source text;
  payload jsonb;
  last_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');
  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  if normalized_metric_source = 'venda' then
    select max(updated_at) into last_updated_at from public.app_sales_daily_snapshots;

    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
          select
            s.codfornec,
            coalesce(sp.supplier_name, s.codfornec) as supplier_name,
            round(sum(s.venda), 2) as gross_amount,
            round(sum(s.volume), 4) as gross_volume,
            count(distinct s.numped) as gross_orders,
            count(distinct s.codcli) as gross_positivation
          from public.app_sales_daily_snapshots s
          left join public.app_suppliers sp on sp.codfornec = s.codfornec
          where s.sales_date between start_date and end_date
            and (
              case
                when current_profile_slug = 'vendedor' then s.codusur = current_user_code
                when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
                when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
                else true
              end
            )
          group by s.codfornec, coalesce(sp.supplier_name, s.codfornec)
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  else
    select max(updated_at) into last_updated_at from public.app_financial_snapshots;

    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
          select
            f.codfornec,
            coalesce(sp.supplier_name, f.codfornec) as supplier_name,
            round(sum(f.faturamento), 2) as gross_amount,
            round(sum(f.volume), 4) as gross_volume,
            count(distinct f.numped) as gross_orders,
            count(distinct f.codcli) as gross_positivation
          from public.app_financial_snapshots f
          left join public.app_suppliers sp on sp.codfornec = f.codfornec
          where f.snapshot_type = 'F'
            and f.snapshot_date between start_date and end_date
            and (
              case
                when current_profile_slug = 'vendedor' then f.codusur = current_user_code
                when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
                when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
                else true
              end
            )
          group by f.codfornec, coalesce(sp.supplier_name, f.codfornec)
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  end if;

  return coalesce(payload, jsonb_build_object(
    'metric_source', normalized_metric_source,
    'last_updated_at', last_updated_at,
    'suppliers', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_supplier_analysis(timestamptz, timestamptz, text) to authenticated;

-- <<< END 20260515_000001_financial_snapshots_and_supplier_analysis.sql <<<

-- >>> BEGIN 20260515_000002_credentials_updated_at.sql >>>

alter table public.app_users
  add column if not exists credentials_updated_at timestamptz;

update public.app_users
set credentials_updated_at = coalesce(credentials_updated_at, created_at, timezone('utc', now()))
where credentials_updated_at is null;

alter table public.app_users
  alter column credentials_updated_at set not null;

alter table public.app_users
  alter column credentials_updated_at set default timezone('utc', now());

-- <<< END 20260515_000002_credentials_updated_at.sql <<<

-- >>> BEGIN 20260515_000003_return_details_module.sql >>>

create table if not exists public.app_return_order_items (
  id uuid primary key default gen_random_uuid(),
  return_date date not null,
  numped text not null,
  codcli text not null,
  client_name text not null default '',
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  return_reason text not null default '',
  codprod text not null,
  product_name text not null default '',
  item_value numeric(18, 2) not null default 0,
  quantity numeric(18, 4) not null default 0,
  volume numeric(18, 4) not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (return_date, numped, codprod, codfornec, codusur, return_reason)
);

create index if not exists idx_app_return_items_date_user
  on public.app_return_order_items (return_date, codusur);

create index if not exists idx_app_return_items_date_supervisor
  on public.app_return_order_items (return_date, codsupervisor);

create index if not exists idx_app_return_items_date_manager
  on public.app_return_order_items (return_date, codgerente);

create index if not exists idx_app_return_items_order
  on public.app_return_order_items (return_date, numped);

drop trigger if exists set_app_return_order_items_updated_at on public.app_return_order_items;
create trigger set_app_return_order_items_updated_at
before update on public.app_return_order_items
for each row
execute function public.set_updated_at();

alter table public.app_return_order_items enable row level security;

grant select, insert, update, delete on public.app_return_order_items to authenticated, service_role;

drop policy if exists "return_items_admin_manage" on public.app_return_order_items;
create policy "return_items_admin_manage"
on public.app_return_order_items
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_return_analysis(timestamptz, timestamptz);

create or replace function public.get_return_analysis(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  payload jsonb;
  last_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select max(updated_at)
    into last_updated_at
  from public.app_return_order_items;

  with filtered as (
    select *
    from public.app_return_order_items ri
    where ri.return_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then ri.codusur = current_user_code
          when current_profile_slug = 'supervisor' then ri.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then ri.codgerente = current_user_code
          else true
        end
      )
  ),
  orders as (
    select
      ri.return_date,
      ri.numped,
      ri.codcli,
      max(ri.client_name) as client_name,
      max(ri.return_reason) as return_reason,
      round(sum(ri.item_value), 2) as total_value,
      round(sum(ri.volume), 4) as total_volume,
      round(sum(ri.quantity), 4) as total_quantity,
      count(*) as item_count
    from filtered ri
    group by ri.return_date, ri.numped, ri.codcli
  )
  select jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', coalesce((select round(sum(item_value), 2) from filtered), 0),
    'total_clients', coalesce((select count(distinct codcli) from filtered), 0),
    'total_volume', coalesce((select round(sum(volume), 4) from filtered), 0),
    'total_orders', coalesce((select count(distinct numped) from filtered), 0),
    'orders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'return_date', o.return_date,
          'numped', o.numped,
          'codcli', o.codcli,
          'client_name', o.client_name,
          'return_reason', o.return_reason,
          'total_value', o.total_value,
          'total_volume', o.total_volume,
          'total_quantity', o.total_quantity,
          'item_count', o.item_count
        )
        order by o.return_date desc, o.total_value desc, o.numped desc
      )
      from orders o
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', 0,
    'total_clients', 0,
    'total_volume', 0,
    'total_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_return_analysis(timestamptz, timestamptz) to authenticated;

drop function if exists public.get_return_order_details(date, text);

create or replace function public.get_return_order_details(
  target_return_date date,
  target_order_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  select jsonb_build_object(
    'items',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'codprod', ri.codprod,
          'product_name', ri.product_name,
          'item_value', ri.item_value,
          'quantity', ri.quantity,
          'volume', ri.volume,
          'return_reason', ri.return_reason
        )
        order by ri.product_name, ri.codprod
      )
      from public.app_return_order_items ri
      where ri.return_date = target_return_date
        and ri.numped = target_order_number
        and (
          case
            when current_profile_slug = 'vendedor' then ri.codusur = current_user_code
            when current_profile_slug = 'supervisor' then ri.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then ri.codgerente = current_user_code
            else true
          end
        )
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object('items', '[]'::jsonb));
end;
$$;

grant execute on function public.get_return_order_details(date, text) to authenticated;

-- <<< END 20260515_000003_return_details_module.sql <<<

-- >>> BEGIN 20260515_000004_return_analysis_seller_name.sql >>>

drop function if exists public.get_return_analysis(timestamptz, timestamptz);

create or replace function public.get_return_analysis(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  payload jsonb;
  last_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select max(updated_at)
    into last_updated_at
  from public.app_return_order_items;

  with sellers as (
    select
      u.code,
      max(u.display_name) as seller_name
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where p.slug = 'vendedor'
    group by u.code
  ),
  filtered as (
    select *
    from public.app_return_order_items ri
    where ri.return_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then ri.codusur = current_user_code
          when current_profile_slug = 'supervisor' then ri.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then ri.codgerente = current_user_code
          else true
        end
      )
  ),
  orders as (
    select
      ri.return_date,
      ri.numped,
      ri.codcli,
      max(ri.client_name) as client_name,
      max(ri.codusur) as codusur,
      coalesce(max(s.seller_name), '') as seller_name,
      max(ri.return_reason) as return_reason,
      round(sum(ri.item_value), 2) as total_value,
      round(sum(ri.volume), 4) as total_volume,
      round(sum(ri.quantity), 4) as total_quantity,
      count(*) as item_count
    from filtered ri
    left join sellers s on s.code = ri.codusur
    group by ri.return_date, ri.numped, ri.codcli
  )
  select jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', coalesce((select round(sum(item_value), 2) from filtered), 0),
    'total_clients', coalesce((select count(distinct codcli) from filtered), 0),
    'total_volume', coalesce((select round(sum(volume), 4) from filtered), 0),
    'total_orders', coalesce((select count(distinct numped) from filtered), 0),
    'orders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'return_date', o.return_date,
          'numped', o.numped,
          'codcli', o.codcli,
          'client_name', o.client_name,
          'codusur', o.codusur,
          'seller_name', o.seller_name,
          'return_reason', o.return_reason,
          'total_value', o.total_value,
          'total_volume', o.total_volume,
          'total_quantity', o.total_quantity,
          'item_count', o.item_count
        )
        order by o.return_date desc, o.total_value desc, o.numped desc
      )
      from orders o
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', 0,
    'total_clients', 0,
    'total_volume', 0,
    'total_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_return_analysis(timestamptz, timestamptz) to authenticated;

-- <<< END 20260515_000004_return_analysis_seller_name.sql <<<

-- >>> BEGIN 20260518_000001_performance_targets_and_sku.sql >>>

create table if not exists public.app_performance_targets (
  id uuid primary key default gen_random_uuid(),
  profile_slug text not null check (profile_slug in ('vendedor', 'supervisor', 'coordenador')),
  owner_code text not null,
  codfornec text not null,
  month_start date not null,
  target_year integer not null check (target_year >= 2026),
  target_month integer not null check (target_month between 1 and 12),
  meta_fin numeric(18, 2) not null default 0,
  meta_pos integer,
  meta_sku integer,
  source_sheet text not null,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (profile_slug, owner_code, codfornec, month_start)
);

create index if not exists idx_app_performance_targets_owner_month
  on public.app_performance_targets (profile_slug, owner_code, month_start desc);

create index if not exists idx_app_performance_targets_supplier
  on public.app_performance_targets (codfornec);

drop trigger if exists set_app_performance_targets_updated_at on public.app_performance_targets;
create trigger set_app_performance_targets_updated_at
before update on public.app_performance_targets
for each row
execute function public.set_updated_at();

alter table public.app_performance_targets enable row level security;

grant select, insert, update, delete on public.app_performance_targets to authenticated, service_role;

drop policy if exists "performance_targets_admin_manage" on public.app_performance_targets;
create policy "performance_targets_admin_manage"
on public.app_performance_targets
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create table if not exists public.app_performance_sku_monthly (
  id uuid primary key default gen_random_uuid(),
  profile_slug text not null check (profile_slug in ('vendedor', 'supervisor', 'coordenador')),
  owner_code text not null,
  codfornec text not null,
  month_start date not null,
  target_year integer not null check (target_year >= 2026),
  target_month integer not null check (target_month between 1 and 12),
  sku_count integer not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (profile_slug, owner_code, codfornec, month_start)
);

create index if not exists idx_app_performance_sku_monthly_owner_month
  on public.app_performance_sku_monthly (profile_slug, owner_code, month_start desc);

create index if not exists idx_app_performance_sku_monthly_supplier
  on public.app_performance_sku_monthly (codfornec);

drop trigger if exists set_app_performance_sku_monthly_updated_at on public.app_performance_sku_monthly;
create trigger set_app_performance_sku_monthly_updated_at
before update on public.app_performance_sku_monthly
for each row
execute function public.set_updated_at();

alter table public.app_performance_sku_monthly enable row level security;

grant select, insert, update, delete on public.app_performance_sku_monthly to authenticated, service_role;

drop policy if exists "performance_sku_monthly_admin_manage" on public.app_performance_sku_monthly;
create policy "performance_sku_monthly_admin_manage"
on public.app_performance_sku_monthly
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_performance_overview(date);

create or replace function public.get_performance_overview(
  target_month_start date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  resolved_month_start date;
  current_month_start date;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  select max(updated_at)
    into last_targets_updated_at
  from public.app_performance_targets t
  where t.profile_slug = current_profile_slug
    and t.owner_code = current_user_code;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_sku_updated_at
  from public.app_performance_sku_monthly s
  where s.profile_slug = current_profile_slug
    and s.owner_code = current_user_code;

  if current_profile_slug not in ('vendedor', 'supervisor', 'coordenador') then
    return jsonb_build_object(
      'supported', false,
      'profile_slug', current_profile_slug,
      'selected_month_start', target_month_start,
      'last_targets_updated_at', last_targets_updated_at,
      'last_sales_updated_at', last_sales_updated_at,
      'last_sku_updated_at', last_sku_updated_at,
      'available_months', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start;
  end if;

  with available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      coalesce(t.meta_fin, 0)::numeric(18, 2) as target_fin,
      t.meta_pos,
      t.meta_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and resolved_month_start is not null
      and t.month_start = resolved_month_start
  ),
  sales_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.venda), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        s.codfornec,
        s.venda,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.sku_count
    from public.app_performance_sku_monthly s
    where s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.target_fin,
      coalesce(sa.actual_fin, 0)::numeric(18, 2) as actual_fin,
      case
        when t.target_fin > 0 then round((coalesce(sa.actual_fin, 0) / t.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      t.meta_pos as target_pos,
      coalesce(sa.actual_pos, 0) as actual_pos,
      case
        when coalesce(t.meta_pos, 0) > 0
          then round((coalesce(sa.actual_pos, 0)::numeric / t.meta_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      t.meta_sku as target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when coalesce(t.meta_sku, 0) > 0
          then round((coalesce(sk.sku_count, 0)::numeric / t.meta_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      case
        when coalesce(t.meta_sku, 0) > 0 then 'sku'
        when coalesce(t.meta_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from targets t
    left join sales_actuals sa on sa.codfornec = t.codfornec
    left join sku_actuals sk on sk.codfornec = t.codfornec
  )
  select jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from merged_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_performance_overview(date) to authenticated;

-- <<< END 20260518_000001_performance_targets_and_sku.sql <<<

-- >>> BEGIN 20260518_000002_performance_metric_source.sql >>>

alter table public.app_performance_sku_monthly
  add column if not exists metric_source text not null default 'venda'
  check (metric_source in ('venda', 'faturamento'));

do $$
declare
  existing_constraint_name text;
begin
  select conname
    into existing_constraint_name
  from pg_constraint
  where conrelid = 'public.app_performance_sku_monthly'::regclass
    and contype = 'u'
    and pg_get_constraintdef(oid) like 'UNIQUE (profile_slug, owner_code, codfornec, month_start)%'
  limit 1;

  if existing_constraint_name is not null then
    execute format(
      'alter table public.app_performance_sku_monthly drop constraint %I',
      existing_constraint_name
    );
  end if;
end;
$$;

alter table public.app_performance_sku_monthly
  add constraint app_performance_sku_monthly_unique_metric_source
  unique (profile_slug, owner_code, codfornec, month_start, metric_source);

drop index if exists idx_app_performance_sku_monthly_owner_month;
create index if not exists idx_app_performance_sku_monthly_owner_source_month
  on public.app_performance_sku_monthly (
    profile_slug,
    owner_code,
    metric_source,
    month_start desc
  );

drop index if exists idx_app_performance_sku_monthly_supplier;
create index if not exists idx_app_performance_sku_monthly_source_supplier
  on public.app_performance_sku_monthly (metric_source, codfornec);

drop function if exists public.get_performance_overview(date);
drop function if exists public.get_performance_overview(date, text);

create or replace function public.get_performance_overview(
  target_month_start date default null,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  resolved_month_start date;
  current_month_start date;
  normalized_metric_source text;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));
  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  select max(updated_at)
    into last_targets_updated_at
  from public.app_performance_targets t
  where t.profile_slug = current_profile_slug
    and t.owner_code = current_user_code;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots
  where snapshot_type = 'F';

  select max(updated_at)
    into last_sku_updated_at
  from public.app_performance_sku_monthly s
  where s.profile_slug = current_profile_slug
    and s.owner_code = current_user_code
    and s.metric_source = normalized_metric_source;

  if current_profile_slug not in ('vendedor', 'supervisor', 'coordenador') then
    return jsonb_build_object(
      'supported', false,
      'profile_slug', current_profile_slug,
      'metric_source', normalized_metric_source,
      'selected_month_start', target_month_start,
      'last_targets_updated_at', last_targets_updated_at,
      'last_sales_updated_at', last_sales_updated_at,
      'last_financial_updated_at', last_financial_updated_at,
      'last_sku_updated_at', last_sku_updated_at,
      'available_months', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start;
  end if;

  with available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      coalesce(t.meta_fin, 0)::numeric(18, 2) as target_fin,
      t.meta_pos,
      t.meta_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and resolved_month_start is not null
      and t.month_start = resolved_month_start
  ),
  actual_rows as (
    select
      source_rows.codfornec,
      source_rows.amount,
      source_rows.codcli
    from (
      select
        s.codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where normalized_metric_source = 'venda'
        and resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where normalized_metric_source = 'venda'
        and resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        f.codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where normalized_metric_source = 'faturamento'
        and f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where normalized_metric_source = 'faturamento'
        and f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )
    ) source_rows
  ),
  actuals as (
    select
      codfornec,
      round(sum(amount), 2) as actual_fin,
      count(distinct codcli) as actual_pos
    from actual_rows
    group by codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.sku_count
    from public.app_performance_sku_monthly s
    where s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and s.metric_source = normalized_metric_source
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.target_fin,
      coalesce(a.actual_fin, 0)::numeric(18, 2) as actual_fin,
      case
        when t.target_fin > 0 then round((coalesce(a.actual_fin, 0) / t.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      t.meta_pos as target_pos,
      coalesce(a.actual_pos, 0) as actual_pos,
      case
        when coalesce(t.meta_pos, 0) > 0
          then round((coalesce(a.actual_pos, 0)::numeric / t.meta_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      t.meta_sku as target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when coalesce(t.meta_sku, 0) > 0
          then round((coalesce(sk.sku_count, 0)::numeric / t.meta_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      case
        when coalesce(t.meta_sku, 0) > 0 then 'sku'
        when coalesce(t.meta_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from targets t
    left join actuals a on a.codfornec = t.codfornec
    left join sku_actuals sk on sk.codfornec = t.codfornec
  )
  select jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from merged_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_performance_overview(date, text) to authenticated;

-- <<< END 20260518_000002_performance_metric_source.sql <<<

-- >>> BEGIN 20260518_000003_performance_profile_rules.sql >>>

drop function if exists public.get_performance_overview(date);
drop function if exists public.get_performance_overview(date, text);

create or replace function public.get_performance_overview(
  target_month_start date default null,
  metric_source text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  resolved_month_start date;
  current_month_start date;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  sku_metric_source text;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  sku_metric_source := case
    when current_profile_slug = 'coordenador' then 'faturamento'
    else 'venda'
  end;

  select max(updated_at)
    into last_targets_updated_at
  from public.app_performance_targets t
  where t.profile_slug = current_profile_slug
    and t.owner_code = current_user_code;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots;

  select max(updated_at)
    into last_sku_updated_at
  from public.app_performance_sku_monthly s
  where s.profile_slug = current_profile_slug
    and s.owner_code = current_user_code
    and s.metric_source = sku_metric_source;

  if current_profile_slug not in ('vendedor', 'supervisor', 'coordenador') then
    return jsonb_build_object(
      'supported', false,
      'profile_slug', current_profile_slug,
      'selected_month_start', target_month_start,
      'last_targets_updated_at', last_targets_updated_at,
      'last_sales_updated_at', last_sales_updated_at,
      'last_financial_updated_at', last_financial_updated_at,
      'last_sku_updated_at', last_sku_updated_at,
      'available_months', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start;
  end if;

  with available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      max(coalesce(t.meta_fin, 0))::numeric(18, 2) as target_fin,
      max(t.meta_pos) as target_pos,
      max(t.meta_sku) as target_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and resolved_month_start is not null
      and t.month_start = resolved_month_start
    group by
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end
  ),
  resolved_targets as (
    select
      t.*,
      case
        when current_profile_slug = 'coordenador' then 'faturamento'
        when current_profile_slug = 'supervisor' and t.codfornec = '1' then 'faturamento'
        else 'venda'
      end as financial_metric_source,
      case
        when current_profile_slug = 'coordenador' then 'faturamento'
        else 'venda'
      end as secondary_metric_source
    from targets t
  ),
  sales_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        s.codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  financial_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        f.codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  return_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as return_amount
    from (
      select
        f.codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.metric_source,
      s.sku_count
    from public.app_performance_sku_monthly s
    where s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.financial_metric_source,
      t.secondary_metric_source,
      t.target_fin,
      round(
        coalesce(
          case
            when t.financial_metric_source = 'faturamento' then fa.actual_fin
            else sa.actual_fin
          end,
          0
        ) + coalesce(ra.return_amount, 0),
        2
      )::numeric(18, 2) as actual_fin,
      t.target_pos,
      coalesce(
        case
          when t.secondary_metric_source = 'faturamento' then fa.actual_pos
          else sa.actual_pos
        end,
        0
      ) as actual_pos,
      t.target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when coalesce(t.target_sku, 0) > 0 then 'sku'
        when coalesce(t.target_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from resolved_targets t
    left join sales_actuals sa on sa.codfornec = t.codfornec
    left join financial_actuals fa on fa.codfornec = t.codfornec
    left join return_actuals ra on ra.codfornec = t.codfornec
    left join sku_actuals sk
      on sk.codfornec = t.codfornec
     and sk.metric_source = t.secondary_metric_source
  ),
  computed_items as (
    select
      item.codfornec,
      item.supplier_name,
      item.financial_metric_source,
      item.secondary_metric_source,
      item.target_fin,
      item.actual_fin,
      case
        when item.target_fin > 0
          then round((item.actual_fin / item.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      item.target_pos,
      item.actual_pos,
      case
        when coalesce(item.target_pos, 0) > 0
          then round((item.actual_pos::numeric / item.target_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      item.target_sku,
      item.actual_sku,
      case
        when coalesce(item.target_sku, 0) > 0
          then round((item.actual_sku::numeric / item.target_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      item.secondary_metric_type
    from merged_items item
  )
  select jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'financial_metric_source', item.financial_metric_source,
          'secondary_metric_source', item.secondary_metric_source,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from computed_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_performance_overview(date, text) to authenticated;

-- <<< END 20260518_000003_performance_profile_rules.sql <<<

-- >>> BEGIN 20260518_000004_performance_admin_selector.sql >>>

drop function if exists public.get_performance_overview(date);
drop function if exists public.get_performance_overview(date, text);

create or replace function public.get_performance_overview(
  target_month_start date default null,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  is_named_profile boolean;
  resolved_month_start date;
  current_month_start date;
  normalized_metric_source text;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  sku_metric_source text;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));
  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  is_named_profile := current_profile_slug in ('vendedor', 'supervisor', 'coordenador');

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  sku_metric_source := case
    when current_profile_slug = 'coordenador' then 'faturamento'
    else 'venda'
  end;

  if is_named_profile then
    select max(updated_at)
      into last_targets_updated_at
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code;

    select max(updated_at)
      into last_sku_updated_at
    from public.app_performance_sku_monthly s
    where s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and s.metric_source = sku_metric_source;
  else
    select max(updated_at)
      into last_targets_updated_at
    from public.app_performance_targets t
    where t.profile_slug = 'coordenador';

    last_sku_updated_at := null;
  end if;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    if is_named_profile then
      select max(t.month_start)
        into resolved_month_start
      from public.app_performance_targets t
      where t.profile_slug = current_profile_slug
        and t.owner_code = current_user_code
        and t.month_start <= current_month_start;
    else
      select max(t.month_start)
        into resolved_month_start
      from public.app_performance_targets t
      where t.profile_slug = 'coordenador'
        and t.month_start <= current_month_start;
    end if;
  end if;

  with available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.month_start <= current_month_start
      and (
        (is_named_profile and t.profile_slug = current_profile_slug and t.owner_code = current_user_code)
        or
        ((not is_named_profile) and t.profile_slug = 'coordenador')
      )
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      case
        when is_named_profile then max(coalesce(t.meta_fin, 0))::numeric(18, 2)
        else coalesce(sum(coalesce(t.meta_fin, 0)), 0)::numeric(18, 2)
      end as target_fin,
      case
        when is_named_profile then max(t.meta_pos)
        else sum(coalesce(t.meta_pos, 0))::integer
      end as target_pos,
      case
        when is_named_profile then max(t.meta_sku)
        else null::integer
      end as target_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where resolved_month_start is not null
      and t.month_start = resolved_month_start
      and (
        (is_named_profile and t.profile_slug = current_profile_slug and t.owner_code = current_user_code)
        or
        ((not is_named_profile) and t.profile_slug = 'coordenador')
      )
    group by
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end
  ),
  resolved_targets as (
    select
      t.*,
      case
        when not is_named_profile then normalized_metric_source
        when current_profile_slug = 'coordenador' then 'faturamento'
        when current_profile_slug = 'supervisor' and t.codfornec = '1' then 'faturamento'
        else 'venda'
      end as financial_metric_source,
      case
        when not is_named_profile then normalized_metric_source
        when current_profile_slug = 'coordenador' then 'faturamento'
        else 'venda'
      end as secondary_metric_source
    from targets t
  ),
  sales_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        s.codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else true
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else true
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  financial_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        f.codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  return_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as return_amount
    from (
      select
        f.codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when current_profile_slug = 'vendedor' then f.codusur = current_user_code
            when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
            else true
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.metric_source,
      s.sku_count
    from public.app_performance_sku_monthly s
    where is_named_profile
      and s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.financial_metric_source,
      t.secondary_metric_source,
      t.target_fin,
      round(
        coalesce(
          case
            when t.financial_metric_source = 'faturamento' then fa.actual_fin
            else sa.actual_fin
          end,
          0
        ) + coalesce(ra.return_amount, 0),
        2
      )::numeric(18, 2) as actual_fin,
      t.target_pos,
      coalesce(
        case
          when t.secondary_metric_source = 'faturamento' then fa.actual_pos
          else sa.actual_pos
        end,
        0
      ) as actual_pos,
      t.target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when not is_named_profile and coalesce(t.target_pos, 0) > 0 then 'positivacao'
        when coalesce(t.target_sku, 0) > 0 then 'sku'
        when coalesce(t.target_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from resolved_targets t
    left join sales_actuals sa on sa.codfornec = t.codfornec
    left join financial_actuals fa on fa.codfornec = t.codfornec
    left join return_actuals ra on ra.codfornec = t.codfornec
    left join sku_actuals sk
      on sk.codfornec = t.codfornec
     and sk.metric_source = t.secondary_metric_source
  ),
  computed_items as (
    select
      item.codfornec,
      item.supplier_name,
      item.financial_metric_source,
      item.secondary_metric_source,
      item.target_fin,
      item.actual_fin,
      case
        when item.target_fin > 0
          then round((item.actual_fin / item.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      item.target_pos,
      item.actual_pos,
      case
        when coalesce(item.target_pos, 0) > 0
          then round((item.actual_pos::numeric / item.target_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      item.target_sku,
      item.actual_sku,
      case
        when coalesce(item.target_sku, 0) > 0
          then round((item.actual_sku::numeric / item.target_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      item.secondary_metric_type
    from merged_items item
  )
  select jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'financial_metric_source', item.financial_metric_source,
          'secondary_metric_source', item.secondary_metric_source,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from computed_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_performance_overview(date, text) to authenticated;

-- <<< END 20260518_000004_performance_admin_selector.sql <<<

-- >>> BEGIN 20260519_000001_remove_power_bi_integration.sql >>>

drop table if exists public.app_user_module_filter_values cascade;
drop table if exists public.app_user_module_accesses cascade;
drop table if exists public.app_module_filters cascade;
drop table if exists public.app_module_usage_events cascade;
drop table if exists public.app_modules cascade;

drop function if exists public.get_usage_report(timestamptz, timestamptz, uuid);

create function public.get_usage_report(
  window_start timestamptz,
  window_end timestamptz,
  target_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  with user_scope as (
    select
      u.auth_user_id as user_id,
      coalesce(nullif(u.display_name, ''), nullif(u.code, ''), u.technical_email) as user_label,
      coalesce(p.name, 'Sem perfil') as profile_name,
      coalesce(p.slug, 'sem_perfil') as profile_slug,
      u.is_active
    from public.app_users u
    left join public.app_profiles p on p.id = u.profile_id
    where target_user_id is null or u.auth_user_id = target_user_id
  ),
  profile_order as (
    select *
    from (
      values
        ('admin', 1),
        ('diretoria', 2),
        ('coordenador', 3),
        ('supervisor', 4),
        ('vendedor', 5),
        ('outros', 6),
        ('sem_perfil', 7)
    ) as t(slug, sort_order)
  )
  select jsonb_build_object(
    'active_users',
      coalesce((
        select count(*)
        from (
          select distinct le.user_id
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
        ) active_users
        join user_scope us on us.user_id = active_users.user_id
        where us.is_active = true
      ), 0),
    'total_logins',
      coalesce((
        select count(*)
        from public.app_login_events le
        where le.logged_in_at between window_start and window_end
          and (target_user_id is null or le.user_id = target_user_id)
      ), 0),
    'active_users_details',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.profile_sort, bucket.label
        )
        from (
          select
            us.user_label as label,
            1::numeric as value,
            coalesce(po.sort_order, 99) as profile_sort
          from (
            select distinct le.user_id
            from public.app_login_events le
            where le.logged_in_at between window_start and window_end
              and (target_user_id is null or le.user_id = target_user_id)
          ) active_users
          join user_scope us on us.user_id = active_users.user_id
          left join profile_order po on po.slug = us.profile_slug
          where us.is_active = true
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            us.user_label as label,
            count(*)::numeric as value
          from public.app_login_events le
          join user_scope us on us.user_id = le.user_id
          where le.logged_in_at between window_start and window_end
          group by 1
        ) bucket
      ), '[]'::jsonb),
    'logins_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order, bucket.label
        )
        from (
          select
            us.profile_name as label,
            count(*)::numeric as value,
            coalesce(po.sort_order, 99) as sort_order
          from public.app_login_events le
          join user_scope us on us.user_id = le.user_id
          left join profile_order po on po.slug = us.profile_slug
          where le.logged_in_at between window_start and window_end
          group by 1, 3
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              us.profile_name,
              us.user_label,
              count(*)::numeric as value,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_hour_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.hour_label,
                'value', bucket.value
              )
              order by bucket.hour_sort
            ) as items
          from (
            select
              us.profile_name,
              lpad(extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as hour_label,
              count(*)::numeric as value,
              extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int as hour_sort,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_weekday_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.weekday_label,
                'value', bucket.value
              )
              order by bucket.weekday_sort
            ) as items
          from (
            select
              us.profile_name,
              case extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int
                when 0 then 'Domingo'
                when 1 then 'Segunda'
                when 2 then 'Terça'
                when 3 then 'Quarta'
                when 4 then 'Quinta'
                when 5 then 'Sexta'
                else 'Sábado'
              end as weekday_label,
              count(*)::numeric as value,
              extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int as weekday_sort,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid) to authenticated;

-- <<< END 20260519_000001_remove_power_bi_integration.sql <<<

-- >>> BEGIN 20260520_000001_performance_scope_selector.sql >>>

drop function if exists public.get_performance_overview(date, text, text, text);

create or replace function public.get_performance_overview(
  target_month_start date,
  metric_source text,
  target_scope_profile_slug text,
  target_scope_owner_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_profile_slug text;
  requested_owner_code text;
  effective_profile_slug text;
  effective_owner_code text;
  aggregate_all_mode boolean := false;
  is_effective_named_profile boolean;
  resolved_month_start date;
  current_month_start date;
  normalized_metric_source text;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  sku_metric_source text;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));
  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  requested_profile_slug := nullif(
    lower(trim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code := nullif(trim(coalesce(target_scope_owner_code, '')), '');

  if viewer_profile_slug = 'vendedor' then
    effective_profile_slug := 'vendedor';
    effective_owner_code := viewer_user_code;
  elsif viewer_profile_slug = 'supervisor' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'supervisor';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'vendedor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'vendedor'
        and u.code = requested_owner_code
        and coalesce(u.supervisor_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'vendedor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de performance invalido para supervisor.';
    end if;
  elsif viewer_profile_slug = 'coordenador' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'coordenador';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'supervisor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'supervisor'
        and u.code = requested_owner_code
        and coalesce(u.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'supervisor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de performance invalido para coordenador.';
    end if;
  elsif viewer_profile_slug in ('admin', 'diretoria', 'outros') then
    if requested_profile_slug is null or requested_owner_code is null then
      aggregate_all_mode := true;
      effective_profile_slug := viewer_profile_slug;
      effective_owner_code := null;
    elsif requested_profile_slug in ('coordenador', 'supervisor', 'vendedor')
      and exists (
        select 1
        from public.app_users u
        join public.app_profiles p on p.id = u.profile_id
        where u.is_active = true
          and p.slug = requested_profile_slug
          and u.code = requested_owner_code
      ) then
      effective_profile_slug := requested_profile_slug;
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de performance invalido para o perfil atual.';
    end if;
  else
    aggregate_all_mode := true;
    effective_profile_slug := viewer_profile_slug;
    effective_owner_code := null;
  end if;

  is_effective_named_profile := effective_profile_slug in (
    'vendedor',
    'supervisor',
    'coordenador'
  );

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  sku_metric_source := case
    when effective_profile_slug = 'coordenador' then 'faturamento'
    else 'venda'
  end;

  if is_effective_named_profile then
    select max(updated_at)
      into last_targets_updated_at
    from public.app_performance_targets t
    where t.profile_slug = effective_profile_slug
      and t.owner_code = effective_owner_code;

    select max(updated_at)
      into last_sku_updated_at
    from public.app_performance_sku_monthly s
    where s.profile_slug = effective_profile_slug
      and s.owner_code = effective_owner_code
      and s.metric_source = sku_metric_source;
  else
    select max(updated_at)
      into last_targets_updated_at
    from public.app_performance_targets t
    where t.profile_slug = 'coordenador';

    last_sku_updated_at := null;
  end if;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.month_start <= current_month_start
      and (
        (is_effective_named_profile and t.profile_slug = effective_profile_slug and t.owner_code = effective_owner_code)
        or
        ((not is_effective_named_profile) and t.profile_slug = 'coordenador')
      );
  end if;

  with available_scope_rows as (
    select
      p.slug as profile_slug,
      u.code as owner_code,
      coalesce(nullif(btrim(u.display_name), ''), u.code) as display_name,
      trim(
        case
          when btrim(coalesce(u.code, '')) <> '' and btrim(coalesce(u.display_name, '')) <> ''
            then u.code || ' - ' || u.display_name
          when btrim(coalesce(u.display_name, '')) <> ''
            then u.display_name
          else u.code
        end
      ) as label
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.is_active = true
      and (
        (viewer_profile_slug = 'supervisor' and p.slug = 'vendedor' and coalesce(u.supervisor_code, '') = viewer_user_code)
        or
        (viewer_profile_slug = 'coordenador' and p.slug = 'supervisor' and coalesce(u.coordinator_code, '') = viewer_user_code)
        or
        (viewer_profile_slug in ('admin', 'diretoria', 'outros') and p.slug in ('coordenador', 'supervisor', 'vendedor'))
      )
  ),
  available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.month_start <= current_month_start
      and (
        (is_effective_named_profile and t.profile_slug = effective_profile_slug and t.owner_code = effective_owner_code)
        or
        ((not is_effective_named_profile) and t.profile_slug = 'coordenador')
      )
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      case
        when is_effective_named_profile then max(coalesce(t.meta_fin, 0))::numeric(18, 2)
        else coalesce(sum(coalesce(t.meta_fin, 0)), 0)::numeric(18, 2)
      end as target_fin,
      case
        when is_effective_named_profile then max(t.meta_pos)
        else sum(coalesce(t.meta_pos, 0))::integer
      end as target_pos,
      case
        when is_effective_named_profile then max(t.meta_sku)
        else null::integer
      end as target_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where resolved_month_start is not null
      and t.month_start = resolved_month_start
      and (
        (is_effective_named_profile and t.profile_slug = effective_profile_slug and t.owner_code = effective_owner_code)
        or
        ((not is_effective_named_profile) and t.profile_slug = 'coordenador')
      )
    group by
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end
  ),
  resolved_targets as (
    select
      t.*,
      case
        when not is_effective_named_profile then normalized_metric_source
        when effective_profile_slug = 'coordenador' then 'faturamento'
        when effective_profile_slug = 'supervisor' and t.codfornec = '1' then 'faturamento'
        else 'venda'
      end as financial_metric_source,
      case
        when not is_effective_named_profile then normalized_metric_source
        when effective_profile_slug = 'coordenador' then 'faturamento'
        else 'venda'
      end as secondary_metric_source
    from targets t
  ),
  sales_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        s.codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when effective_profile_slug = 'vendedor' then s.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then s.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then s.codgerente = effective_owner_code
            else true
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda as amount,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when effective_profile_slug = 'vendedor' then s.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then s.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then s.codgerente = effective_owner_code
            else true
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  financial_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        f.codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount,
        f.codcli
      from public.app_financial_snapshots f
      where f.snapshot_type = 'F'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  return_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.amount), 2) as return_amount
    from (
      select
        f.codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
          end
        )

      union all

      select
        '1' as codfornec,
        f.faturamento as amount
      from public.app_financial_snapshots f
      where f.snapshot_type = 'D'
        and resolved_month_start is not null
        and f.snapshot_date >= resolved_month_start
        and f.snapshot_date < (resolved_month_start + interval '1 month')::date
        and (
          case
            when effective_profile_slug = 'vendedor' then f.codusur = effective_owner_code
            when effective_profile_slug = 'supervisor' then f.codsupervisor = effective_owner_code
            when effective_profile_slug = 'coordenador' then f.codgerente = effective_owner_code
            else true
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.metric_source,
      s.sku_count
    from public.app_performance_sku_monthly s
    where is_effective_named_profile
      and s.profile_slug = effective_profile_slug
      and s.owner_code = effective_owner_code
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.financial_metric_source,
      t.secondary_metric_source,
      t.target_fin,
      round(
        coalesce(
          case
            when t.financial_metric_source = 'faturamento' then fa.actual_fin
            else sa.actual_fin
          end,
          0
        ) + coalesce(ra.return_amount, 0),
        2
      )::numeric(18, 2) as actual_fin,
      t.target_pos,
      coalesce(
        case
          when t.secondary_metric_source = 'faturamento' then fa.actual_pos
          else sa.actual_pos
        end,
        0
      ) as actual_pos,
      t.target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when not is_effective_named_profile and coalesce(t.target_pos, 0) > 0 then 'positivacao'
        when coalesce(t.target_sku, 0) > 0 then 'sku'
        when coalesce(t.target_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from resolved_targets t
    left join sales_actuals sa on sa.codfornec = t.codfornec
    left join financial_actuals fa on fa.codfornec = t.codfornec
    left join return_actuals ra on ra.codfornec = t.codfornec
    left join sku_actuals sk
      on sk.codfornec = t.codfornec
     and sk.metric_source = t.secondary_metric_source
  ),
  computed_items as (
    select
      item.codfornec,
      item.supplier_name,
      item.financial_metric_source,
      item.secondary_metric_source,
      item.target_fin,
      item.actual_fin,
      case
        when item.target_fin > 0
          then round((item.actual_fin / item.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      item.target_pos,
      item.actual_pos,
      case
        when coalesce(item.target_pos, 0) > 0
          then round((item.actual_pos::numeric / item.target_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      item.target_sku,
      item.actual_sku,
      case
        when coalesce(item.target_sku, 0) > 0
          then round((item.actual_sku::numeric / item.target_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      item.secondary_metric_type
    from merged_items item
  )
  select jsonb_build_object(
    'supported', true,
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_scopes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile_slug', scope.profile_slug,
          'owner_code', scope.owner_code,
          'display_name', scope.display_name,
          'label', scope.label
        )
        order by
          case scope.profile_slug
            when 'coordenador' then 1
            when 'supervisor' then 2
            when 'vendedor' then 3
            else 9
          end,
          scope.display_name,
          scope.owner_code
      )
      from available_scope_rows scope
    ), '[]'::jsonb),
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'financial_metric_source', item.financial_metric_source,
          'secondary_metric_source', item.secondary_metric_source,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from computed_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'metric_source', normalized_metric_source,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_scopes', '[]'::jsonb,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

create or replace function public.get_performance_overview(
  target_month_start date default null,
  metric_source text default 'venda'
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select public.get_performance_overview(
    target_month_start,
    metric_source,
    null,
    null
  );
$$;

grant execute on function public.get_performance_overview(date, text, text, text) to authenticated;
grant execute on function public.get_performance_overview(date, text) to authenticated;

-- <<< END 20260520_000001_performance_scope_selector.sql <<<
