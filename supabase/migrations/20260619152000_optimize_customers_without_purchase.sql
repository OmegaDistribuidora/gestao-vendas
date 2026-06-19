create index if not exists idx_app_sales_customer_seller_date
  on public.app_sales_daily_snapshots (codcli, codusur, sales_date desc, numped);

create or replace function public.get_customers_without_purchase(
  window_start timestamptz,
  window_end timestamptz,
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
  start_date date;
  end_date date;
  anchor_month date;
  prev_month_1 date;
  prev_month_2 date;
  prev_month_3 date;
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

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  anchor_month := date_trunc('month', start_date)::date;
  prev_month_1 := (anchor_month - interval '1 month')::date;
  prev_month_2 := (anchor_month - interval '2 months')::date;
  prev_month_3 := (anchor_month - interval '3 months')::date;

  requested_profile_slug := nullif(lower(trim(coalesce(target_scope_profile_slug, ''))), '');
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
      raise exception 'Escopo invalido para supervisor.';
    end if;
  elsif viewer_profile_slug = 'coordenador' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'coordenador';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'supervisor' and exists (
      select 1
      from public.app_users seller
      join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
      where seller.is_active = true
        and seller_profile.slug = 'vendedor'
        and coalesce(seller.supervisor_code, '') = requested_owner_code
        and coalesce(seller.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'supervisor';
      effective_owner_code := requested_owner_code;
    elsif requested_profile_slug = 'vendedor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'vendedor'
        and u.code = requested_owner_code
        and coalesce(u.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'vendedor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo invalido para coordenador.';
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
      raise exception 'Escopo invalido para o perfil atual.';
    end if;
  else
    aggregate_all_mode := true;
    effective_profile_slug := viewer_profile_slug;
    effective_owner_code := null;
  end if;

  last_updated_at := public.get_latest_sync_finished_at(
    array['oracle_customer_base_sync']
  );

  with available_scope_rows as (
    select distinct
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
      and viewer_profile_slug = 'supervisor'
      and p.slug = 'vendedor'
      and coalesce(u.supervisor_code, '') = viewer_user_code

    union all

    select distinct
      'supervisor' as profile_slug,
      seller.supervisor_code as owner_code,
      coalesce(nullif(btrim(supervisor.display_name), ''), seller.supervisor_code) as display_name,
      trim(
        case
          when btrim(coalesce(seller.supervisor_code, '')) <> ''
            and btrim(coalesce(supervisor.display_name, '')) <> ''
            then seller.supervisor_code || ' - ' || supervisor.display_name
          when btrim(coalesce(supervisor.display_name, '')) <> ''
            then supervisor.display_name
          else seller.supervisor_code
        end
      ) as label
    from public.app_users seller
    join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
    left join public.app_users supervisor on supervisor.code = seller.supervisor_code
    where seller.is_active = true
      and viewer_profile_slug = 'coordenador'
      and seller_profile.slug = 'vendedor'
      and coalesce(seller.coordinator_code, '') = viewer_user_code
      and coalesce(seller.supervisor_code, '') <> ''

    union all

    select distinct
      'vendedor' as profile_slug,
      seller.code as owner_code,
      coalesce(nullif(btrim(seller.display_name), ''), seller.code) as display_name,
      trim(
        case
          when btrim(coalesce(seller.code, '')) <> ''
            and btrim(coalesce(seller.display_name, '')) <> ''
            then seller.code || ' - ' || seller.display_name
          when btrim(coalesce(seller.display_name, '')) <> ''
            then seller.display_name
          else seller.code
        end
      ) as label
    from public.app_users seller
    join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
    where seller.is_active = true
      and viewer_profile_slug = 'coordenador'
      and seller_profile.slug = 'vendedor'
      and coalesce(seller.coordinator_code, '') = viewer_user_code

    union all

    select distinct
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
      and viewer_profile_slug in ('admin', 'diretoria', 'outros')
      and p.slug in ('coordenador', 'supervisor', 'vendedor')
  ),
  scoped_base as (
    select
      b.codcli,
      b.codusur,
      b.status_cliente,
      c.cliente,
      c.cod_cliente,
      c.fantasia,
      c.cod_fantasia,
      c.end_compl,
      c.bairro,
      c.cep,
      c.codatv,
      c.codcidade,
      c.codrede,
      c.codpraca,
      c.uf,
      c.limcred,
      c.codibge,
      c.status,
      c.motivo_bloq,
      c.dtbloq,
      c.cnpj,
      coalesce(nullif(seller.display_name, ''), b.codusur) as seller_name,
      coalesce(seller.supervisor_code, '') as codsupervisor,
      coalesce(seller.coordinator_code, '') as codgerente,
      coalesce(nullif(supervisor.display_name, ''), seller.supervisor_code, '') as supervisor_name,
      coalesce(nullif(coordinator.display_name, ''), seller.coordinator_code, '') as coordinator_name
    from public.app_customer_seller_bases b
    join public.app_customers c on c.codcli = b.codcli
    left join public.app_users seller on seller.code = b.codusur
    left join public.app_users supervisor on supervisor.code = seller.supervisor_code
    left join public.app_users coordinator on coordinator.code = seller.coordinator_code
    where lower(b.status_cliente) = 'desbloqueado'
      and (
        aggregate_all_mode
        or (effective_profile_slug = 'vendedor' and b.codusur = effective_owner_code)
        or (effective_profile_slug = 'supervisor' and coalesce(seller.supervisor_code, '') = effective_owner_code)
        or (effective_profile_slug = 'coordenador' and coalesce(seller.coordinator_code, '') = effective_owner_code)
      )
  ),
  base_rows as (
    select sb.*
    from scoped_base sb
    where not exists (
      select 1
      from public.app_sales_daily_snapshots s
      where s.codcli = sb.codcli
        and s.codusur = sb.codusur
        and s.sales_date between start_date and end_date
    )
  ),
  month_flags as (
    select
      br.codcli,
      br.codusur,
      bool_or(s.sales_date >= prev_month_1 and s.sales_date < anchor_month) as bought_prev_1,
      bool_or(s.sales_date >= prev_month_2 and s.sales_date < prev_month_1) as bought_prev_2,
      bool_or(s.sales_date >= prev_month_3 and s.sales_date < prev_month_2) as bought_prev_3
    from base_rows br
    join public.app_sales_daily_snapshots s
      on s.codcli = br.codcli
     and s.codusur = br.codusur
     and s.sales_date >= prev_month_3
     and s.sales_date < anchor_month
    group by br.codcli, br.codusur
  ),
  order_totals as (
    select
      br.codcli,
      br.codusur,
      s.numped,
      s.sales_date,
      round(sum(s.venda), 2) as total_amount,
      round(sum(s.volume), 4) as total_volume,
      count(*) as item_count
    from base_rows br
    join public.app_sales_daily_snapshots s
      on s.codcli = br.codcli
     and s.codusur = br.codusur
     and s.sales_date < start_date
    group by br.codcli, br.codusur, s.numped, s.sales_date
  ),
  ranked_orders as (
    select
      ot.*,
      row_number() over (
        partition by ot.codcli, ot.codusur
        order by ot.sales_date desc, ot.numped desc
      ) as order_rank
    from order_totals ot
  ),
  latest_orders as (
    select
      ro.codcli,
      ro.codusur,
      ro.sales_date as last_purchase_date,
      ro.total_amount as last_purchase_amount
    from ranked_orders ro
    where ro.order_rank = 1
  ),
  recent_orders as (
    select
      ro.codcli,
      ro.codusur,
      jsonb_agg(
        jsonb_build_object(
          'numped', ro.numped,
          'sales_date', ro.sales_date,
          'total_amount', ro.total_amount,
          'total_volume', ro.total_volume,
          'item_count', ro.item_count
        )
        order by ro.sales_date desc, ro.numped desc
      ) as orders
    from ranked_orders ro
    where ro.order_rank <= 3
    group by ro.codcli, ro.codusur
  ),
  enriched as (
    select
      br.*,
      lo.last_purchase_date,
      coalesce(lo.last_purchase_amount, 0) as last_purchase_amount,
      coalesce(ro.orders, '[]'::jsonb) as recent_orders,
      case
        when coalesce(mf.bought_prev_1, false)
          and coalesce(mf.bought_prev_2, false)
          and coalesce(mf.bought_prev_3, false)
          then 'Regular'
        when coalesce(mf.bought_prev_1, false)
          and coalesce(mf.bought_prev_2, false)
          then 'Semi-Regular'
        else 'Normal'
      end as regularity_label,
      case
        when lo.last_purchase_date is null then 9999
        else greatest(start_date - lo.last_purchase_date, 0)
      end as days_without_purchase
    from base_rows br
    left join month_flags mf
      on mf.codcli = br.codcli
     and mf.codusur = br.codusur
    left join latest_orders lo
      on lo.codcli = br.codcli
     and lo.codusur = br.codusur
    left join recent_orders ro
      on ro.codcli = br.codcli
     and ro.codusur = br.codusur
  )
  select jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'selected_scope_profile_slug', case when aggregate_all_mode then null else effective_profile_slug end,
    'selected_scope_owner_code', case when aggregate_all_mode then null else effective_owner_code end,
    'period_start', start_date,
    'period_end', end_date,
    'anchor_month', anchor_month,
    'last_updated_at', last_updated_at,
    'available_scopes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile_slug', a.profile_slug,
          'owner_code', a.owner_code,
          'display_name', a.display_name,
          'label', a.label
        )
        order by
          case a.profile_slug
            when 'coordenador' then 1
            when 'supervisor' then 2
            when 'vendedor' then 3
            else 4
          end,
          a.label
      )
      from available_scope_rows a
    ), '[]'::jsonb),
    'total_clients', coalesce((select count(*) from enriched), 0),
    'regular_clients', coalesce((select count(*) from enriched where regularity_label = 'Regular'), 0),
    'semi_regular_clients', coalesce((select count(*) from enriched where regularity_label = 'Semi-Regular'), 0),
    'normal_clients', coalesce((select count(*) from enriched where regularity_label = 'Normal'), 0),
    'customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'codcli', e.codcli,
          'client_name', e.cliente,
          'cod_cliente', e.cod_cliente,
          'fantasia', e.fantasia,
          'cod_fantasia', e.cod_fantasia,
          'address', e.end_compl,
          'district', e.bairro,
          'cep', e.cep,
          'activity_code', e.codatv,
          'city_code', e.codcidade,
          'network_code', e.codrede,
          'market_code', e.codpraca,
          'uf', e.uf,
          'credit_limit', e.limcred,
          'ibge_code', e.codibge,
          'status', e.status,
          'block_reason', e.motivo_bloq,
          'blocked_at', e.dtbloq,
          'cnpj', e.cnpj,
          'codusur', e.codusur,
          'seller_name', e.seller_name,
          'codsupervisor', e.codsupervisor,
          'supervisor_name', e.supervisor_name,
          'codgerente', e.codgerente,
          'coordinator_name', e.coordinator_name,
          'last_purchase_date', e.last_purchase_date,
          'last_purchase_amount', e.last_purchase_amount,
          'days_without_purchase', e.days_without_purchase,
          'regularity_label', e.regularity_label,
          'recent_orders', e.recent_orders
        )
        order by e.days_without_purchase desc, e.cliente, e.codcli, e.codusur
      )
      from enriched e
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_customers_without_purchase(timestamptz, timestamptz, text, text) to authenticated;
