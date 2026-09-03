-- Inclui o vendedor no detalhamento de clientes positivados da Home.
-- A funcao v2 e conectada somente ao dashboard v4 usado pela proxima versao;
-- os contratos consumidos pela versao publicada permanecem inalterados.

create or replace function public.get_home_positive_customers_v2(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile text;
  viewer_code text;
  start_date date := date(window_start at time zone 'America/Sao_Paulo');
  end_date date := date(window_end at time zone 'America/Sao_Paulo');
  month_start date;
  result jsonb;
begin
  select coalesce(profile.slug, 'sem_perfil'), app_user.code
    into viewer_profile, viewer_code
  from public.app_users app_user
  left join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  month_start := date_trunc('month', start_date)::date;

  with visible_month_sales as (
    select
      sale.codcli,
      sale.codusur,
      sale.codsupervisor,
      sale.codgerente,
      sale.sales_date,
      sale.venda
    from public.app_sales_daily_snapshots sale
    where sale.sales_date between month_start and end_date
      and public.app_scope_matches(
        viewer_profile,
        viewer_code,
        sale.codusur,
        sale.codsupervisor,
        sale.codgerente
      )
  ), first_purchase_in_month as (
    select codcli, min(sales_date) as first_purchase_date
    from visible_month_sales
    group by codcli
  ), visible_sales as (
    select codcli, sum(venda) as total_amount
    from visible_month_sales
    where sales_date between start_date and end_date
    group by codcli
  ), seller_totals as (
    select codcli, codusur, sum(venda) as seller_amount
    from visible_month_sales
    where sales_date between start_date and end_date
    group by codcli, codusur
  ), primary_seller as (
    select distinct on (codcli)
      codcli,
      codusur
    from seller_totals
    order by codcli, seller_amount desc, codusur
  ), resolved as (
    select
      visible.codcli,
      coalesce(
        nullif(btrim(customer.cliente), ''),
        nullif(btrim(customer.fantasia), ''),
        visible.codcli
      ) as client_name,
      round(visible.total_amount, 2) as total_amount,
      first_purchase.first_purchase_date between start_date and end_date
        as is_new_in_month,
      coalesce(primary_seller.codusur, '') as seller_code,
      coalesce(
        nullif(btrim(seller.display_name), ''),
        primary_seller.codusur,
        ''
      ) as seller_name
    from visible_sales visible
    join first_purchase_in_month first_purchase
      on first_purchase.codcli = visible.codcli
    left join primary_seller on primary_seller.codcli = visible.codcli
    left join public.app_customers customer on customer.codcli = visible.codcli
    left join public.app_users seller on seller.code = primary_seller.codusur
  )
  select jsonb_build_object(
    'total_clients', count(*),
    'total_new_customers', count(*) filter (where is_new_in_month),
    'total_amount', coalesce(round(sum(total_amount), 2), 0),
    'items', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'client_code', codcli,
          'client_name', client_name,
          'total_amount', total_amount,
          'is_new_in_month', is_new_in_month,
          'seller_code', seller_code,
          'seller_name', seller_name
        )
        order by is_new_in_month desc, total_amount desc, client_name, codcli
      ),
      '[]'::jsonb
    )
  )
  into result
  from resolved;

  return coalesce(
    result,
    jsonb_build_object(
      'total_clients', 0,
      'total_new_customers', 0,
      'total_amount', 0,
      'items', '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.get_home_positive_customers_v2(
  timestamptz, timestamptz
) from public, anon;
grant execute on function public.get_home_positive_customers_v2(
  timestamptz, timestamptz
) to authenticated;

create or replace function public.get_home_dashboard_v4(
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
  requested_profile_slug text := nullif(
    lower(btrim(coalesce(target_scope_profile_slug, ''))), ''
  );
  requested_owner_code text := nullif(
    btrim(coalesce(target_scope_owner_code, '')), ''
  );
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb;
  payload jsonb;
  positive_customers jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid() and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Filtro da Home incompleto.';
  end if;

  available_scopes := public.app_view_scope_options();
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug,
      requested_owner_code
    );
    if target_auth_user_id is null then
      raise exception 'Filtro da Home indisponivel para este usuario.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config(
        'request.jwt.claim.sub',
        target_auth_user_id::text,
        true
      );
    end if;

    payload := public.get_home_dashboard_v3(
      window_start,
      window_end,
      null,
      null
    );
    positive_customers := public.get_home_positive_customers_v2(
      window_start,
      window_end
    );
  exception when others then
    perform set_config(
      'request.jwt.claim.sub',
      coalesce(original_auth_user_id, ''),
      true
    );
    raise;
  end;
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(original_auth_user_id, ''),
    true
  );

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes,
    'positive_customers', positive_customers
  );
end;
$$;

revoke all on function public.get_home_dashboard_v4(
  timestamptz, timestamptz, text, text
) from public, anon;
grant execute on function public.get_home_dashboard_v4(
  timestamptz, timestamptz, text, text
) to authenticated;

comment on function public.get_home_positive_customers_v2(
  timestamptz, timestamptz
) is
  'Clientes positivados da Home com vendedor principal do periodo.';
