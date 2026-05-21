create or replace function public.get_delinquency_overview(
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_profile_slug text;
  requested_owner_code text;
  effective_profile_slug text;
  effective_owner_code text;
  aggregate_all_mode boolean := false;
  group_by_profile_slug text;
  payload jsonb;
  last_updated_at timestamptz;
  current_month_start date;
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

  requested_profile_slug := nullif(
    lower(trim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code := nullif(trim(coalesce(target_scope_owner_code, '')), '');

  if viewer_profile_slug = 'vendedor' then
    effective_profile_slug := 'vendedor';
    effective_owner_code := viewer_user_code;
  elsif viewer_profile_slug = 'supervisor' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'supervisor';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'vendedor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'vendedor'
        and u.code = requested_owner_code
        and coalesce(u.supervisor_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'vendedor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de inadimplencia invalido para supervisor.';
    end if;
  elsif viewer_profile_slug = 'coordenador' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'coordenador';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'supervisor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'supervisor'
        and u.code = requested_owner_code
        and coalesce(u.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'supervisor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de inadimplencia invalido para coordenador.';
    end if;
  elsif viewer_profile_slug in ('admin', 'diretoria', 'outros') then
    if requested_profile_slug is null or requested_owner_code is null then
      aggregate_all_mode := true;
      effective_profile_slug := viewer_profile_slug;
      effective_owner_code := null;
    elsif requested_profile_slug in ('coordenador', 'supervisor', 'vendedor')
      and exists (
        select 1
        from public.app_users u
        join public.app_profiles p on p.id = u.profile_id
        where u.is_active = true
          and p.slug = requested_profile_slug
          and u.code = requested_owner_code
      ) then
      effective_profile_slug := requested_profile_slug;
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo de inadimplencia invalido para o perfil atual.';
    end if;
  else
    aggregate_all_mode := true;
    effective_profile_slug := viewer_profile_slug;
    effective_owner_code := null;
  end if;

  group_by_profile_slug := case
    when effective_profile_slug = 'supervisor' then 'vendedor'
    when effective_profile_slug = 'coordenador' then 'supervisor'
    when aggregate_all_mode or effective_profile_slug in ('admin', 'diretoria', 'outros')
      then 'coordenador'
    else null
  end;

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  select max(updated_at)
    into last_updated_at
  from public.app_delinquency_items;

  with available_scope_rows as (
    select
      p.slug as profile_slug,
      u.code as owner_code,
      coalesce(nullif(btrim(u.display_name), ''), u.code) as display_name,
      trim(
        case
          when btrim(coalesce(u.code, '')) <> '' and btrim(coalesce(u.display_name, '')) <> ''
            then u.code || ' - ' || u.display_name
          when btrim(coalesce(u.display_name, '')) <> ''
            then u.display_name
          else u.code
        end
      ) as label
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.is_active = true
      and (
        (viewer_profile_slug = 'supervisor' and p.slug = 'vendedor' and coalesce(u.supervisor_code, '') = viewer_user_code)
        or
        (viewer_profile_slug = 'coordenador' and p.slug = 'supervisor' and coalesce(u.coordinator_code, '') = viewer_user_code)
        or
        (viewer_profile_slug in ('admin', 'diretoria', 'outros') and p.slug in ('coordenador', 'supervisor', 'vendedor'))
      )
  ),
  actor_names as (
    select
      p.slug as profile_slug,
      u.code,
      coalesce(nullif(btrim(u.display_name), ''), u.code) as display_name
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.is_active = true
      and p.slug in ('vendedor', 'supervisor', 'coordenador')
  ),
  filtered as (
    select
      di.*,
      coalesce(nullif(btrim(di.client_name), ''), di.codcli) as resolved_client_name,
      coalesce(seller.display_name, di.codusur) as seller_name,
      coalesce(supervisor.display_name, di.codsupervisor) as supervisor_name,
      coalesce(coordinator.display_name, di.codgerente) as coordinator_name,
      case
        when group_by_profile_slug = 'vendedor' then di.codusur
        when group_by_profile_slug = 'supervisor' then di.codsupervisor
        when group_by_profile_slug = 'coordenador' then di.codgerente
        else null
      end as group_code,
      case
        when group_by_profile_slug = 'vendedor' then coalesce(seller.display_name, di.codusur)
        when group_by_profile_slug = 'supervisor' then coalesce(supervisor.display_name, di.codsupervisor)
        when group_by_profile_slug = 'coordenador' then coalesce(coordinator.display_name, di.codgerente)
        else null
      end as group_name
    from public.app_delinquency_items di
    left join actor_names seller
      on seller.profile_slug = 'vendedor'
     and seller.code = di.codusur
    left join actor_names supervisor
      on supervisor.profile_slug = 'supervisor'
     and supervisor.code = di.codsupervisor
    left join actor_names coordinator
      on coordinator.profile_slug = 'coordenador'
     and coordinator.code = di.codgerente
    where coalesce(di.tipo, 'Geral') = 'Geral'
      and di.dtvenc < current_month_start
      and (
        case
          when effective_profile_slug = 'vendedor' then di.codusur = effective_owner_code
          when effective_profile_slug = 'supervisor' then di.codsupervisor = effective_owner_code
          when effective_profile_slug = 'coordenador' then di.codgerente = effective_owner_code
          else true
        end
      )
  ),
  order_rows as (
    select
      f.group_code,
      max(f.group_name) as group_name,
      f.codcli,
      max(f.resolved_client_name) as client_name,
      f.numped,
      f.dtemissao,
      f.dtvenc,
      max(f.prestacao) as prestacao,
      max(f.duplicata) as duplicata,
      max(f.tipo) as tipo,
      round(sum(f.valor), 2)::numeric(18, 2) as total_amount
    from filtered f
    group by
      f.group_code,
      f.codcli,
      f.numped,
      f.dtemissao,
      f.dtvenc
  ),
  client_rows as (
    select
      o.group_code,
      max(o.group_name) as group_name,
      o.codcli,
      max(o.client_name) as client_name,
      round(sum(o.total_amount), 2)::numeric(18, 2) as total_amount,
      count(distinct o.numped) as total_orders,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'numped', o.numped,
            'dtemissao', o.dtemissao,
            'dtvenc', o.dtvenc,
            'prestacao', o.prestacao,
            'duplicata', o.duplicata,
            'tipo', o.tipo,
            'valor', o.total_amount
          )
          order by o.dtvenc desc, o.numped desc
        ),
        '[]'::jsonb
      ) as orders
    from order_rows o
    group by
      o.group_code,
      o.codcli
  ),
  group_rows as (
    select
      c.group_code,
      max(c.group_name) as group_name,
      round(sum(c.total_amount), 2)::numeric(18, 2) as total_amount,
      count(*) as total_clients,
      sum(c.total_orders)::integer as total_orders,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'codcli', c.codcli,
            'client_name', c.client_name,
            'total_amount', c.total_amount,
            'total_orders', c.total_orders,
            'orders', c.orders
          )
          order by c.total_amount desc, c.client_name, c.codcli
        ),
        '[]'::jsonb
      ) as clients
    from client_rows c
    where c.group_code is not null
    group by c.group_code
  )
  select jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'group_by_profile_slug', group_by_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'last_updated_at', last_updated_at,
    'total_amount', coalesce((select round(sum(valor), 2) from filtered), 0),
    'total_orders', coalesce((select count(distinct numped) from filtered), 0),
    'total_clients', coalesce((select count(distinct codcli) from filtered), 0),
    'available_scopes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile_slug', scope.profile_slug,
          'owner_code', scope.owner_code,
          'display_name', scope.display_name,
          'label', scope.label
        )
        order by
          case scope.profile_slug
            when 'coordenador' then 1
            when 'supervisor' then 2
            when 'vendedor' then 3
            else 9
          end,
          scope.display_name,
          scope.owner_code
      )
      from available_scope_rows scope
    ), '[]'::jsonb),
    'clients', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'codcli', c.codcli,
          'client_name', c.client_name,
          'total_amount', c.total_amount,
          'total_orders', c.total_orders,
          'orders', c.orders
        )
        order by c.total_amount desc, c.client_name, c.codcli
      )
      from client_rows c
      where c.group_code is null
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile_slug', group_by_profile_slug,
          'code', g.group_code,
          'display_name', g.group_name,
          'label',
            case
              when btrim(coalesce(g.group_code, '')) <> '' and btrim(coalesce(g.group_name, '')) <> ''
                then g.group_code || ' - ' || g.group_name
              when btrim(coalesce(g.group_name, '')) <> ''
                then g.group_name
              else g.group_code
            end,
          'total_amount', g.total_amount,
          'total_orders', g.total_orders,
          'total_clients', g.total_clients,
          'clients', g.clients
        )
        order by g.total_amount desc, g.group_name, g.group_code
      )
      from group_rows g
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'group_by_profile_slug', group_by_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'last_updated_at', last_updated_at,
    'total_amount', 0,
    'total_orders', 0,
    'total_clients', 0,
    'available_scopes', '[]'::jsonb,
    'clients', '[]'::jsonb,
    'groups', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_delinquency_overview(text, text) to authenticated;
