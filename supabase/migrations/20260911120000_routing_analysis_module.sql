-- Additive API for the Routing Analysis module. Kept local until emulator
-- approval. It reuses the daily snapshot already consumed by Home.
create or replace function public.get_routing_analysis(
  target_date date,
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
  snapshot jsonb;
  applicable boolean := true;
  available_scopes jsonb;
  result jsonb;
begin
  if target_date is null then
    raise exception 'Data obrigatoria.';
  end if;

  if not exists (
    select 1 from public.app_users
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

  select p.slug, u.code,
         coalesce(nullif(btrim(u.display_name), ''), nullif(btrim(u.code), ''), p.name)
    into effective_profile_slug, effective_owner_code, effective_display_name
  from public.app_users u
  join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = effective_id and u.is_active
  limit 1;

  if effective_profile_slug is null then
    raise exception 'Usuario indisponivel.';
  end if;

  select payload into snapshot
  from public.app_daily_routing_snapshots
  where reference_date = target_date;

  if snapshot is null then
    return jsonb_build_object(
      'available', false,
      'applicable', true,
      'reference_date', target_date,
      'effective_profile_slug', effective_profile_slug,
      'effective_owner_code', effective_owner_code,
      'effective_display_name', effective_display_name,
      'selected_scope_profile_slug', nullif(btrim(target_scope_profile_slug), ''),
      'selected_scope_owner_code', nullif(btrim(target_scope_owner_code), ''),
      'available_scopes', available_scopes,
      'seller_summaries', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  applicable := case
    when effective_profile_slug = 'supervisor' then effective_owner_code not in ('33', '35')
    when effective_profile_slug = 'vendedor' then exists (
      select 1
      from jsonb_array_elements(snapshot->'sellers') s
      where s->>'seller_code' = effective_owner_code
        and coalesce((s->>'eligible')::boolean, false)
    )
    else effective_profile_slug in (
      'coordenador', 'gerencia', 'diretoria', 'outros', 'admin'
    )
  end;

  with scoped_sellers as (
    select s
    from jsonb_array_elements(snapshot->'sellers') s
    where applicable
      and coalesce((s->>'eligible')::boolean, false)
      and public.app_scope_matches(
        effective_profile_slug,
        effective_owner_code,
        s->>'seller_code',
        s->>'supervisor_code',
        s->>'coordinator_code'
      )
  ), occurrences as (
    select i || jsonb_build_object(
      'seller_name', s->>'seller_name',
      'supervisor_code', s->>'supervisor_code',
      'coordinator_code', s->>'coordinator_code'
    ) as item
    from jsonb_array_elements(snapshot->'items') i
    join scoped_sellers on s->>'seller_code' = i->>'seller_code'
  ), seller_totals as (
    select
      item->>'seller_code' as seller_code,
      max(item->>'seller_name') as seller_name,
      max(item->>'supervisor_code') as supervisor_code,
      max(item->>'coordinator_code') as coordinator_code,
      count(*)::integer as planned,
      count(*) filter (where coalesce((item->>'purchased')::boolean, false))::integer as purchased,
      coalesce(sum((item->>'sale_amount')::numeric), 0) as sale_amount
    from occurrences
    group by item->>'seller_code'
  ), totals as (
    select
      count(*)::integer as planned,
      count(*) filter (where coalesce((item->>'purchased')::boolean, false))::integer as purchased,
      coalesce(sum((item->>'sale_amount')::numeric), 0) as sale_amount
    from occurrences
  )
  select jsonb_build_object(
    'available', true,
    'applicable', applicable,
    'reference_date', target_date,
    'snapshot_id', snapshot->>'snapshot_id',
    'source_updated_at', snapshot->>'source_updated_at',
    'routing_updated_at', snapshot->>'routing_updated_at',
    'effective_profile_slug', effective_profile_slug,
    'effective_owner_code', effective_owner_code,
    'effective_display_name', effective_display_name,
    'selected_scope_profile_slug', nullif(btrim(target_scope_profile_slug), ''),
    'selected_scope_owner_code', nullif(btrim(target_scope_owner_code), ''),
    'available_scopes', available_scopes,
    'planned', t.planned,
    'purchased', t.purchased,
    'pending', t.planned - t.purchased,
    'percent', case when t.planned > 0
      then round(t.purchased::numeric * 100 / t.planned, 2)
      else null end,
    'sale_amount', t.sale_amount,
    'map_available', effective_profile_slug = 'vendedor' and t.planned > 0,
    'seller_summaries', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'seller_code', seller_code,
          'seller_name', seller_name,
          'supervisor_code', supervisor_code,
          'coordinator_code', coordinator_code,
          'planned', planned,
          'purchased', purchased,
          'pending', planned - purchased,
          'percent', case when planned > 0
            then round(purchased::numeric * 100 / planned, 2)
            else null end,
          'sale_amount', sale_amount
        )
        order by lower(seller_name), seller_code
      ) from seller_totals
    ), '[]'::jsonb),
    'items', case when effective_profile_slug = 'vendedor' then coalesce((
      select jsonb_agg(item order by
        coalesce(nullif(item->>'route_code', '')::integer, 0),
        coalesce(nullif(item->>'route_sequence', '')::integer, 0),
        lower(item->>'customer_name'), item->>'customer_code')
      from occurrences
    ), '[]'::jsonb) else '[]'::jsonb end
  ) into result
  from totals t;

  return result;
end;
$$;

revoke all on function public.get_routing_analysis(date, text, text)
  from public, anon;
grant execute on function public.get_routing_analysis(date, text, text)
  to authenticated, service_role;

comment on function public.get_routing_analysis(date, text, text) is
  'Resumo hierarquico e roteiro detalhado de um vendedor por data.';
