drop function if exists public.get_usage_report(timestamptz, timestamptz, uuid);
drop function if exists public.get_usage_report(timestamptz, timestamptz, uuid, text, text[]);

create function public.get_usage_report(
  window_start timestamptz,
  window_end timestamptz,
  target_user_id uuid default null,
  target_coordinator_code text default null,
  target_profile_slugs text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  normalized_coordinator_code text := nullif(trim(coalesce(target_coordinator_code, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Acesso negado.';
  end if;

  with profile_order as (
    select *
    from (
      values
        ('diretoria', 1),
        ('coordenador', 2),
        ('supervisor', 3),
        ('vendedor', 4),
        ('outros', 5),
        ('sem_perfil', 6)
    ) as t(slug, sort_order)
  ),
  user_scope as (
    select
      u.auth_user_id as user_id,
      case
        when nullif(u.code, '') is not null and nullif(u.display_name, '') is not null
          then u.code || ' - ' || u.display_name
        else coalesce(nullif(u.display_name, ''), nullif(u.code, ''), u.technical_email)
      end as user_label,
      coalesce(p.name, 'Sem perfil') as profile_name,
      coalesce(p.slug, 'sem_perfil') as profile_slug,
      u.code,
      u.coordinator_code,
      u.is_active
    from public.app_users u
    left join public.app_profiles p on p.id = u.profile_id
    where coalesce(p.slug, 'sem_perfil') <> 'admin'
      and (target_user_id is null or u.auth_user_id = target_user_id)
      and (
        target_profile_slugs is null
        or cardinality(target_profile_slugs) = 0
        or coalesce(p.slug, 'sem_perfil') = any(target_profile_slugs)
      )
      and (
        normalized_coordinator_code is null
        or (
          coalesce(p.slug, 'sem_perfil') in ('vendedor', 'supervisor', 'coordenador')
          and (
            u.coordinator_code = normalized_coordinator_code
            or (
              coalesce(p.slug, 'sem_perfil') = 'coordenador'
              and u.code = normalized_coordinator_code
            )
          )
        )
      )
  ),
  filtered_logins as (
    select
      le.user_id,
      le.logged_in_at,
      floor(extract(epoch from le.logged_in_at) / 300)::bigint as score_window
    from public.app_login_events le
    join user_scope us on us.user_id = le.user_id
    where le.logged_in_at between window_start and window_end
      and us.is_active = true
  ),
  filtered_modules as (
    select
      mae.user_id,
      mae.module_key,
      mae.module_name,
      mae.opened_at,
      floor(extract(epoch from mae.opened_at) / 300)::bigint as score_window
    from public.app_module_access_events mae
    join user_scope us on us.user_id = mae.user_id
    where mae.opened_at between window_start and window_end
      and us.is_active = true
      and mae.module_key not in ('home', 'home_daily_notification')
      and lower(trim(mae.module_name)) not in ('inicio', 'início', 'resumo de hoje')
  ),
  login_points as (
    select
      fl.user_id,
      count(distinct fl.score_window)::numeric as value
    from filtered_logins fl
    group by fl.user_id
  ),
  module_points as (
    select
      fm.user_id,
      count(distinct (fm.module_key || ':' || fm.score_window::text))::numeric as value,
      count(distinct fm.module_key)::numeric as distinct_modules
    from filtered_modules fm
    group by fm.user_id
  ),
  user_points as (
    select
      us.user_id,
      us.user_label,
      us.profile_name,
      us.profile_slug,
      coalesce(lp.value, 0)::numeric as login_points,
      coalesce(mp.value, 0)::numeric as module_points,
      coalesce(mp.distinct_modules, 0)::numeric as distinct_modules,
      (coalesce(lp.value, 0) + coalesce(mp.value, 0))::numeric as total_points,
      coalesce(po.sort_order, 99) as profile_sort
    from user_scope us
    left join login_points lp on lp.user_id = us.user_id
    left join module_points mp on mp.user_id = us.user_id
    left join profile_order po on po.slug = us.profile_slug
    where us.is_active = true
      and (coalesce(lp.value, 0) + coalesce(mp.value, 0)) > 0
  )
  select jsonb_build_object(
    'active_users',
      coalesce((select count(distinct user_id) from filtered_logins), 0),
    'total_logins',
      coalesce((select count(*) from filtered_logins), 0),
    'active_users_details',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', up.user_label,
            'value', up.total_points,
            'secondary_value', up.login_points,
            'metadata', jsonb_build_object(
              'user_id', up.user_id,
              'profile_slug', up.profile_slug,
              'profile_name', up.profile_name,
              'login_points', up.login_points,
              'module_points', up.module_points,
              'distinct_modules', up.distinct_modules
            )
          )
          order by up.total_points desc, up.user_label
        )
        from user_points up
      ), '[]'::jsonb),
    'logins_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.user_label,
            'value', bucket.value,
            'metadata', jsonb_build_object('user_id', bucket.user_id)
          )
          order by bucket.value desc, bucket.user_label
        )
        from (
          select us.user_id, us.user_label, count(*)::numeric as value
          from filtered_logins fl
          join user_scope us on us.user_id = fl.user_id
          group by 1, 2
        ) bucket
      ), '[]'::jsonb),
    'logins_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', bucket.profile_name, 'value', bucket.value)
          order by bucket.sort_order, bucket.profile_name
        )
        from (
          select
            us.profile_name,
            count(*)::numeric as value,
            coalesce(po.sort_order, 99) as sort_order
          from filtered_logins fl
          join user_scope us on us.user_id = fl.user_id
          left join profile_order po on po.slug = us.profile_slug
          group by 1, 3
        ) bucket
      ), '[]'::jsonb),
    'logins_by_user_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', grouped.profile_name, 'items', grouped.items)
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value,
                'metadata', jsonb_build_object('user_id', bucket.user_id)
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              us.profile_name,
              us.user_id,
              us.user_label,
              count(*)::numeric as value,
              coalesce(po.sort_order, 99) as sort_order
            from filtered_logins fl
            join user_scope us on us.user_id = fl.user_id
            left join profile_order po on po.slug = us.profile_slug
            group by 1, 2, 3, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_hour_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', grouped.profile_name, 'items', grouped.items)
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object('label', bucket.hour_label, 'value', bucket.value)
              order by bucket.hour_sort
            ) as items
          from (
            select
              us.profile_name,
              lpad(extract(hour from fl.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as hour_label,
              count(*)::numeric as value,
              extract(hour from fl.logged_in_at at time zone 'America/Sao_Paulo')::int as hour_sort,
              coalesce(po.sort_order, 99) as sort_order
            from filtered_logins fl
            join user_scope us on us.user_id = fl.user_id
            left join profile_order po on po.slug = us.profile_slug
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_hour_users',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', grouped.hour_label, 'items', grouped.items)
          order by grouped.hour_sort
        )
        from (
          select
            bucket.hour_label,
            bucket.hour_sort,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value,
                'metadata', jsonb_build_object('user_id', bucket.user_id)
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              lpad(extract(hour from fl.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as hour_label,
              extract(hour from fl.logged_in_at at time zone 'America/Sao_Paulo')::int as hour_sort,
              us.user_id,
              us.user_label,
              count(*)::numeric as value
            from filtered_logins fl
            join user_scope us on us.user_id = fl.user_id
            group by 1, 2, 3, 4
          ) bucket
          group by bucket.hour_label, bucket.hour_sort
        ) grouped
      ), '[]'::jsonb),
    'logins_by_weekday_by_profile',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', grouped.profile_name, 'items', grouped.items)
          order by grouped.sort_order, grouped.profile_name
        )
        from (
          select
            bucket.profile_name,
            bucket.sort_order,
            jsonb_agg(
              jsonb_build_object('label', bucket.weekday_label, 'value', bucket.value)
              order by bucket.weekday_sort
            ) as items
          from (
            select
              us.profile_name,
              case extract(dow from fl.logged_in_at at time zone 'America/Sao_Paulo')::int
                when 0 then 'Domingo'
                when 1 then 'Segunda'
                when 2 then 'Terca'
                when 3 then 'Quarta'
                when 4 then 'Quinta'
                when 5 then 'Sexta'
                else 'Sabado'
              end as weekday_label,
              count(*)::numeric as value,
              extract(dow from fl.logged_in_at at time zone 'America/Sao_Paulo')::int as weekday_sort,
              coalesce(po.sort_order, 99) as sort_order
            from filtered_logins fl
            join user_scope us on us.user_id = fl.user_id
            left join profile_order po on po.slug = us.profile_slug
            group by 1, 2, 4, 5
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'logins_by_weekday_users',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', grouped.weekday_label, 'items', grouped.items)
          order by grouped.weekday_sort
        )
        from (
          select
            bucket.weekday_label,
            bucket.weekday_sort,
            jsonb_agg(
              jsonb_build_object(
                'label', bucket.user_label,
                'value', bucket.value,
                'metadata', jsonb_build_object('user_id', bucket.user_id)
              )
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              case extract(dow from fl.logged_in_at at time zone 'America/Sao_Paulo')::int
                when 0 then 'Domingo'
                when 1 then 'Segunda'
                when 2 then 'Terca'
                when 3 then 'Quarta'
                when 4 then 'Quinta'
                when 5 then 'Sexta'
                else 'Sabado'
              end as weekday_label,
              extract(dow from fl.logged_in_at at time zone 'America/Sao_Paulo')::int as weekday_sort,
              us.user_id,
              us.user_label,
              count(*)::numeric as value
            from filtered_logins fl
            join user_scope us on us.user_id = fl.user_id
            group by 1, 2, 3, 4
          ) bucket
          group by bucket.weekday_label, bucket.weekday_sort
        ) grouped
      ), '[]'::jsonb),
    'module_opens_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', bucket.module_name, 'value', bucket.value)
          order by bucket.value desc, bucket.module_name
        )
        from (
          select fm.module_name, count(*)::numeric as value
          from filtered_modules fm
          group by 1
        ) bucket
      ), '[]'::jsonb),
    'module_users_by_module',
      coalesce((
        select jsonb_agg(
          jsonb_build_object('label', grouped.module_name, 'items', grouped.items)
          order by grouped.module_name
        )
        from (
          select
            bucket.module_name,
            jsonb_agg(
              jsonb_build_object('label', bucket.user_label, 'value', bucket.value)
              order by bucket.value desc, bucket.user_label
            ) as items
          from (
            select
              fm.module_name,
              us.user_label,
              count(*)::numeric as value
            from filtered_modules fm
            join user_scope us on us.user_id = fm.user_id
            group by 1, 2
          ) bucket
          group by bucket.module_name
        ) grouped
      ), '[]'::jsonb),
    'module_users_by_user',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', grouped.user_label,
            'value', grouped.distinct_modules,
            'items', grouped.items,
            'metadata', jsonb_build_object('user_id', grouped.user_id)
          )
          order by grouped.distinct_modules desc, grouped.user_label
        )
        from (
          select
            bucket.user_id,
            bucket.user_label,
            count(distinct bucket.module_key)::numeric as distinct_modules,
            jsonb_agg(
              jsonb_build_object('label', bucket.module_name, 'value', bucket.value)
              order by bucket.value desc, bucket.module_name
            ) as items
          from (
            select
              us.user_id,
              us.user_label,
              fm.module_key,
              fm.module_name,
              count(*)::numeric as value
            from filtered_modules fm
            join user_scope us on us.user_id = fm.user_id
            group by 1, 2, 3, 4
          ) bucket
          group by bucket.user_id, bucket.user_label
        ) grouped
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid, text, text[])
  to authenticated;
