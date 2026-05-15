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
          union
          select distinct mu.user_id
          from public.app_module_usage_events mu
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
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
            union
            select distinct mu.user_id
            from public.app_module_usage_events mu
            where mu.opened_at between window_start and window_end
              and (target_user_id is null or mu.user_id = target_user_id)
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
    'modules_by_open_count_by_profile',
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
                'label', bucket.module_name,
                'value', bucket.value
              )
              order by bucket.value desc, bucket.module_name
            ) as items
          from (
            select
              us.profile_name,
              m.name as module_name,
              count(*)::numeric as value,
              coalesce(po.sort_order, 99) as sort_order
            from public.app_module_usage_events mu
            join user_scope us on us.user_id = mu.user_id
            join public.app_modules m on m.id = mu.module_id
            left join profile_order po on po.slug = us.profile_slug
            where mu.opened_at between window_start and window_end
            group by 1, 2, 4
          ) bucket
          group by bucket.profile_name, bucket.sort_order
        ) grouped
      ), '[]'::jsonb),
    'minutes_by_module',
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
            m.name as label,
            round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1) as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
          group by 1
        ) bucket
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
                when 2 then 'Terça'
                when 3 then 'Quarta'
                when 4 then 'Quinta'
                when 5 then 'Sexta'
                else 'Sábado'
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
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid) to authenticated;
