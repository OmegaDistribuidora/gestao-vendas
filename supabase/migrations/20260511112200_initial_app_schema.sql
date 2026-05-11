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
