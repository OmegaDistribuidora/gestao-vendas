create or replace function public.customer_opportunity_activity_key(
  activity_code text,
  activity_name text
)
returns text
language sql
immutable
set search_path = public
as $$
  with normalized as (
    select
      btrim(coalesce(activity_code, '')) as code,
      btrim(coalesce(activity_name, '')) as name
  ),
  labeled as (
    select
      code,
      name,
      case
        when code = '' then name
        when name = '' or name = code then code
        else code || ' - ' || name
      end as label
    from normalized
  )
  select case
    when label ~ '^[0-9]+$' then '__no_activity__'
    else coalesce(nullif(code, ''), public.normalize_city_key(name))
  end
  from labeled;
$$;

revoke all on function public.customer_opportunity_activity_key(text, text)
  from public;

create or replace function public.get_customer_opportunities(
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
  no_activity_key constant text := '__no_activity__';
  requested_activity_key text := btrim(coalesce(target_activity_key, ''));
  effective_activity_key text := '';
  payload jsonb;
  aggregated_activities jsonb := '[]'::jsonb;
  marker_count integer := 0;
  median_latitude double precision;
  median_longitude double precision;
  filtered_markers jsonb := '[]'::jsonb;
  filtered_count integer := 0;
begin
  payload := public.get_customer_opportunities_unfiltered(
    target_neighborhood_key,
    null,
    target_supervisor_code,
    target_seller_code
  );

  with scoped_opportunities as (
    select opportunity.*
    from jsonb_array_elements(
      coalesce(payload -> 'opportunities', '[]'::jsonb)
    ) as source(marker)
    join public.app_customer_opportunities opportunity
      on opportunity.tax_id = marker ->> 0
  ),
  normalized_activities as (
    select
      public.customer_opportunity_activity_key(
        opportunity.activity_code,
        opportunity.activity_name
      ) as activity_key,
      case
        when public.customer_opportunity_activity_key(
          opportunity.activity_code,
          opportunity.activity_name
        ) = no_activity_key then ''
        else btrim(coalesce(opportunity.activity_code, ''))
      end as activity_code,
      case
        when public.customer_opportunity_activity_key(
          opportunity.activity_code,
          opportunity.activity_name
        ) = no_activity_key then 'Sem ramo de atividade'
        else btrim(coalesce(opportunity.activity_name, ''))
      end as activity_name
    from scoped_opportunities opportunity
  ),
  grouped_activities as (
    select
      activity_key,
      max(activity_code) as activity_code,
      max(activity_name) as activity_name,
      count(*)::integer as opportunity_count
    from normalized_activities
    where activity_key <> ''
    group by activity_key
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'activity_key', activity_key,
        'activity_code', activity_code,
        'activity_name', activity_name,
        'opportunity_count', opportunity_count
      )
      order by
        case when activity_key = no_activity_key then 0 else 1 end,
        activity_name,
        activity_code
    ),
    '[]'::jsonb
  )
    into aggregated_activities
  from grouped_activities;

  payload := jsonb_set(
    payload,
    '{available_activities}',
    aggregated_activities,
    true
  );

  if requested_activity_key <> '' and exists (
    select 1
    from jsonb_array_elements(aggregated_activities) as source(activity)
    where activity ->> 'activity_key' = requested_activity_key
  ) then
    effective_activity_key := requested_activity_key;
  end if;

  if effective_activity_key <> '' then
    with matching_markers as (
      select marker
      from jsonb_array_elements(
        coalesce(payload -> 'opportunities', '[]'::jsonb)
      ) as source(marker)
      join public.app_customer_opportunities opportunity
        on opportunity.tax_id = marker ->> 0
      where public.customer_opportunity_activity_key(
        opportunity.activity_code,
        opportunity.activity_name
      ) = effective_activity_key
    )
    select
      coalesce(jsonb_agg(marker order by marker ->> 0), '[]'::jsonb),
      count(*)::integer
      into filtered_markers, filtered_count
    from matching_markers;

    payload := jsonb_set(payload, '{opportunities}', filtered_markers, true);
    payload := jsonb_set(
      payload,
      '{total_opportunities}',
      to_jsonb(filtered_count),
      true
    );
  end if;

  payload := jsonb_set(
    payload,
    '{selected_activity_key}',
    to_jsonb(effective_activity_key),
    true
  );

  marker_count := jsonb_array_length(
    coalesce(payload -> 'opportunities', '[]'::jsonb)
  );
  if marker_count = 0 then
    return payload;
  end if;

  with points as (
    select
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
      marker ->> 0 as tax_id,
      (marker ->> 1)::double precision as latitude,
      (marker ->> 2)::double precision as longitude
    from jsonb_array_elements(payload -> 'opportunities') as source(marker)
  ),
  plausible_points as (
    select point.*
    from points point
    where point.latitude between -34 and 6
      and point.longitude between -74 and -34
      and (
        marker_count < 5
        or public.coordinate_distance_km(
          median_latitude,
          median_longitude,
          point.latitude,
          point.longitude
        ) <= 25
      )
  )
  select
    coalesce(jsonb_agg(marker order by tax_id), '[]'::jsonb),
    count(*)::integer
    into filtered_markers, filtered_count
  from plausible_points;

  payload := jsonb_set(payload, '{opportunities}', filtered_markers, true);
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
