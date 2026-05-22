create or replace function public.get_latest_sync_finished_at(
  job_names text[]
)
returns timestamptz
language sql
security definer
set search_path = public
as $$
  select max(r.finished_at)
  from public.etl_sync_runs r
  where r.status = 'applied'
    and r.job_name = any(job_names)
$$;

grant execute on function public.get_latest_sync_finished_at(text[]) to authenticated, service_role;

create or replace function public.get_home_kpis(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  normalized_metric_source text;
  gross_amount numeric(18, 2);
  gross_volume numeric(18, 4);
  gross_orders integer;
  gross_positivation integer;
  return_amount numeric(18, 2);
  return_volume numeric(18, 4);
  return_orders integer;
  return_positivation integer;
  last_sales_updated_at timestamptz;
  last_financial_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');
  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  last_sales_updated_at := public.get_latest_sync_finished_at(
    array['oracle_sales_sync']
  );

  last_financial_updated_at := public.get_latest_sync_finished_at(
    array['oracle_billing_sync', 'oracle_returns_financial_sync']
  );

  if normalized_metric_source = 'venda' then
    select
      coalesce(round(sum(s.venda), 2), 0),
      coalesce(round(sum(s.volume), 4), 0),
      coalesce(count(distinct s.numped), 0),
      coalesce(count(distinct s.codcli), 0)
      into gross_amount, gross_volume, gross_orders, gross_positivation
    from public.app_sales_daily_snapshots s
    where s.sales_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then s.codusur = current_user_code
          when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
          else true
        end
      );
  else
    select
      coalesce(round(sum(f.faturamento), 2), 0),
      coalesce(round(sum(f.volume), 4), 0),
      coalesce(count(distinct f.numped), 0),
      coalesce(count(distinct f.codcli), 0)
      into gross_amount, gross_volume, gross_orders, gross_positivation
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then f.codusur = current_user_code
          when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
          else true
        end
      );
  end if;

  select
    coalesce(round(sum(f.faturamento), 2), 0),
    coalesce(round(sum(f.volume), 4), 0),
    coalesce(count(distinct f.numped), 0),
    coalesce(count(distinct f.codcli), 0)
    into return_amount, return_volume, return_orders, return_positivation
  from public.app_financial_snapshots f
  where f.snapshot_type = 'D'
    and f.snapshot_date between start_date and end_date
    and (
      case
        when current_profile_slug = 'vendedor' then f.codusur = current_user_code
        when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
        else true
      end
    );

  return jsonb_build_object(
    'metric_source', normalized_metric_source,
    'gross_amount', coalesce(gross_amount, 0),
    'gross_volume', coalesce(gross_volume, 0),
    'gross_orders', coalesce(gross_orders, 0),
    'gross_positivation', coalesce(gross_positivation, 0),
    'return_amount', coalesce(return_amount, 0),
    'return_volume', coalesce(return_volume, 0),
    'return_orders', coalesce(return_orders, 0),
    'return_positivation', coalesce(return_positivation, 0),
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at
  );
end;
$$;

create or replace function public.get_supplier_analysis(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  normalized_metric_source text;
  payload jsonb;
  last_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');
  normalized_metric_source := lower(trim(coalesce(metric_source, 'venda')));

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  if normalized_metric_source not in ('venda', 'faturamento') then
    raise exception 'Fonte de indicador invalida.';
  end if;

  if normalized_metric_source = 'venda' then
    last_updated_at := public.get_latest_sync_finished_at(array['oracle_sales_sync']);

    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
          select
            s.codfornec,
            coalesce(sp.supplier_name, s.codfornec) as supplier_name,
            round(sum(s.venda), 2) as gross_amount,
            round(sum(s.volume), 4) as gross_volume,
            count(distinct s.numped) as gross_orders,
            count(distinct s.codcli) as gross_positivation
          from public.app_sales_daily_snapshots s
          left join public.app_suppliers sp on sp.codfornec = s.codfornec
          where s.sales_date between start_date and end_date
            and (
              case
                when current_profile_slug = 'vendedor' then s.codusur = current_user_code
                when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
                when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
                else true
              end
            )
          group by s.codfornec, coalesce(sp.supplier_name, s.codfornec)
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  else
    last_updated_at := public.get_latest_sync_finished_at(
      array['oracle_billing_sync']
    );

    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
          select
            f.codfornec,
            coalesce(sp.supplier_name, f.codfornec) as supplier_name,
            round(sum(f.faturamento), 2) as gross_amount,
            round(sum(f.volume), 4) as gross_volume,
            count(distinct f.numped) as gross_orders,
            count(distinct f.codcli) as gross_positivation
          from public.app_financial_snapshots f
          left join public.app_suppliers sp on sp.codfornec = f.codfornec
          where f.snapshot_type = 'F'
            and f.snapshot_date between start_date and end_date
            and (
              case
                when current_profile_slug = 'vendedor' then f.codusur = current_user_code
                when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
                when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
                else true
              end
            )
          group by f.codfornec, coalesce(sp.supplier_name, f.codfornec)
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  end if;

  return coalesce(payload, jsonb_build_object(
    'metric_source', normalized_metric_source,
    'last_updated_at', last_updated_at,
    'suppliers', '[]'::jsonb
  ));
end;
$$;

create or replace function public.get_return_analysis(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  payload jsonb;
  last_updated_at timestamptz;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  last_updated_at := public.get_latest_sync_finished_at(
    array['oracle_return_items_sync']
  );

  with sellers as (
    select
      u.code,
      max(u.display_name) as seller_name
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where p.slug = 'vendedor'
    group by u.code
  ),
  filtered as (
    select *
    from public.app_return_order_items ri
    where ri.return_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then ri.codusur = current_user_code
          when current_profile_slug = 'supervisor' then ri.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then ri.codgerente = current_user_code
          else true
        end
      )
  ),
  orders as (
    select
      ri.return_date,
      ri.numped,
      ri.codcli,
      max(ri.client_name) as client_name,
      max(ri.codusur) as codusur,
      coalesce(max(s.seller_name), '') as seller_name,
      max(ri.return_reason) as return_reason,
      round(sum(ri.item_value), 2) as total_value,
      round(sum(ri.volume), 4) as total_volume,
      round(sum(ri.quantity), 4) as total_quantity,
      count(*) as item_count
    from filtered ri
    left join sellers s on s.code = ri.codusur
    group by ri.return_date, ri.numped, ri.codcli
  )
  select jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', coalesce((select round(sum(item_value), 2) from filtered), 0),
    'total_clients', coalesce((select count(distinct codcli) from filtered), 0),
    'total_volume', coalesce((select round(sum(volume), 4) from filtered), 0),
    'total_orders', coalesce((select count(distinct numped) from filtered), 0),
    'orders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'return_date', o.return_date,
          'numped', o.numped,
          'codcli', o.codcli,
          'client_name', o.client_name,
          'codusur', o.codusur,
          'seller_name', o.seller_name,
          'return_reason', o.return_reason,
          'total_value', o.total_value,
          'total_volume', o.total_volume,
          'total_quantity', o.total_quantity,
          'item_count', o.item_count
        )
        order by o.return_date desc, o.total_value desc, o.numped desc
      )
      from orders o
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', 0,
    'total_clients', 0,
    'total_volume', 0,
    'total_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;
