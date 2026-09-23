-- Keeps the optimized Commitment contract and enriches only items that have
-- at least one planned route occurrence in the selected commitment period.

alter function public.get_commitment_overview_optimized(
  date, date, text, text
) rename to get_commitment_overview_without_routing;

create or replace function public.get_commitment_overview_optimized(
  target_start_date date default null,
  target_end_date date default null,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  routing_by_scope jsonb := '{}'::jsonb;
  enriched_items jsonb := '[]'::jsonb;
  item_record record;
  selected_start_date date;
  selected_end_date date;
  routing_metric jsonb;
begin
  payload := public.get_commitment_overview_without_routing(
    target_start_date,
    target_end_date,
    target_scope_profile_slug,
    target_scope_owner_code
  );

  selected_start_date := nullif(payload ->> 'selected_start_date', '')::date;
  selected_end_date := nullif(payload ->> 'selected_end_date', '')::date;
  if selected_start_date is null or selected_end_date is null then
    return payload;
  end if;

  routing_by_scope := public.get_routing_performance_by_scope(
    selected_start_date,
    selected_end_date
  );

  for item_record in
    select item.value
    from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) item
  loop
    routing_metric := routing_by_scope -> (
      (item_record.value ->> 'profile_slug')
      || '|'
      || (item_record.value ->> 'owner_code')
    );

    if routing_metric is not null
       and coalesce((routing_metric ->> 'routing_planned')::integer, 0) > 0 then
      item_record.value := item_record.value || routing_metric;
    end if;

    enriched_items := enriched_items || jsonb_build_array(item_record.value);
  end loop;

  return payload || jsonb_build_object('items', enriched_items);
end;
$$;

revoke all on function public.get_commitment_overview_optimized(
  date, date, text, text
) from public, anon, authenticated;

comment on function public.get_commitment_overview_optimized(
  date, date, text, text
) is 'Compromisso otimizado com desempenho de roteirizacao no periodo.';
