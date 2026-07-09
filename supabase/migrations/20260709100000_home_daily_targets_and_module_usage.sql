create table if not exists public.app_module_access_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  profile_slug text not null default '',
  module_key text not null,
  module_name text not null,
  opened_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_app_module_access_events_opened_at
  on public.app_module_access_events (opened_at desc);

create index if not exists idx_app_module_access_events_module_opened
  on public.app_module_access_events (module_key, opened_at desc);

create index if not exists idx_app_module_access_events_user_opened
  on public.app_module_access_events (user_id, opened_at desc);

alter table public.app_module_access_events enable row level security;

grant select, insert, delete on public.app_module_access_events
  to authenticated, service_role;

drop policy if exists "module_access_events_select_admin" on public.app_module_access_events;
create policy "module_access_events_select_admin"
on public.app_module_access_events
for select
to authenticated
using (public.is_admin());

drop policy if exists "module_access_events_insert_self" on public.app_module_access_events;
create policy "module_access_events_insert_self"
on public.app_module_access_events
for insert
to authenticated
with check (auth.uid() = user_id);

create or replace function public.record_module_access(
  target_module_key text,
  target_module_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  normalized_module_key text;
  normalized_module_name text;
begin
  select coalesce(p.slug, '')
    into current_profile_slug
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active = true
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  normalized_module_key := lower(trim(coalesce(target_module_key, '')));
  normalized_module_name := trim(coalesce(target_module_name, ''));

  if normalized_module_key = '' then
    raise exception 'Modulo invalido.';
  end if;

  if normalized_module_name = '' then
    normalized_module_name := normalized_module_key;
  end if;

  insert into public.app_module_access_events (
    user_id,
    profile_slug,
    module_key,
    module_name,
    opened_at
  )
  values (
    auth.uid(),
    current_profile_slug,
    normalized_module_key,
    normalized_module_name,
    timezone('utc', now())
  );
end;
$$;

grant execute on function public.record_module_access(text, text)
  to authenticated;

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
  distinct_products integer;
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

  with visible_sales_orders as (
    select distinct
      s.sales_date,
      s.numped,
      s.codcli,
      s.codusur
    from public.app_sales_daily_snapshots s
    where s.sales_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then s.codusur = current_user_code
          when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
          else true
        end
      )
  )
  select coalesce(count(distinct nullif(soi.codprod, '')), 0)
    into distinct_products
  from public.app_sales_order_items soi
  join visible_sales_orders v
    on v.sales_date = soi.sales_date
   and v.numped = soi.numped
   and v.codcli = soi.codcli
   and v.codusur = soi.codusur;

  if coalesce(distinct_products, 0) = 0 and coalesce(gross_orders, 0) > 0 then
    select coalesce(round(sum(f.mix), 0)::integer, 0)
      into distinct_products
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
    'distinct_products', coalesce(distinct_products, 0),
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz, text)
  to authenticated;

drop function if exists public.get_usage_report(timestamptz, timestamptz, uuid);

create function public.get_usage_report(
  window_start timestamptz,
  window_end timestamptz,
  target_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  with user_scope as (
    select
      u.auth_user_id as user_id,
      coalesce(nullif(u.display_name, ''), nullif(u.code, ''), u.technical_email) as user_label,
      coalesce(p.name, 'Sem perfil') as profile_name,
      coalesce(p.slug, 'sem_perfil') as profile_slug,
      u.is_active
    from public.app_users u
    left join public.app_profiles p on p.id = u.profile_id
    where target_user_id is null or u.auth_user_id = target_user_id
  ),
  profile_order as (
    select *
    from (
      values
        ('admin', 1),
        ('diretoria', 2),
        ('coordenador', 3),
        ('supervisor', 4),
        ('vendedor', 5),
        ('outros', 6),
        ('sem_perfil', 7)
    ) as t(slug, sort_order)
  )
  select jsonb_build_object(
    'active_users',
      coalesce((
        select count(*)
        from (
          select distinct le.user_id
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
        ) active_users
        join user_scope us on us.user_id = active_users.user_id
        where us.is_active = true
      ), 0),
    'total_logins',
      coalesce((
        select count(*)
        from public.app_login_events le
        where le.logged_in_at between window_start and window_end
          and (target_user_id is null or le.user_id = target_user_id)
      ), 0),
    'active_users_details',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.profile_sort, bucket.label
        )
        from (
          select
            us.user_label as label,
            1::numeric as value,
            coalesce(po.sort_order, 99) as profile_sort
          from (
            select distinct le.user_id
            from public.app_login_events le
            where le.logged_in_at between window_start and window_end
              and (target_user_id is null or le.user_id = target_user_id)
          ) active_users
          join user_scope us on us.user_id = active_users.user_id
          left join profile_order po on po.slug = us.profile_slug
          where us.is_active = true
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.label
        )
        from (
          select
            us.user_label as label,
            count(*)::numeric as value
          from public.app_login_events le
          join user_scope us on us.user_id = le.user_id
          where le.logged_in_at between window_start and window_end
          group by 1
        ) bucket
      ), '[]'::jsonb),
    'logins_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order, bucket.label
        )
        from (
          select
            us.profile_name as label,
            count(*)::numeric as value,
            coalesce(po.sort_order, 99) as sort_order
          from public.app_login_events le
          join user_scope us on us.user_id = le.user_id
          left join profile_order po on po.slug = us.profile_slug
          where le.logged_in_at between window_start and window_end
          group by 1, 3
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              us.profile_name,
              us.user_label,
              count(*)::numeric as value,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_hour_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.hour_label,
                'value', bucket.value
              )
              order by bucket.hour_sort
            ) as items
          from (
            select
              us.profile_name,
              lpad(extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as hour_label,
              count(*)::numeric as value,
              extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int as hour_sort,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_weekday_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.profile_name,
            'items', grouped.items
          )
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.weekday_label,
                'value', bucket.value
              )
              order by bucket.weekday_sort
            ) as items
          from (
            select
              us.profile_name,
              case extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int
                when 0 then 'Domingo'
                when 1 then 'Segunda'
                when 2 then 'Terca'
                when 3 then 'Quarta'
                when 4 then 'Quinta'
                when 5 then 'Sexta'
                else 'Sabado'
              end as weekday_label,
              count(*)::numeric as value,
              extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int as weekday_sort,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_login_events le
            join user_scope us on us.user_id = le.user_id
            left join profile_order po on po.slug = us.profile_slug
            where le.logged_in_at between window_start and window_end
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'module_opens_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.module_name,
            'value', bucket.value
          )
          order by bucket.value desc, bucket.module_name
        )
        from (
          select
            mae.module_name,
            count(*)::numeric as value
          from public.app_module_access_events mae
          join user_scope us on us.user_id = mae.user_id
          where mae.opened_at between window_start and window_end
          group by 1
        ) bucket
      ), '[]'::jsonb),
    'module_users_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.module_name,
            'items', grouped.items
          )
          order by grouped.module_name
        )
        from (
          select
            bucket.module_name,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              mae.module_name,
              us.user_label,
              count(*)::numeric as value
            from public.app_module_access_events mae
            join user_scope us on us.user_id = mae.user_id
            where mae.opened_at between window_start and window_end
            group by 1, 2
          ) bucket
          group by bucket.module_name
        ) grouped
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid)
  to authenticated;
