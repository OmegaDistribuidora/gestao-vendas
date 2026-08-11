create or replace function public.can_access_customer_opportunities_v2()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users u
    left join public.app_profiles p on p.id = u.profile_id
    where u.auth_user_id = auth.uid()
      and u.is_active
      and coalesce(p.slug, 'sem_perfil') <> 'sem_perfil'
  );
$$;

grant execute on function public.can_access_customer_opportunities_v2() to authenticated;

create or replace function public.get_customer_opportunities_v2(
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
  viewer_profile text;
  viewer_code text;
  requested_supervisor text := btrim(coalesce(target_supervisor_code, ''));
  requested_seller text := btrim(coalesce(target_seller_code, ''));
  requested_neighborhood text := btrim(coalesce(target_neighborhood_key, ''));
  requested_activity text := btrim(coalesce(target_activity_key, ''));
  effective_supervisor text := '';
  effective_seller text := '';
  supervisors jsonb := '[]'::jsonb;
  sellers jsonb := '[]'::jsonb;
  selection_required text := '';
  last_updated timestamptz;
  payload jsonb;
begin
  select coalesce(p.slug, 'sem_perfil'), u.code into viewer_profile, viewer_code
  from public.app_users u left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid() and u.is_active limit 1;

  if viewer_profile = 'sem_perfil' then
    raise exception 'Usuario sem acesso ao mapa.';
  end if;

  last_updated := public.get_latest_sync_finished_at(
    array['customer_opportunities_sync', 'customer_opportunities_prune']
  );

  if viewer_profile = 'vendedor' then
    effective_seller := viewer_code;
  elsif viewer_profile = 'supervisor' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', u.code, 'name', coalesce(nullif(btrim(u.display_name), ''), u.code),
      'label', u.code || ' - ' || coalesce(nullif(btrim(u.display_name), ''), u.code)
    ) order by u.display_name, u.code), '[]'::jsonb) into sellers
    from public.app_users u join public.app_profiles p on p.id = u.profile_id
    where p.slug = 'vendedor' and u.is_active and coalesce(u.supervisor_code, '') = viewer_code;

    if exists (select 1 from public.app_users u join public.app_profiles p on p.id=u.profile_id
      where p.slug='vendedor' and u.is_active and u.code=requested_seller
        and coalesce(u.supervisor_code,'')=viewer_code) then
      effective_seller := requested_seller;
    else selection_required := 'seller'; end if;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', scope.code, 'name', scope.name,
      'label', scope.code || ' - ' || scope.name
    ) order by scope.name, scope.code), '[]'::jsonb) into supervisors
    from (
      select distinct seller.supervisor_code as code,
        coalesce(nullif(btrim(supervisor.display_name), ''), seller.supervisor_code) as name
      from public.app_users seller
      join public.app_profiles sp on sp.id=seller.profile_id
      left join public.app_users supervisor on supervisor.code=seller.supervisor_code
      where sp.slug='vendedor' and seller.is_active
        and coalesce(seller.supervisor_code,'') <> ''
        and (viewer_profile <> 'coordenador' or coalesce(seller.coordinator_code,'')=viewer_code)
    ) scope;

    if exists (
      select 1 from public.app_users seller join public.app_profiles p on p.id=seller.profile_id
      where p.slug='vendedor' and seller.is_active
        and seller.supervisor_code=requested_supervisor
        and (viewer_profile <> 'coordenador' or coalesce(seller.coordinator_code,'')=viewer_code)
    ) then effective_supervisor := requested_supervisor;
    else selection_required := 'supervisor'; end if;

    if effective_supervisor <> '' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'code', u.code, 'name', coalesce(nullif(btrim(u.display_name), ''), u.code),
        'label', u.code || ' - ' || coalesce(nullif(btrim(u.display_name), ''), u.code)
      ) order by u.display_name, u.code), '[]'::jsonb) into sellers
      from public.app_users u join public.app_profiles p on p.id=u.profile_id
      where p.slug='vendedor' and u.is_active and u.supervisor_code=effective_supervisor
        and (viewer_profile <> 'coordenador' or coalesce(u.coordinator_code,'')=viewer_code);

      if exists (select 1 from public.app_users u join public.app_profiles p on p.id=u.profile_id
        where p.slug='vendedor' and u.is_active and u.code=requested_seller
          and u.supervisor_code=effective_supervisor
          and (viewer_profile <> 'coordenador' or coalesce(u.coordinator_code,'')=viewer_code)) then
        effective_seller := requested_seller; selection_required := '';
      else selection_required := 'seller'; end if;
    end if;
  end if;

  if effective_seller = '' then
    return jsonb_build_object(
      'viewer_profile_slug', viewer_profile, 'viewer_user_code', viewer_code,
      'selected_supervisor_code', nullif(effective_supervisor,''),
      'selected_seller_code', null, 'selection_required', selection_required,
      'access_denied_reason', '', 'last_updated_at', last_updated,
      'available_supervisors', supervisors, 'available_sellers', sellers,
      'served_neighborhoods', '[]'::jsonb, 'available_activities', '[]'::jsonb,
      'opportunities', '[]'::jsonb, 'total_opportunities', 0
    );
  end if;

  with seller_neighborhood_rows as (
    select public.normalize_city_key(c.cidade) city_key,
      public.normalize_city_key(c.bairro) district_key,
      max(c.cidade) city, max(c.bairro) district
    from public.app_customer_seller_bases b join public.app_customers c on c.codcli=b.codcli
    where b.codusur=effective_seller and public.normalize_city_key(c.cidade)<>''
      and public.normalize_city_key(c.bairro)<>''
    group by public.normalize_city_key(c.cidade), public.normalize_city_key(c.bairro)
  ), selectable as (
    select sn.city_key||'|'||sn.district_key neighborhood_key, sn.city, sn.district,
      count(o.tax_id)::integer opportunity_count, avg(o.latitude) center_latitude,
      avg(o.longitude) center_longitude
    from seller_neighborhood_rows sn join public.app_customer_opportunities o
      on o.city_key=sn.city_key and public.normalize_city_key(o.district)=sn.district_key
    group by sn.city_key,sn.district_key,sn.city,sn.district
  ), selected as (
    select x.* from (
      select s.*,0 priority from selectable s where requested_neighborhood<>'' and s.neighborhood_key=requested_neighborhood
      union all select s.*,1 priority from selectable s
    ) x order by priority,city,district limit 1
  ), neighborhood_opportunities as (
    select o.* from public.app_customer_opportunities o join selected s
      on o.city_key=split_part(s.neighborhood_key,'|',1)
      and public.normalize_city_key(o.district)=split_part(s.neighborhood_key,'|',2)
    where o.latitude between -90 and 90 and o.longitude between -180 and 180
  ), activities as (
    select public.customer_opportunity_activity_key(o.activity_code,o.activity_name) activity_key,
      max(o.activity_code) activity_code, max(o.activity_name) activity_name,
      count(*)::integer opportunity_count
    from neighborhood_opportunities o
    group by public.customer_opportunity_activity_key(o.activity_code,o.activity_name)
  ), effective_activity as (
    select activity_key from activities where requested_activity<>'' and activity_key=requested_activity limit 1
  ), visible as (
    select o.* from neighborhood_opportunities o where not exists(select 1 from effective_activity)
      or public.customer_opportunity_activity_key(o.activity_code,o.activity_name)=(select activity_key from effective_activity)
  )
  select jsonb_build_object(
    'viewer_profile_slug',viewer_profile,'viewer_user_code',viewer_code,
    'selected_supervisor_code',nullif(effective_supervisor,''),'selected_seller_code',effective_seller,
    'selection_required','','access_denied_reason','','last_updated_at',last_updated,
    'available_supervisors',supervisors,'available_sellers',sellers,
    'selected_neighborhood_key',coalesce((select neighborhood_key from selected limit 1),''),
    'served_neighborhoods',coalesce((select jsonb_agg(jsonb_build_object(
      'neighborhood_key',neighborhood_key,'city',city,'district',district,
      'opportunity_count',opportunity_count,'center_latitude',round(center_latitude::numeric,6),
      'center_longitude',round(center_longitude::numeric,6)) order by city,district) from selectable),'[]'::jsonb),
    'selected_activity_key',coalesce((select activity_key from effective_activity limit 1),''),
    'available_activities',coalesce((select jsonb_agg(jsonb_build_object(
      'activity_key',activity_key,'activity_code',activity_code,'activity_name',activity_name,
      'opportunity_count',opportunity_count) order by activity_name,activity_code) from activities),'[]'::jsonb),
    'total_opportunities',(select count(*) from visible),
    'opportunities',coalesce((select jsonb_agg(jsonb_build_array(
      tax_id,round(latitude::numeric,6),round(longitude::numeric,6)) order by tax_id) from visible),'[]'::jsonb)
  ) into payload;
  return coalesce(payload,'{}'::jsonb);
end;
$$;

grant execute on function public.get_customer_opportunities_v2(text,text,text,text) to authenticated;
alter function public.get_customer_opportunities_v2(text,text,text,text) set statement_timeout='65s';

create or replace function public.get_customer_opportunity_details_v2(
  target_tax_id text,
  target_seller_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  viewer_profile text; viewer_code text; seller_code text := btrim(coalesce(target_seller_code,''));
  normalized_tax_id text; payload jsonb;
begin
  select coalesce(p.slug,'sem_perfil'),u.code into viewer_profile,viewer_code
  from public.app_users u left join public.app_profiles p on p.id=u.profile_id
  where u.auth_user_id=auth.uid() and u.is_active limit 1;
  if viewer_profile='vendedor' then seller_code:=viewer_code; end if;
  if not exists(select 1 from public.app_users u join public.app_profiles p on p.id=u.profile_id
    where viewer_profile <> 'sem_perfil' and p.slug='vendedor' and u.is_active and u.code=seller_code
      and (viewer_profile not in ('supervisor','coordenador')
        or (viewer_profile='supervisor' and u.supervisor_code=viewer_code)
        or (viewer_profile='coordenador' and u.coordinator_code=viewer_code))) then
    raise exception 'Vendedor invalido para o mapa de oportunidades.';
  end if;
  normalized_tax_id:=regexp_replace(coalesce(target_tax_id,''),'[^0-9]','','g');
  select jsonb_build_object(
    'tax_id',o.tax_id,'source_customer_code',o.source_customer_code,'client_name',o.client_name,
    'fantasy_name',o.fantasy_name,'activity_code',o.activity_code,'activity_name',o.activity_name,
    'city',o.city,'uf',o.uf,'district',o.district,'street',o.street,
    'address_number',o.address_number,'full_address',o.full_address,'postal_code',o.postal_code,
    'credit_limit',o.credit_limit,'market_potential',o.market_potential,
    'market_potential_order_count',o.market_potential_order_count,'latitude',o.latitude,
    'longitude',o.longitude,'suppliers',coalesce((select jsonb_agg(jsonb_build_object(
      'code',m.omega_supplier_code,'name',s.supplier_name) order by s.supplier_name,m.omega_supplier_code)
      from jsonb_array_elements(o.suppliers) h
      join public.app_customer_opportunity_supplier_map m on m.henrique_supplier_code=btrim(coalesce(h->>'code',''))
      join public.app_suppliers s on s.codfornec=m.omega_supplier_code),'[]'::jsonb)
  ) into payload
  from public.app_customer_opportunities o where o.tax_id=normalized_tax_id and exists(
    select 1 from public.app_customer_seller_bases b join public.app_customers c on c.codcli=b.codcli
    where b.codusur=seller_code and public.normalize_city_key(c.cidade)=o.city_key
      and public.normalize_city_key(c.bairro)=public.normalize_city_key(o.district)
      and public.normalize_city_key(c.bairro)<>''
  );
  if payload is null then raise exception 'Oportunidade nao encontrada no escopo do vendedor.'; end if;
  return payload;
end;
$$;

grant execute on function public.get_customer_opportunity_details_v2(text,text) to authenticated;
