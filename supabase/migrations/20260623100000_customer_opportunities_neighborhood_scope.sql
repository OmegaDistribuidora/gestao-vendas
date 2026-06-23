alter table public.app_customer_opportunities
  add column if not exists market_potential numeric(18, 2),
  add column if not exists market_potential_order_count integer not null default 0;

alter table public.etl_stg_customer_opportunities
  add column if not exists market_potential numeric(18, 2),
  add column if not exists market_potential_order_count integer not null default 0;

create index if not exists idx_app_customer_opportunities_neighborhood
  on public.app_customer_opportunities (
    city_key,
    public.normalize_city_key(district),
    activity_code
  );

create or replace function public.seller_has_current_sku_target(
  target_seller_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_performance_targets t
    where t.profile_slug = 'vendedor'
      and t.owner_code = btrim(coalesce(target_seller_code, ''))
      and t.month_start = date_trunc('month', current_date)::date
      and coalesce(t.meta_sku, 0) > 0
  );
$$;

revoke all on function public.seller_has_current_sku_target(text) from public;

create or replace function public.can_access_customer_opportunities()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if viewer_profile_slug in ('supervisor', 'coordenador') then
    return true;
  end if;

  return viewer_profile_slug = 'vendedor'
    and not public.seller_has_current_sku_target(viewer_user_code);
end;
$$;

grant execute on function public.can_access_customer_opportunities()
  to authenticated;

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

alter function public.apply_customer_opportunities_sync(uuid)
  set statement_timeout = '300s';

drop function if exists public.get_customer_opportunities(text);

create function public.get_customer_opportunities(
  target_neighborhood_key text default null,
  target_activity_key text default null,
  target_supervisor_code text default null,
  target_seller_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_supervisor_code text := btrim(coalesce(target_supervisor_code, ''));
  requested_seller_code text := btrim(coalesce(target_seller_code, ''));
  requested_neighborhood_key text := btrim(coalesce(target_neighborhood_key, ''));
  requested_activity_key text := btrim(coalesce(target_activity_key, ''));
  effective_supervisor_code text := '';
  effective_seller_code text := '';
  available_supervisors jsonb := '[]'::jsonb;
  available_sellers jsonb := '[]'::jsonb;
  selection_required text := '';
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

  if viewer_profile_slug not in ('vendedor', 'supervisor', 'coordenador') then
    raise exception 'Modulo disponivel apenas para vendedor, supervisor e coordenador.';
  end if;

  last_updated_at := public.get_latest_sync_finished_at(
    array['customer_opportunities_sync', 'customer_opportunities_prune']
  );

  if viewer_profile_slug = 'vendedor' then
    if public.seller_has_current_sku_target(viewer_user_code) then
      return jsonb_build_object(
        'viewer_profile_slug', viewer_profile_slug,
        'viewer_user_code', viewer_user_code,
        'access_denied_reason', 'O mapa nao se aplica a vendedores com meta de SKU.',
        'last_updated_at', last_updated_at,
        'available_supervisors', '[]'::jsonb,
        'available_sellers', '[]'::jsonb,
        'served_neighborhoods', '[]'::jsonb,
        'available_activities', '[]'::jsonb,
        'opportunities', '[]'::jsonb,
        'total_opportunities', 0
      );
    end if;
    effective_seller_code := viewer_user_code;
  elsif viewer_profile_slug = 'supervisor' then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'code', seller.code,
        'name', coalesce(nullif(btrim(seller.display_name), ''), seller.code),
        'label', case
          when nullif(btrim(seller.display_name), '') is null then seller.code
          else seller.code || ' - ' || seller.display_name
        end
      ) order by seller.display_name, seller.code
    ), '[]'::jsonb)
      into available_sellers
    from public.app_users seller
    join public.app_profiles profile on profile.id = seller.profile_id
    where profile.slug = 'vendedor'
      and seller.is_active
      and coalesce(seller.supervisor_code, '') = viewer_user_code
      and not public.seller_has_current_sku_target(seller.code);

    if exists (
      select 1
      from public.app_users seller
      join public.app_profiles profile on profile.id = seller.profile_id
      where profile.slug = 'vendedor'
        and seller.is_active
        and seller.code = requested_seller_code
        and coalesce(seller.supervisor_code, '') = viewer_user_code
        and not public.seller_has_current_sku_target(seller.code)
    ) then
      effective_seller_code := requested_seller_code;
    else
      selection_required := 'seller';
    end if;
  else
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'code', scope.code,
        'name', scope.name,
        'label', case
          when scope.name = scope.code then scope.code
          else scope.code || ' - ' || scope.name
        end
      ) order by scope.name, scope.code
    ), '[]'::jsonb)
      into available_supervisors
    from (
      select distinct
        seller.supervisor_code as code,
        coalesce(nullif(btrim(supervisor.display_name), ''), seller.supervisor_code) as name
      from public.app_users seller
      join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
      left join public.app_users supervisor on supervisor.code = seller.supervisor_code
      where seller_profile.slug = 'vendedor'
        and seller.is_active
        and coalesce(seller.coordinator_code, '') = viewer_user_code
        and coalesce(seller.supervisor_code, '') <> ''
        and not public.seller_has_current_sku_target(seller.code)
    ) scope;

    if exists (
      select 1
      from public.app_users supervisor
      join public.app_profiles profile on profile.id = supervisor.profile_id
      where profile.slug = 'supervisor'
        and supervisor.is_active
        and supervisor.code = requested_supervisor_code
        and coalesce(supervisor.coordinator_code, '') = viewer_user_code
    ) then
      effective_supervisor_code := requested_supervisor_code;
    else
      selection_required := 'supervisor';
    end if;

    if effective_supervisor_code <> '' then
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'code', seller.code,
          'name', coalesce(nullif(btrim(seller.display_name), ''), seller.code),
          'label', case
            when nullif(btrim(seller.display_name), '') is null then seller.code
            else seller.code || ' - ' || seller.display_name
          end
        ) order by seller.display_name, seller.code
      ), '[]'::jsonb)
        into available_sellers
      from public.app_users seller
      join public.app_profiles profile on profile.id = seller.profile_id
      where profile.slug = 'vendedor'
        and seller.is_active
        and coalesce(seller.supervisor_code, '') = effective_supervisor_code
        and coalesce(seller.coordinator_code, '') = viewer_user_code
        and not public.seller_has_current_sku_target(seller.code);

      if exists (
        select 1
        from public.app_users seller
        join public.app_profiles profile on profile.id = seller.profile_id
        where profile.slug = 'vendedor'
          and seller.is_active
          and seller.code = requested_seller_code
          and coalesce(seller.supervisor_code, '') = effective_supervisor_code
          and coalesce(seller.coordinator_code, '') = viewer_user_code
          and not public.seller_has_current_sku_target(seller.code)
      ) then
        effective_seller_code := requested_seller_code;
        selection_required := '';
      else
        selection_required := 'seller';
      end if;
    end if;
  end if;

  if effective_seller_code = '' then
    return jsonb_build_object(
      'viewer_profile_slug', viewer_profile_slug,
      'viewer_user_code', viewer_user_code,
      'selected_supervisor_code', nullif(effective_supervisor_code, ''),
      'selected_seller_code', null,
      'selection_required', selection_required,
      'access_denied_reason', '',
      'last_updated_at', last_updated_at,
      'available_supervisors', available_supervisors,
      'available_sellers', available_sellers,
      'served_neighborhoods', '[]'::jsonb,
      'available_activities', '[]'::jsonb,
      'opportunities', '[]'::jsonb,
      'total_opportunities', 0
    );
  end if;

  with seller_neighborhood_rows as (
    select
      public.normalize_city_key(c.cidade) as city_key,
      public.normalize_city_key(c.bairro) as district_key,
      max(c.cidade) as city,
      max(c.bairro) as district
    from public.app_customer_seller_bases b
    join public.app_customers c on c.codcli = b.codcli
    where b.codusur = effective_seller_code
      and public.normalize_city_key(c.cidade) <> ''
      and public.normalize_city_key(c.bairro) <> ''
    group by
      public.normalize_city_key(c.cidade),
      public.normalize_city_key(c.bairro)
  ),
  selectable_neighborhood_rows as (
    select
      sn.city_key || '|' || sn.district_key as neighborhood_key,
      sn.city,
      sn.district,
      count(o.tax_id)::integer as opportunity_count,
      avg(o.latitude) as center_latitude,
      avg(o.longitude) as center_longitude
    from seller_neighborhood_rows sn
    join public.app_customer_opportunities o
      on o.city_key = sn.city_key
     and public.normalize_city_key(o.district) = sn.district_key
    group by sn.city_key, sn.district_key, sn.city, sn.district
  ),
  selected_neighborhood as (
    select row_data.*
    from (
      select sr.*, 0 as priority
      from selectable_neighborhood_rows sr
      where requested_neighborhood_key <> ''
        and sr.neighborhood_key = requested_neighborhood_key
      union all
      select sr.*, 1 as priority
      from selectable_neighborhood_rows sr
    ) row_data
    order by row_data.priority, row_data.city, row_data.district
    limit 1
  ),
  neighborhood_opportunities as (
    select o.*
    from public.app_customer_opportunities o
    join selected_neighborhood sn
      on o.city_key = split_part(sn.neighborhood_key, '|', 1)
     and public.normalize_city_key(o.district) = split_part(sn.neighborhood_key, '|', 2)
    where o.latitude between -90 and 90
      and o.longitude between -180 and 180
  ),
  activity_rows as (
    select
      coalesce(
        nullif(btrim(o.activity_code), ''),
        public.normalize_city_key(o.activity_name)
      ) as activity_key,
      max(o.activity_code) as activity_code,
      max(o.activity_name) as activity_name,
      count(*)::integer as opportunity_count
    from neighborhood_opportunities o
    where coalesce(
      nullif(btrim(o.activity_code), ''),
      public.normalize_city_key(o.activity_name)
    ) <> ''
    group by coalesce(
      nullif(btrim(o.activity_code), ''),
      public.normalize_city_key(o.activity_name)
    )
  ),
  effective_activity as (
    select ar.activity_key
    from activity_rows ar
    where requested_activity_key <> ''
      and ar.activity_key = requested_activity_key
    limit 1
  ),
  visible_opportunities as (
    select o.*
    from neighborhood_opportunities o
    where not exists (select 1 from effective_activity)
       or coalesce(
         nullif(btrim(o.activity_code), ''),
         public.normalize_city_key(o.activity_name)
       ) = (select ea.activity_key from effective_activity ea limit 1)
  )
  select jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'viewer_user_code', viewer_user_code,
    'selected_supervisor_code', nullif(effective_supervisor_code, ''),
    'selected_seller_code', effective_seller_code,
    'selection_required', '',
    'access_denied_reason', '',
    'last_updated_at', last_updated_at,
    'available_supervisors', available_supervisors,
    'available_sellers', available_sellers,
    'selected_neighborhood_key', coalesce((
      select sn.neighborhood_key from selected_neighborhood sn limit 1
    ), ''),
    'served_neighborhoods', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'neighborhood_key', sr.neighborhood_key,
          'city', sr.city,
          'district', sr.district,
          'opportunity_count', sr.opportunity_count,
          'center_latitude', round(sr.center_latitude::numeric, 6),
          'center_longitude', round(sr.center_longitude::numeric, 6)
        ) order by sr.city, sr.district
      )
      from selectable_neighborhood_rows sr
    ), '[]'::jsonb),
    'selected_activity_key', coalesce((
      select ea.activity_key from effective_activity ea limit 1
    ), ''),
    'available_activities', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'activity_key', ar.activity_key,
          'activity_code', ar.activity_code,
          'activity_name', ar.activity_name,
          'opportunity_count', ar.opportunity_count
        ) order by ar.activity_name, ar.activity_code
      )
      from activity_rows ar
    ), '[]'::jsonb),
    'total_opportunities', coalesce((
      select count(*) from visible_opportunities
    ), 0),
    'opportunities', coalesce((
      select jsonb_agg(
        jsonb_build_array(
          o.tax_id,
          round(o.latitude::numeric, 6),
          round(o.longitude::numeric, 6)
        ) order by o.tax_id
      )
      from visible_opportunities o
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_customer_opportunities(text, text, text, text)
  to authenticated;

alter function public.get_customer_opportunities(text, text, text, text)
  set statement_timeout = '60s';

drop function if exists public.get_customer_opportunity_details(text);

create function public.get_customer_opportunity_details(
  target_tax_id text,
  target_seller_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  effective_seller_code text := '';
  normalized_tax_id text;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if viewer_profile_slug = 'vendedor' then
    effective_seller_code := viewer_user_code;
  elsif viewer_profile_slug = 'supervisor' then
    select seller.code
      into effective_seller_code
    from public.app_users seller
    join public.app_profiles profile on profile.id = seller.profile_id
    where profile.slug = 'vendedor'
      and seller.is_active
      and seller.code = btrim(coalesce(target_seller_code, ''))
      and coalesce(seller.supervisor_code, '') = viewer_user_code
      and not public.seller_has_current_sku_target(seller.code)
    limit 1;
  elsif viewer_profile_slug = 'coordenador' then
    select seller.code
      into effective_seller_code
    from public.app_users seller
    join public.app_profiles profile on profile.id = seller.profile_id
    where profile.slug = 'vendedor'
      and seller.is_active
      and seller.code = btrim(coalesce(target_seller_code, ''))
      and coalesce(seller.coordinator_code, '') = viewer_user_code
      and not public.seller_has_current_sku_target(seller.code)
    limit 1;
  end if;

  if coalesce(effective_seller_code, '') = ''
     or public.seller_has_current_sku_target(effective_seller_code) then
    raise exception 'Vendedor invalido para o mapa de oportunidades.';
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
    'market_potential', o.market_potential,
    'market_potential_order_count', o.market_potential_order_count,
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
      where b.codusur = effective_seller_code
        and public.normalize_city_key(c.cidade) = o.city_key
        and public.normalize_city_key(c.bairro) = public.normalize_city_key(o.district)
        and public.normalize_city_key(c.bairro) <> ''
    );

  if payload is null then
    raise exception 'Oportunidade nao encontrada no escopo do vendedor.';
  end if;

  return payload;
end;
$$;

grant execute on function public.get_customer_opportunity_details(text, text)
  to authenticated;

alter function public.get_customer_opportunity_details(text, text)
  set statement_timeout = '15s';
