create table if not exists public.app_customer_opportunity_supplier_map (
  henrique_supplier_code text primary key,
  omega_supplier_code text not null references public.app_suppliers (codfornec),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (btrim(henrique_supplier_code) <> ''),
  check (btrim(omega_supplier_code) <> '')
);

create index if not exists idx_customer_opportunity_supplier_map_omega
  on public.app_customer_opportunity_supplier_map (omega_supplier_code);

drop trigger if exists set_customer_opportunity_supplier_map_updated_at
  on public.app_customer_opportunity_supplier_map;
create trigger set_customer_opportunity_supplier_map_updated_at
before update on public.app_customer_opportunity_supplier_map
for each row
execute function public.set_updated_at();

alter table public.app_customer_opportunity_supplier_map enable row level security;

grant select, insert, update, delete
  on public.app_customer_opportunity_supplier_map
  to authenticated, service_role;

drop policy if exists "customer_opportunity_supplier_map_admin_manage"
  on public.app_customer_opportunity_supplier_map;
create policy "customer_opportunity_supplier_map_admin_manage"
on public.app_customer_opportunity_supplier_map
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

insert into public.app_customer_opportunity_supplier_map (
  henrique_supplier_code,
  omega_supplier_code
)
values
  ('9106', '5569'),
  ('9107', '3609'),
  ('9109', '1630'),
  ('9151', '3609'),
  ('9211', '967'),
  ('9371', '1481'),
  ('9440', '5348'),
  ('9504', '967'),
  ('9649', '5348'),
  ('10323', '117'),
  ('12449', '4701'),
  ('12486', '1481'),
  ('12496', '5687'),
  ('12668', '117'),
  ('12698', '117'),
  ('12826', '3609'),
  ('12925', '117'),
  ('13086', '3609'),
  ('13126', '117'),
  ('13153', '4698'),
  ('13236', '5348'),
  ('13828', '3609'),
  ('14080', '117')
on conflict (henrique_supplier_code)
do update
  set omega_supplier_code = excluded.omega_supplier_code;

create or replace function public.get_customer_opportunity_details(
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

  normalized_tax_id := regexp_replace(
    coalesce(target_tax_id, ''),
    '[^0-9]',
    '',
    'g'
  );

  select jsonb_build_object(
    'tax_id', opportunity.tax_id,
    'source_customer_code', opportunity.source_customer_code,
    'client_name', opportunity.client_name,
    'fantasy_name', opportunity.fantasy_name,
    'activity_code', opportunity.activity_code,
    'activity_name', opportunity.activity_name,
    'city', opportunity.city,
    'uf', opportunity.uf,
    'district', opportunity.district,
    'street', opportunity.street,
    'address_number', opportunity.address_number,
    'full_address', opportunity.full_address,
    'postal_code', opportunity.postal_code,
    'credit_limit', opportunity.credit_limit,
    'market_potential', opportunity.market_potential,
    'market_potential_order_count', opportunity.market_potential_order_count,
    'latitude', opportunity.latitude,
    'longitude', opportunity.longitude,
    'suppliers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', mapped_supplier.omega_supplier_code,
          'name', mapped_supplier.supplier_name
        )
        order by
          mapped_supplier.supplier_name,
          mapped_supplier.omega_supplier_code
      )
      from (
        select distinct
          supplier_map.omega_supplier_code,
          omega_supplier.supplier_name
        from jsonb_array_elements(opportunity.suppliers) henrique_supplier
        join public.app_customer_opportunity_supplier_map supplier_map
          on supplier_map.henrique_supplier_code =
            btrim(coalesce(henrique_supplier ->> 'code', ''))
        join public.app_suppliers omega_supplier
          on omega_supplier.codfornec = supplier_map.omega_supplier_code
      ) mapped_supplier
    ), '[]'::jsonb)
  )
    into payload
  from public.app_customer_opportunities opportunity
  where opportunity.tax_id = normalized_tax_id
    and exists (
      select 1
      from public.app_customer_seller_bases customer_base
      join public.app_customers customer
        on customer.codcli = customer_base.codcli
      where customer_base.codusur = effective_seller_code
        and public.normalize_city_key(customer.cidade) = opportunity.city_key
        and public.normalize_city_key(customer.bairro) =
          public.normalize_city_key(opportunity.district)
        and public.normalize_city_key(customer.bairro) <> ''
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
