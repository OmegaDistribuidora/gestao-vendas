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
    case
      when requested_activity_key = no_activity_key then null
      else target_activity_key
    end,
    target_supervisor_code,
    target_seller_code
  );

  with raw_activities as (
    select
      activity ->> 'activity_key' as activity_key,
      btrim(coalesce(activity ->> 'activity_code', '')) as activity_code,
      btrim(coalesce(activity ->> 'activity_name', '')) as activity_name,
      coalesce((activity ->> 'opportunity_count')::integer, 0) as opportunity_count,
      case
        when btrim(coalesce(activity ->> 'activity_code', '')) = ''
          then btrim(coalesce(activity ->> 'activity_name', ''))
        when btrim(coalesce(activity ->> 'activity_name', '')) = ''
          or btrim(coalesce(activity ->> 'activity_name', '')) =
            btrim(coalesce(activity ->> 'activity_code', ''))
          then btrim(coalesce(activity ->> 'activity_code', ''))
        else btrim(coalesce(activity ->> 'activity_code', '')) || ' - ' ||
          btrim(coalesce(activity ->> 'activity_name', ''))
      end as activity_label
    from jsonb_array_elements(
      coalesce(payload -> 'available_activities', '[]'::jsonb)
    ) as source(activity)
  ),
  normalized_activities as (
    select
      case
        when activity_label ~ '^[0-9]+$' then no_activity_key
        else activity_key
      end as activity_key,
      case when activity_label ~ '^[0-9]+$' then '' else activity_code end
        as activity_code,
      case
        when activity_label ~ '^[0-9]+$' then 'Sem ramo de atividade'
        else activity_name
      end as activity_name,
      opportunity_count
    from raw_activities
  ),
  grouped_activities as (
    select
      activity_key,
      max(activity_code) as activity_code,
      max(activity_name) as activity_name,
      sum(opportunity_count)::integer as opportunity_count
    from normalized_activities
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

  if requested_activity_key = no_activity_key then
    with markers as (
      select marker
      from jsonb_array_elements(
        coalesce(payload -> 'opportunities', '[]'::jsonb)
      ) as source(marker)
      join public.app_customer_opportunities opportunity
        on opportunity.tax_id = (marker ->> 0)
      where (
        case
          when btrim(coalesce(opportunity.activity_code, '')) = ''
            then btrim(coalesce(opportunity.activity_name, ''))
          when btrim(coalesce(opportunity.activity_name, '')) = ''
            or btrim(coalesce(opportunity.activity_name, '')) =
              btrim(coalesce(opportunity.activity_code, ''))
            then btrim(coalesce(opportunity.activity_code, ''))
          else btrim(coalesce(opportunity.activity_code, '')) || ' - ' ||
            btrim(coalesce(opportunity.activity_name, ''))
        end
      ) ~ '^[0-9]+$'
    )
    select
      coalesce(jsonb_agg(marker order by marker ->> 0), '[]'::jsonb),
      count(*)::integer
      into filtered_markers, filtered_count
    from markers;

    payload := jsonb_set(payload, '{opportunities}', filtered_markers, true);
    payload := jsonb_set(
      payload,
      '{total_opportunities}',
      to_jsonb(filtered_count),
      true
    );
    payload := jsonb_set(
      payload,
      '{selected_activity_key}',
      to_jsonb(no_activity_key),
      true
    );
  end if;

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
