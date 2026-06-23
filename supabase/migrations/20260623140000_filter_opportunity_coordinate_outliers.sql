create or replace function public.coordinate_distance_km(
  latitude_a double precision,
  longitude_a double precision,
  latitude_b double precision,
  longitude_b double precision
)
returns double precision
language sql
immutable
parallel safe
as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(latitude_b - latitude_a) / 2), 2)
    + cos(radians(latitude_a))
      * cos(radians(latitude_b))
      * power(sin(radians(longitude_b - longitude_a) / 2), 2)
  ));
$$;

revoke all on function public.coordinate_distance_km(
  double precision,
  double precision,
  double precision,
  double precision
) from public;

alter function public.get_customer_opportunities(text, text, text, text)
  rename to get_customer_opportunities_unfiltered;

revoke all on function public.get_customer_opportunities_unfiltered(
  text,
  text,
  text,
  text
) from public, authenticated;

create function public.get_customer_opportunities(
  target_neighborhood_key text default null,
  target_activity_key text default null,
  target_supervisor_code text default null,
  target_seller_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  marker_count integer := 0;
  median_latitude double precision;
  median_longitude double precision;
  filtered_markers jsonb := '[]'::jsonb;
  filtered_count integer := 0;
begin
  payload := public.get_customer_opportunities_unfiltered(
    target_neighborhood_key,
    target_activity_key,
    target_supervisor_code,
    target_seller_code
  );

  marker_count := jsonb_array_length(
    coalesce(payload -> 'opportunities', '[]'::jsonb)
  );
  if marker_count = 0 then
    return payload;
  end if;

  with points as (
    select
      marker,
      (marker ->> 1)::double precision as latitude,
      (marker ->> 2)::double precision as longitude
    from jsonb_array_elements(payload -> 'opportunities') as source(marker)
  )
  select
    percentile_cont(0.5) within group (order by latitude),
    percentile_cont(0.5) within group (order by longitude)
    into median_latitude, median_longitude
  from points
  where latitude between -34 and 6
    and longitude between -74 and -34;

  with points as (
    select
      marker,
      (marker ->> 0) as tax_id,
      (marker ->> 1)::double precision as latitude,
      (marker ->> 2)::double precision as longitude
    from jsonb_array_elements(payload -> 'opportunities') as source(marker)
  ),
  plausible_points as (
    select p.*
    from points p
    where p.latitude between -34 and 6
      and p.longitude between -74 and -34
      and (
        marker_count < 5
        or public.coordinate_distance_km(
          median_latitude,
          median_longitude,
          p.latitude,
          p.longitude
        ) <= 25
      )
  )
  select
    coalesce(jsonb_agg(marker order by tax_id), '[]'::jsonb),
    count(*)::integer
    into filtered_markers, filtered_count
  from plausible_points;

  payload := jsonb_set(
    payload,
    '{opportunities}',
    filtered_markers,
    true
  );
  payload := jsonb_set(
    payload,
    '{total_opportunities}',
    to_jsonb(filtered_count),
    true
  );

  return payload;
end;
$$;

grant execute on function public.get_customer_opportunities(
  text,
  text,
  text,
  text
) to authenticated;

alter function public.get_customer_opportunities(text, text, text, text)
  set statement_timeout = '65s';
