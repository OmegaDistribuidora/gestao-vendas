update public.app_users
set display_name = replace(display_name, 'UsuÃ¡rio', 'Usuário')
where display_name like '%UsuÃ¡rio%';

update public.app_users
set display_name = replace(display_name, 'Usu�rio', 'Usuário')
where display_name like '%Usu�rio%';

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

  select jsonb_build_object(
    'active_users',
      coalesce((
        select count(*)
        from (
          select le.user_id
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          union
          select mu.user_id
          from public.app_module_usage_events mu
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
        ) active_users
        join public.app_users u on u.auth_user_id = active_users.user_id
        where u.is_active = true
      ), 0),
    'total_logins',
      coalesce((
        select count(*)
        from public.app_login_events le
        where le.logged_in_at between window_start and window_end
          and (target_user_id is null or le.user_id = target_user_id)
      ), 0),
    'total_module_opens',
      coalesce((
        select count(*)
        from public.app_module_usage_events mu
        where mu.opened_at between window_start and window_end
          and (target_user_id is null or mu.user_id = target_user_id)
      ), 0),
    'total_minutes',
      coalesce((
        select round(sum(coalesce(mu.duration_seconds, 0)) / 60.0, 1)
        from public.app_module_usage_events mu
        where mu.opened_at between window_start and window_end
          and (target_user_id is null or mu.user_id = target_user_id)
      ), 0),
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
            coalesce(nullif(u.display_name, ''), u.code) as label,
            count(*)::numeric as value
          from public.app_login_events le
          join public.app_users u on u.auth_user_id = le.user_id
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1
        ) as bucket
      ), '[]'::jsonb),
    'modules_by_open_count',
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
            count(*)::numeric as value
          from public.app_module_usage_events mu
          join public.app_modules m on m.id = mu.module_id
          where mu.opened_at between window_start and window_end
            and (target_user_id is null or mu.user_id = target_user_id)
          group by 1
        ) as bucket
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
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_hour',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order
        )
        from (
          select
            lpad(extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int::text, 2, '0') || ':00' as label,
            count(*)::numeric as value,
            extract(hour from le.logged_in_at at time zone 'America/Sao_Paulo')::int as sort_order
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1, 3
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_weekday',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'label', bucket.label,
            'value', bucket.value
          )
          order by bucket.sort_order
        )
        from (
          select
            case extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int
              when 0 then 'Domingo'
              when 1 then 'Segunda'
              when 2 then 'Terça'
              when 3 then 'Quarta'
              when 4 then 'Quinta'
              when 5 then 'Sexta'
              else 'Sábado'
            end as label,
            count(*)::numeric as value,
            extract(dow from le.logged_in_at at time zone 'America/Sao_Paulo')::int as sort_order
          from public.app_login_events le
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1, 3
        ) as bucket
      ), '[]'::jsonb),
    'logins_by_profile',
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
            coalesce(p.name, 'Sem perfil') as label,
            count(*)::numeric as value
          from public.app_login_events le
          left join public.app_profiles p on p.slug = le.profile_slug
          where le.logged_in_at between window_start and window_end
            and (target_user_id is null or le.user_id = target_user_id)
          group by 1
        ) as bucket
      ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_usage_report(timestamptz, timestamptz, uuid) to authenticated;
