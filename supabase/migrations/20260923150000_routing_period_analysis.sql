-- Adds period analysis without changing the existing daily RPC used by
-- released versions of the app. A route occurrence is counted once per day,
-- so repeated visits to the same customer remain distinct planned visits.

create or replace function public.get_routing_analysis_period(
  target_start_date date,
  target_end_date date,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  effective_id uuid := auth.uid();
  effective_profile_slug text;
  effective_owner_code text;
  effective_display_name text;
  available_scopes jsonb;
  requested_days integer;
  available_days integer;
  applicable boolean := true;
  result jsonb;
begin
  if target_start_date is null or target_end_date is null then
    raise exception 'Periodo obrigatorio.';
  end if;
  if target_end_date < target_start_date then
    raise exception 'Periodo invalido.';
  end if;

  requested_days := target_end_date - target_start_date + 1;
  if requested_days > 31 then
    raise exception 'O periodo da roteirizacao deve ter no maximo 31 dias.';
  end if;

  if not exists (
    select 1
    from public.app_users
    where auth_user_id = auth.uid() and is_active
  ) then
    raise exception 'Usuario nao encontrado.';
  end if;

  if (nullif(btrim(target_scope_profile_slug), '') is null) <>
     (nullif(btrim(target_scope_owner_code), '') is null) then
    raise exception 'Filtro incompleto.';
  end if;

  available_scopes := public.app_view_scope_options(
    array['gerencia', 'coordenador', 'supervisor', 'vendedor']::text[]
  );

  if nullif(btrim(target_scope_profile_slug), '') is not null then
    effective_id := public.app_resolve_view_scope_auth_user(
      target_scope_profile_slug,
      target_scope_owner_code,
      array['gerencia', 'coordenador', 'supervisor', 'vendedor']::text[]
    );
    if effective_id is null then
      raise exception 'Visao nao autorizada.';
    end if;
  end if;

  select
    profile.slug,
    app_user.code,
    coalesce(
      nullif(btrim(app_user.display_name), ''),
      nullif(btrim(app_user.code), ''),
      profile.name
    )
  into
    effective_profile_slug,
    effective_owner_code,
    effective_display_name
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = effective_id
    and app_user.is_active
  limit 1;

  if effective_profile_slug is null then
    raise exception 'Usuario indisponivel.';
  end if;

  select count(*)::integer
  into available_days
  from public.app_daily_routing_snapshots snapshot
  where snapshot.reference_date between target_start_date and target_end_date;

  if available_days = 0 then
    return jsonb_build_object(
      'available', false,
      'applicable', true,
      'reference_date', target_start_date,
      'start_date', target_start_date,
      'end_date', target_end_date,
      'requested_days', requested_days,
      'available_days', 0,
      'missing_dates', coalesce((
        select jsonb_agg(day_value::date order by day_value)
        from generate_series(
          target_start_date,
          target_end_date,
          interval '1 day'
        ) day_value
      ), '[]'::jsonb),
      'effective_profile_slug', effective_profile_slug,
      'effective_owner_code', effective_owner_code,
      'effective_display_name', effective_display_name,
      'selected_scope_profile_slug',
        nullif(btrim(target_scope_profile_slug), ''),
      'selected_scope_owner_code',
        nullif(btrim(target_scope_owner_code), ''),
      'available_scopes', available_scopes,
      'planned', 0,
      'purchased', 0,
      'pending', 0,
      'percent', null,
      'sale_amount', 0,
      'map_available', false,
      'seller_summaries', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  applicable := case
    when effective_profile_slug = 'supervisor'
      then effective_owner_code not in ('33', '35')
    when effective_profile_slug = 'vendedor' then exists (
      select 1
      from public.app_daily_routing_snapshots snapshot
      cross join lateral jsonb_array_elements(
        coalesce(snapshot.payload -> 'sellers', '[]'::jsonb)
      ) seller
      where snapshot.reference_date between target_start_date and target_end_date
        and seller ->> 'seller_code' = effective_owner_code
        and coalesce((seller ->> 'eligible')::boolean, false)
    )
    else effective_profile_slug in (
      'coordenador', 'gerencia', 'diretoria', 'outros', 'admin'
    )
  end;

  with snapshots as materialized (
    select snapshot.reference_date, snapshot.payload
    from public.app_daily_routing_snapshots snapshot
    where snapshot.reference_date between target_start_date and target_end_date
  ),
  scoped_sellers as materialized (
    select snapshot.reference_date, seller.value as seller
    from snapshots snapshot
    cross join lateral jsonb_array_elements(
      coalesce(snapshot.payload -> 'sellers', '[]'::jsonb)
    ) seller
    where applicable
      and coalesce((seller.value ->> 'eligible')::boolean, false)
      and public.app_scope_matches(
        effective_profile_slug,
        effective_owner_code,
        seller.value ->> 'seller_code',
        seller.value ->> 'supervisor_code',
        seller.value ->> 'coordinator_code'
      )
  ),
  occurrences as materialized (
    select
      snapshot.reference_date,
      item.value || jsonb_build_object(
        'reference_date', snapshot.reference_date,
        'seller_name', seller.seller ->> 'seller_name',
        'supervisor_code', seller.seller ->> 'supervisor_code',
        'coordinator_code', seller.seller ->> 'coordinator_code'
      ) as item
    from snapshots snapshot
    cross join lateral jsonb_array_elements(
      coalesce(snapshot.payload -> 'items', '[]'::jsonb)
    ) item
    join scoped_sellers seller
      on seller.reference_date = snapshot.reference_date
     and seller.seller ->> 'seller_code' = item.value ->> 'seller_code'
  ),
  seller_totals as (
    select
      item ->> 'seller_code' as seller_code,
      max(item ->> 'seller_name') as seller_name,
      max(item ->> 'supervisor_code') as supervisor_code,
      max(item ->> 'coordinator_code') as coordinator_code,
      count(*)::integer as planned,
      count(*) filter (
        where coalesce((item ->> 'purchased')::boolean, false)
      )::integer as purchased,
      coalesce(sum(coalesce(nullif(item ->> 'sale_amount', '')::numeric, 0)), 0)
        as sale_amount
    from occurrences
    group by item ->> 'seller_code'
  ),
  totals as (
    select
      count(*)::integer as planned,
      count(*) filter (
        where coalesce((item ->> 'purchased')::boolean, false)
      )::integer as purchased,
      coalesce(sum(coalesce(nullif(item ->> 'sale_amount', '')::numeric, 0)), 0)
        as sale_amount
    from occurrences
  )
  select jsonb_build_object(
    'available', true,
    'applicable', applicable,
    'reference_date', target_start_date,
    'start_date', target_start_date,
    'end_date', target_end_date,
    'requested_days', requested_days,
    'available_days', available_days,
    'missing_dates', coalesce((
      select jsonb_agg(day_value::date order by day_value)
      from generate_series(
        target_start_date,
        target_end_date,
        interval '1 day'
      ) day_value
      where not exists (
        select 1
        from snapshots snapshot
        where snapshot.reference_date = day_value::date
      )
    ), '[]'::jsonb),
    'snapshot_id', case when requested_days = 1 then (
      select snapshot.payload ->> 'snapshot_id'
      from snapshots snapshot
      limit 1
    ) else null end,
    'source_updated_at', (
      select max(nullif(snapshot.payload ->> 'source_updated_at', '')::timestamptz)
      from snapshots snapshot
    ),
    'routing_updated_at', (
      select max(nullif(snapshot.payload ->> 'routing_updated_at', '')::timestamptz)
      from snapshots snapshot
    ),
    'effective_profile_slug', effective_profile_slug,
    'effective_owner_code', effective_owner_code,
    'effective_display_name', effective_display_name,
    'selected_scope_profile_slug',
      nullif(btrim(target_scope_profile_slug), ''),
    'selected_scope_owner_code',
      nullif(btrim(target_scope_owner_code), ''),
    'available_scopes', available_scopes,
    'planned', total.planned,
    'purchased', total.purchased,
    'pending', total.planned - total.purchased,
    'percent', case when total.planned > 0
      then round(total.purchased::numeric * 100 / total.planned, 2)
      else null end,
    'sale_amount', total.sale_amount,
    'map_available', effective_profile_slug = 'vendedor' and total.planned > 0,
    'seller_summaries', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'seller_code', seller.seller_code,
          'seller_name', seller.seller_name,
          'supervisor_code', seller.supervisor_code,
          'coordinator_code', seller.coordinator_code,
          'planned', seller.planned,
          'purchased', seller.purchased,
          'pending', seller.planned - seller.purchased,
          'percent', case when seller.planned > 0
            then round(seller.purchased::numeric * 100 / seller.planned, 2)
            else null end,
          'sale_amount', seller.sale_amount
        )
        order by lower(seller.seller_name), seller.seller_code
      )
      from seller_totals seller
    ), '[]'::jsonb),
    'items', case when effective_profile_slug = 'vendedor' then coalesce((
      select jsonb_agg(
        occurrence.item
        order by
          occurrence.reference_date,
          coalesce(nullif(occurrence.item ->> 'route_code', '')::integer, 0),
          coalesce(nullif(occurrence.item ->> 'route_sequence', '')::integer, 0),
          lower(occurrence.item ->> 'customer_name'),
          occurrence.item ->> 'customer_code'
      )
      from occurrences occurrence
    ), '[]'::jsonb) else '[]'::jsonb end
  )
  into result
  from totals total;

  return result;
end;
$$;

revoke all on function public.get_routing_analysis_period(
  date, date, text, text
) from public, anon;
grant execute on function public.get_routing_analysis_period(
  date, date, text, text
) to authenticated, service_role;

comment on function public.get_routing_analysis_period(
  date, date, text, text
) is 'Resumo hierarquico e roteiro detalhado por periodo de ate 31 dias.';

-- Internal batch used by the Commitment module. The result is keyed by
-- "profile|code" and only contains scopes with at least one planned visit.
create or replace function public.get_routing_performance_by_scope(
  target_start_date date,
  target_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  requested_days integer;
  available_days integer;
  routing_updated_at timestamptz;
  result jsonb;
begin
  if target_start_date is null
     or target_end_date is null
     or target_end_date < target_start_date then
    raise exception 'Periodo da roteirizacao invalido.';
  end if;

  requested_days := target_end_date - target_start_date + 1;
  if requested_days > 31 then
    raise exception 'O periodo da roteirizacao deve ter no maximo 31 dias.';
  end if;

  select
    count(*)::integer,
    max(nullif(snapshot.payload ->> 'source_updated_at', '')::timestamptz)
  into available_days, routing_updated_at
  from public.app_daily_routing_snapshots snapshot
  where snapshot.reference_date between target_start_date and target_end_date;

  with snapshots as materialized (
    select snapshot.reference_date, snapshot.payload
    from public.app_daily_routing_snapshots snapshot
    where snapshot.reference_date between target_start_date and target_end_date
  ),
  eligible_sellers as materialized (
    select snapshot.reference_date, seller.value as seller
    from snapshots snapshot
    cross join lateral jsonb_array_elements(
      coalesce(snapshot.payload -> 'sellers', '[]'::jsonb)
    ) seller
    where coalesce((seller.value ->> 'eligible')::boolean, false)
  ),
  occurrences as materialized (
    select
      seller.seller ->> 'supervisor_code' as supervisor_code,
      seller.seller ->> 'coordinator_code' as coordinator_code,
      coalesce((item.value ->> 'purchased')::boolean, false) as purchased,
      coalesce(nullif(item.value ->> 'sale_amount', '')::numeric, 0)
        as sale_amount
    from snapshots snapshot
    cross join lateral jsonb_array_elements(
      coalesce(snapshot.payload -> 'items', '[]'::jsonb)
    ) item
    join eligible_sellers seller
      on seller.reference_date = snapshot.reference_date
     and seller.seller ->> 'seller_code' = item.value ->> 'seller_code'
  ),
  scope_occurrences as (
    select
      'supervisor'::text as profile_slug,
      occurrence.supervisor_code as owner_code,
      occurrence.purchased,
      occurrence.sale_amount
    from occurrences occurrence
    where nullif(btrim(occurrence.supervisor_code), '') is not null
      and occurrence.supervisor_code not in ('33', '35')

    union all

    select
      'coordenador'::text as profile_slug,
      occurrence.coordinator_code as owner_code,
      occurrence.purchased,
      occurrence.sale_amount
    from occurrences occurrence
    where nullif(btrim(occurrence.coordinator_code), '') is not null
  ),
  totals as (
    select
      scope.profile_slug,
      scope.owner_code,
      count(*)::integer as planned,
      count(*) filter (where scope.purchased)::integer as purchased,
      round(coalesce(sum(scope.sale_amount), 0), 2) as sale_amount
    from scope_occurrences scope
    group by scope.profile_slug, scope.owner_code
  )
  select coalesce(jsonb_object_agg(
    total.profile_slug || '|' || total.owner_code,
    jsonb_build_object(
      'routing_planned', total.planned,
      'routing_purchased', total.purchased,
      'routing_percent', case when total.planned > 0
        then round(total.purchased::numeric * 100 / total.planned, 2)
        else null end,
      'routing_sale_amount', total.sale_amount,
      'routing_requested_days', requested_days,
      'routing_available_days', available_days,
      'routing_updated_at', routing_updated_at
    )
  ), '{}'::jsonb)
  into result
  from totals total;

  return result;
end;
$$;

revoke all on function public.get_routing_performance_by_scope(date, date)
  from public, anon, authenticated;

comment on function public.get_routing_performance_by_scope(date, date) is
  'Desempenho de roteirizacao por supervisor e coordenador para uso interno.';
