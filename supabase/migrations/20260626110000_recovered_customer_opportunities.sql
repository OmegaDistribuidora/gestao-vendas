create table if not exists public.app_customer_recovered_opportunities (
  tax_id text primary key,
  source_customer_code text not null default '',
  client_name text not null default '',
  fantasy_name text not null default '',
  activity_code text not null default '',
  activity_name text not null default '',
  city text not null default '',
  uf text not null default '',
  district text not null default '',
  full_address text not null default '',
  credit_limit numeric(18, 2) not null default 0,
  market_potential numeric(18, 2),
  market_potential_order_count integer not null default 0,
  opportunity_imported_at timestamptz,
  opportunity_created_at timestamptz,
  opportunity_updated_at timestamptz,
  recovered_at timestamptz not null default timezone('utc', now()),
  last_prune_run_id uuid references public.etl_sync_runs (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (length(tax_id) in (11, 14))
);

create index if not exists idx_app_customer_recovered_opportunities_recovered_at
  on public.app_customer_recovered_opportunities (recovered_at desc);

create index if not exists idx_app_customer_recovered_opportunities_city
  on public.app_customer_recovered_opportunities (city, district);

drop trigger if exists set_app_customer_recovered_opportunities_updated_at
  on public.app_customer_recovered_opportunities;
create trigger set_app_customer_recovered_opportunities_updated_at
before update on public.app_customer_recovered_opportunities
for each row
execute function public.set_updated_at();

alter table public.app_customer_recovered_opportunities enable row level security;

grant select, insert, update
  on public.app_customer_recovered_opportunities
  to authenticated, service_role;

create or replace function public.can_access_recovered_customer_opportunities()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.auth_user_id = auth.uid()
      and u.is_active
      and p.slug not in ('vendedor', 'supervisor', 'coordenador')
  );
$$;

grant execute on function public.can_access_recovered_customer_opportunities()
  to authenticated;

drop policy if exists "recovered_opportunities_select_allowed"
  on public.app_customer_recovered_opportunities;
create policy "recovered_opportunities_select_allowed"
on public.app_customer_recovered_opportunities
for select
to authenticated
using (public.can_access_recovered_customer_opportunities());

drop policy if exists "recovered_opportunities_admin_manage"
  on public.app_customer_recovered_opportunities;
create policy "recovered_opportunities_admin_manage"
on public.app_customer_recovered_opportunities
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.archive_recovered_customer_opportunities(
  p_run_id uuid,
  p_tax_ids text[] default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows_archived integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Apenas administradores podem executar esta rotina.';
  end if;

  insert into public.app_customer_recovered_opportunities (
    tax_id,
    source_customer_code,
    client_name,
    fantasy_name,
    activity_code,
    activity_name,
    city,
    uf,
    district,
    full_address,
    credit_limit,
    market_potential,
    market_potential_order_count,
    opportunity_imported_at,
    opportunity_created_at,
    opportunity_updated_at,
    recovered_at,
    last_prune_run_id
  )
  select
    o.tax_id,
    o.source_customer_code,
    o.client_name,
    o.fantasy_name,
    o.activity_code,
    o.activity_name,
    o.city,
    o.uf,
    o.district,
    o.full_address,
    o.credit_limit,
    o.market_potential,
    o.market_potential_order_count,
    o.imported_at,
    o.created_at,
    o.updated_at,
    timezone('utc', now()),
    p_run_id
  from public.app_customer_opportunities o
  where p_tax_ids is null
     or o.tax_id = any(p_tax_ids)
  on conflict (tax_id)
  do update
    set source_customer_code = excluded.source_customer_code,
        client_name = excluded.client_name,
        fantasy_name = excluded.fantasy_name,
        activity_code = excluded.activity_code,
        activity_name = excluded.activity_name,
        city = excluded.city,
        uf = excluded.uf,
        district = excluded.district,
        full_address = excluded.full_address,
        credit_limit = excluded.credit_limit,
        market_potential = excluded.market_potential,
        market_potential_order_count = excluded.market_potential_order_count,
        opportunity_imported_at = excluded.opportunity_imported_at,
        opportunity_created_at = excluded.opportunity_created_at,
        opportunity_updated_at = excluded.opportunity_updated_at,
        last_prune_run_id = excluded.last_prune_run_id;

  get diagnostics v_rows_archived = row_count;
  return v_rows_archived;
end;
$$;

grant execute on function public.archive_recovered_customer_opportunities(uuid, text[])
  to authenticated, service_role;

create or replace function public.apply_customer_opportunities_sync(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows_staged integer := 0;
  v_rows_inserted integer := 0;
  v_rows_updated integer := 0;
  v_rows_deleted integer := 0;
  v_rows_archived integer := 0;
begin
  if not exists (
    select 1 from public.etl_sync_runs where id = p_run_id
  ) then
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
      or t.market_potential is distinct from s.market_potential
      or t.market_potential_order_count is distinct from s.market_potential_order_count
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

  select public.archive_recovered_customer_opportunities(
    p_run_id,
    array(
      select t.tax_id
      from public.app_customer_opportunities t
      where not exists (
        select 1
        from public.etl_stg_customer_opportunities s
        where s.run_id = p_run_id
          and s.tax_id = t.tax_id
      )
    )
  )
    into v_rows_archived;

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
    market_potential,
    market_potential_order_count,
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
    s.market_potential,
    s.market_potential_order_count,
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
        market_potential = excluded.market_potential,
        market_potential_order_count = excluded.market_potential_order_count,
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
     or public.app_customer_opportunities.market_potential is distinct from excluded.market_potential
     or public.app_customer_opportunities.market_potential_order_count is distinct from excluded.market_potential_order_count
     or public.app_customer_opportunities.latitude is distinct from excluded.latitude
     or public.app_customer_opportunities.longitude is distinct from excluded.longitude
     or public.app_customer_opportunities.suppliers is distinct from excluded.suppliers;

  delete from public.etl_stg_customer_opportunities
  where run_id = p_run_id;

  if not exists (select 1 from public.etl_stg_customer_opportunities) then
    truncate table public.etl_stg_customer_opportunities;
  end if;

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
           'rows_deleted', v_rows_deleted,
           'rows_archived_as_recovered', v_rows_archived
         )
   where id = p_run_id;

  return jsonb_build_object(
    'rows_staged', v_rows_staged,
    'rows_inserted', v_rows_inserted,
    'rows_updated', v_rows_updated,
    'rows_deleted', v_rows_deleted,
    'rows_archived_as_recovered', v_rows_archived
  );
end;
$$;

alter function public.apply_customer_opportunities_sync(uuid)
  set statement_timeout = '300s';

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
  v_rows_archived integer := 0;
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

  select public.archive_recovered_customer_opportunities(
    p_run_id,
    p_registered_tax_ids
  )
    into v_rows_archived;

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
           'opportunities_removed', v_rows_deleted,
           'opportunities_archived_as_recovered', v_rows_archived
         )
   where id = p_run_id;

  return jsonb_build_object(
    'registered_tax_ids_checked', v_registered_count,
    'opportunities_removed', v_rows_deleted,
    'opportunities_archived_as_recovered', v_rows_archived
  );
end;
$$;

grant execute on function public.prune_customer_opportunities(uuid, text[])
  to authenticated, service_role;

alter function public.prune_customer_opportunities(uuid, text[])
  set statement_timeout = '120s';

create or replace function public.get_recovered_customer_opportunities(
  target_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  normalized_search text := lower(extensions.unaccent(btrim(coalesce(target_search, ''))));
  last_updated_at timestamptz;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if coalesce(viewer_profile_slug, '') = '' then
    raise exception 'Usuario nao encontrado.';
  end if;

  if viewer_profile_slug in ('vendedor', 'supervisor', 'coordenador') then
    raise exception 'Modulo disponivel apenas para perfis administrativos.';
  end if;

  last_updated_at := public.get_latest_sync_finished_at(
    array['customer_opportunities_sync', 'customer_opportunities_prune']
  );

  with filtered as (
    select r.*
    from public.app_customer_recovered_opportunities r
    where normalized_search = ''
       or lower(extensions.unaccent(r.tax_id)) like '%' || normalized_search || '%'
       or lower(extensions.unaccent(r.client_name)) like '%' || normalized_search || '%'
       or lower(extensions.unaccent(r.fantasy_name)) like '%' || normalized_search || '%'
       or lower(extensions.unaccent(r.city)) like '%' || normalized_search || '%'
       or lower(extensions.unaccent(r.district)) like '%' || normalized_search || '%'
       or lower(extensions.unaccent(r.activity_name)) like '%' || normalized_search || '%'
  )
  select jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'viewer_user_code', viewer_user_code,
    'last_updated_at', last_updated_at,
    'total_recovered', coalesce((select count(*) from filtered), 0),
    'customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'tax_id', f.tax_id,
          'source_customer_code', f.source_customer_code,
          'client_name', f.client_name,
          'fantasy_name', f.fantasy_name,
          'activity_code', f.activity_code,
          'activity_name', f.activity_name,
          'city', f.city,
          'uf', f.uf,
          'district', f.district,
          'full_address', f.full_address,
          'credit_limit', f.credit_limit,
          'market_potential', f.market_potential,
          'market_potential_order_count', f.market_potential_order_count,
          'recovered_at', f.recovered_at
        )
        order by f.recovered_at desc, f.client_name, f.tax_id
      )
      from filtered f
    ), '[]'::jsonb)
  )
    into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_recovered_customer_opportunities(text)
  to authenticated;

alter function public.get_recovered_customer_opportunities(text)
  set statement_timeout = '30s';
