create extension if not exists unaccent with schema extensions;

create or replace function public.normalize_city_key(input_value text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select regexp_replace(
    lower(extensions.unaccent(coalesce(input_value, ''))),
    '[^a-z0-9]+',
    '',
    'g'
  );
$$;

create table if not exists public.app_customer_opportunities (
  tax_id text primary key,
  source_customer_code text not null default '',
  client_name text not null default '',
  fantasy_name text not null default '',
  activity_code text not null default '',
  activity_name text not null default '',
  city text not null default '',
  city_key text not null default '',
  uf text not null default '',
  district text not null default '',
  street text not null default '',
  address_number text not null default '',
  full_address text not null default '',
  postal_code text not null default '',
  credit_limit numeric(18, 2) not null default 0,
  latitude double precision not null,
  longitude double precision not null,
  suppliers jsonb not null default '[]'::jsonb,
  imported_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (length(tax_id) in (11, 14)),
  check (latitude between -90 and 90),
  check (longitude between -180 and 180),
  check (jsonb_typeof(suppliers) = 'array')
);

create index if not exists idx_app_customer_opportunities_city
  on public.app_customer_opportunities (city_key, client_name);

create index if not exists idx_app_customer_opportunities_coordinates
  on public.app_customer_opportunities (latitude, longitude);

drop trigger if exists set_app_customer_opportunities_updated_at
  on public.app_customer_opportunities;
create trigger set_app_customer_opportunities_updated_at
before update on public.app_customer_opportunities
for each row
execute function public.set_updated_at();

alter table public.app_customer_opportunities enable row level security;

grant select, insert, update, delete
  on public.app_customer_opportunities
  to authenticated, service_role;

drop policy if exists "customer_opportunities_admin_manage"
  on public.app_customer_opportunities;
create policy "customer_opportunities_admin_manage"
on public.app_customer_opportunities
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create unlogged table if not exists public.etl_stg_customer_opportunities (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  tax_id text not null,
  source_customer_code text not null default '',
  client_name text not null default '',
  fantasy_name text not null default '',
  activity_code text not null default '',
  activity_name text not null default '',
  city text not null default '',
  city_key text not null default '',
  uf text not null default '',
  district text not null default '',
  street text not null default '',
  address_number text not null default '',
  full_address text not null default '',
  postal_code text not null default '',
  credit_limit numeric(18, 2) not null default 0,
  latitude double precision not null,
  longitude double precision not null,
  suppliers jsonb not null default '[]'::jsonb,
  imported_at timestamptz not null,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, tax_id)
);

alter table public.etl_stg_customer_opportunities enable row level security;

grant select, insert, delete
  on public.etl_stg_customer_opportunities
  to authenticated, service_role;

drop policy if exists "etl_stg_customer_opportunities_admin_manage"
  on public.etl_stg_customer_opportunities;
create policy "etl_stg_customer_opportunities_admin_manage"
on public.etl_stg_customer_opportunities
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.apply_customer_opportunities_sync(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.etl_sync_runs%rowtype;
  v_rows_staged integer := 0;
  v_rows_inserted integer := 0;
  v_rows_updated integer := 0;
  v_rows_deleted integer := 0;
begin
  select *
    into v_run
  from public.etl_sync_runs
  where id = p_run_id;

  if not found then
    raise exception 'Sync run not found.';
  end if;

  select count(*)
    into v_rows_staged
  from public.etl_stg_customer_opportunities
  where run_id = p_run_id;

  if v_rows_staged = 0 then
    raise exception 'Customer opportunities staging is empty; sync aborted.';
  end if;

  select count(*)
    into v_rows_inserted
  from public.etl_stg_customer_opportunities s
  left join public.app_customer_opportunities t on t.tax_id = s.tax_id
  where s.run_id = p_run_id
    and t.tax_id is null;

  select count(*)
    into v_rows_updated
  from public.etl_stg_customer_opportunities s
  join public.app_customer_opportunities t on t.tax_id = s.tax_id
  where s.run_id = p_run_id
    and (
      t.source_customer_code is distinct from s.source_customer_code
      or t.client_name is distinct from s.client_name
      or t.fantasy_name is distinct from s.fantasy_name
      or t.activity_code is distinct from s.activity_code
      or t.activity_name is distinct from s.activity_name
      or t.city is distinct from s.city
      or t.city_key is distinct from s.city_key
      or t.uf is distinct from s.uf
      or t.district is distinct from s.district
      or t.street is distinct from s.street
      or t.address_number is distinct from s.address_number
      or t.full_address is distinct from s.full_address
      or t.postal_code is distinct from s.postal_code
      or t.credit_limit is distinct from s.credit_limit
      or t.latitude is distinct from s.latitude
      or t.longitude is distinct from s.longitude
      or t.suppliers is distinct from s.suppliers
    );

  select count(*)
    into v_rows_deleted
  from public.app_customer_opportunities t
  where not exists (
    select 1
    from public.etl_stg_customer_opportunities s
    where s.run_id = p_run_id
      and s.tax_id = t.tax_id
  );

  delete from public.app_customer_opportunities t
  where not exists (
    select 1
    from public.etl_stg_customer_opportunities s
    where s.run_id = p_run_id
      and s.tax_id = t.tax_id
  );

  insert into public.app_customer_opportunities (
    tax_id,
    source_customer_code,
    client_name,
    fantasy_name,
    activity_code,
    activity_name,
    city,
    city_key,
    uf,
    district,
    street,
    address_number,
    full_address,
    postal_code,
    credit_limit,
    latitude,
    longitude,
    suppliers,
    imported_at
  )
  select
    s.tax_id,
    s.source_customer_code,
    s.client_name,
    s.fantasy_name,
    s.activity_code,
    s.activity_name,
    s.city,
    s.city_key,
    s.uf,
    s.district,
    s.street,
    s.address_number,
    s.full_address,
    s.postal_code,
    s.credit_limit,
    s.latitude,
    s.longitude,
    s.suppliers,
    s.imported_at
  from public.etl_stg_customer_opportunities s
  where s.run_id = p_run_id
  on conflict (tax_id)
  do update
    set source_customer_code = excluded.source_customer_code,
        client_name = excluded.client_name,
        fantasy_name = excluded.fantasy_name,
        activity_code = excluded.activity_code,
        activity_name = excluded.activity_name,
        city = excluded.city,
        city_key = excluded.city_key,
        uf = excluded.uf,
        district = excluded.district,
        street = excluded.street,
        address_number = excluded.address_number,
        full_address = excluded.full_address,
        postal_code = excluded.postal_code,
        credit_limit = excluded.credit_limit,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        suppliers = excluded.suppliers,
        imported_at = excluded.imported_at
  where public.app_customer_opportunities.source_customer_code is distinct from excluded.source_customer_code
     or public.app_customer_opportunities.client_name is distinct from excluded.client_name
     or public.app_customer_opportunities.fantasy_name is distinct from excluded.fantasy_name
     or public.app_customer_opportunities.activity_code is distinct from excluded.activity_code
     or public.app_customer_opportunities.activity_name is distinct from excluded.activity_name
     or public.app_customer_opportunities.city is distinct from excluded.city
     or public.app_customer_opportunities.city_key is distinct from excluded.city_key
     or public.app_customer_opportunities.uf is distinct from excluded.uf
     or public.app_customer_opportunities.district is distinct from excluded.district
     or public.app_customer_opportunities.street is distinct from excluded.street
     or public.app_customer_opportunities.address_number is distinct from excluded.address_number
     or public.app_customer_opportunities.full_address is distinct from excluded.full_address
     or public.app_customer_opportunities.postal_code is distinct from excluded.postal_code
     or public.app_customer_opportunities.credit_limit is distinct from excluded.credit_limit
     or public.app_customer_opportunities.latitude is distinct from excluded.latitude
     or public.app_customer_opportunities.longitude is distinct from excluded.longitude
     or public.app_customer_opportunities.suppliers is distinct from excluded.suppliers;

  truncate table public.etl_stg_customer_opportunities;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_rows_staged,
         rows_inserted = v_rows_inserted,
         rows_updated = v_rows_updated,
         rows_deleted = v_rows_deleted,
         finished_at = timezone('utc', now()),
         error_message = null,
         notes = jsonb_build_object(
           'rows_staged', v_rows_staged,
           'rows_inserted', v_rows_inserted,
           'rows_updated', v_rows_updated,
           'rows_deleted', v_rows_deleted
         )
   where id = p_run_id;

  return jsonb_build_object(
    'rows_staged', v_rows_staged,
    'rows_inserted', v_rows_inserted,
    'rows_updated', v_rows_updated,
    'rows_deleted', v_rows_deleted
  );
end;
$$;

grant execute on function public.apply_customer_opportunities_sync(uuid)
  to authenticated, service_role;

alter function public.apply_customer_opportunities_sync(uuid)
  set statement_timeout = '300s';

create or replace function public.get_customer_opportunities(
  target_city_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_city_key text;
  last_updated_at timestamptz;
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

  if viewer_profile_slug <> 'vendedor' then
    raise exception 'Modulo disponivel apenas para vendedor.';
  end if;

  last_updated_at := public.get_latest_sync_finished_at(
    array['customer_opportunities_sync', 'customer_opportunities_prune']
  );
  requested_city_key := public.normalize_city_key(target_city_key);

  with seller_city_rows as (
    select distinct
      public.normalize_city_key(c.cidade) as city_key,
      max(c.cidade) as city
    from public.app_customer_seller_bases b
    join public.app_customers c on c.codcli = b.codcli
    where b.codusur = viewer_user_code
      and public.normalize_city_key(c.cidade) <> ''
    group by public.normalize_city_key(c.cidade)
  ),
  selectable_city_rows as (
    select
      sc.city_key,
      sc.city,
      count(o.tax_id)::integer as opportunity_count
    from seller_city_rows sc
    join public.app_customer_opportunities o on o.city_key = sc.city_key
    group by sc.city_key, sc.city
  ),
  selected_city as (
    select scr.city_key
    from selectable_city_rows scr
    where (
      requested_city_key <> ''
      and scr.city_key = requested_city_key
    )
    union all
    select scr.city_key
    from selectable_city_rows scr
    where requested_city_key = ''
    order by city_key
    limit 1
  ),
  visible_opportunities as (
    select o.*
    from public.app_customer_opportunities o
    join selected_city sc on sc.city_key = o.city_key
    where o.latitude between -90 and 90
      and o.longitude between -180 and 180
  )
  select jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'viewer_user_code', viewer_user_code,
    'last_updated_at', last_updated_at,
    'selected_city_key', coalesce((
      select sc.city_key from selected_city sc limit 1
    ), ''),
    'served_cities', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'city_key', scr.city_key,
          'city', scr.city,
          'opportunity_count', scr.opportunity_count
        )
        order by scr.city
      )
      from selectable_city_rows scr
    ), '[]'::jsonb),
    'total_opportunities', coalesce((
      select count(*) from visible_opportunities
    ), 0),
    'opportunities', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'tax_id', o.tax_id,
          'client_name', o.client_name,
          'fantasy_name', o.fantasy_name,
          'city', o.city,
          'uf', o.uf,
          'latitude', o.latitude,
          'longitude', o.longitude
        )
        order by o.city, o.client_name, o.tax_id
      )
      from visible_opportunities o
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_customer_opportunities(text)
  to authenticated;

alter function public.get_customer_opportunities(text)
  set statement_timeout = '60s';

create or replace function public.get_customer_opportunity_details(
  target_tax_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  normalized_tax_id text;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if viewer_profile_slug <> 'vendedor' then
    raise exception 'Modulo disponivel apenas para vendedor.';
  end if;

  normalized_tax_id := regexp_replace(coalesce(target_tax_id, ''), '[^0-9]', '', 'g');

  select jsonb_build_object(
    'tax_id', o.tax_id,
    'source_customer_code', o.source_customer_code,
    'client_name', o.client_name,
    'fantasy_name', o.fantasy_name,
    'activity_code', o.activity_code,
    'activity_name', o.activity_name,
    'city', o.city,
    'uf', o.uf,
    'district', o.district,
    'street', o.street,
    'address_number', o.address_number,
    'full_address', o.full_address,
    'postal_code', o.postal_code,
    'credit_limit', o.credit_limit,
    'latitude', o.latitude,
    'longitude', o.longitude,
    'suppliers', o.suppliers
  )
    into payload
  from public.app_customer_opportunities o
  where o.tax_id = normalized_tax_id
    and exists (
      select 1
      from public.app_customer_seller_bases b
      join public.app_customers c on c.codcli = b.codcli
      where b.codusur = viewer_user_code
        and public.normalize_city_key(c.cidade) = o.city_key
    );

  if payload is null then
    raise exception 'Oportunidade nao encontrada no escopo do vendedor.';
  end if;

  return payload;
end;
$$;

grant execute on function public.get_customer_opportunity_details(text)
  to authenticated;

alter function public.get_customer_opportunity_details(text)
  set statement_timeout = '15s';

create or replace function public.prune_customer_opportunities(
  p_run_id uuid,
  p_registered_tax_ids text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows_deleted integer := 0;
  v_registered_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Apenas administradores podem executar esta rotina.';
  end if;

  if not exists (
    select 1
    from public.etl_sync_runs
    where id = p_run_id
  ) then
    raise exception 'Sync run not found.';
  end if;

  v_registered_count := coalesce(cardinality(p_registered_tax_ids), 0);
  if v_registered_count = 0 then
    raise exception 'Registered customer list is empty; prune aborted.';
  end if;

  delete from public.app_customer_opportunities o
  where o.tax_id = any(p_registered_tax_ids);

  get diagnostics v_rows_deleted = row_count;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_registered_count,
         rows_inserted = 0,
         rows_updated = 0,
         rows_deleted = v_rows_deleted,
         finished_at = timezone('utc', now()),
         error_message = null,
         notes = jsonb_build_object(
           'registered_tax_ids_checked', v_registered_count,
           'opportunities_removed', v_rows_deleted
         )
   where id = p_run_id;

  return jsonb_build_object(
    'registered_tax_ids_checked', v_registered_count,
    'opportunities_removed', v_rows_deleted
  );
end;
$$;

grant execute on function public.prune_customer_opportunities(uuid, text[])
  to authenticated, service_role;

alter function public.prune_customer_opportunities(uuid, text[])
  set statement_timeout = '120s';
