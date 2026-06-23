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
    select
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
    where requested_city_key <> ''
      and scr.city_key = requested_city_key
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
        jsonb_build_array(
          o.tax_id,
          round(o.latitude::numeric, 6),
          round(o.longitude::numeric, 6)
        )
        order by o.tax_id
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
