create or replace function public.evaluate_push_notifications(
  target_reference_date date default (timezone('America/Sao_Paulo', now()))::date,
  target_changed_since timestamptz default null,
  force_initial_notifications boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reference_date date := coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date);
  changed_since timestamptz := coalesce(target_changed_since, timezone('utc', now()) - interval '6 hours');
  threshold_values integer[] := array[25, 50, 75, 90, 100];
  recipient_row record;
  metric_row record;
  previous_state record;
  threshold_value integer;
  selected_threshold integer;
  metric_label text;
  title_text text;
  body_text text;
  source_key_text text;
  queued_count integer := 0;
  state_count integer := 0;
  return_row record;
begin
  for recipient_row in
    select distinct
      u.auth_user_id,
      u.code,
      coalesce(p.slug, 'sem_perfil') as profile_slug
    from public.app_push_tokens pt
    join public.app_users u on u.auth_user_id = pt.user_id
    left join public.app_profiles p on p.id = u.profile_id
    where pt.enabled = true
      and pt.remember_login_enabled = true
      and pt.notifications_enabled = true
      and pt.revoked_at is null
      and u.is_active = true
      and coalesce(p.slug, '') in ('vendedor', 'supervisor', 'coordenador')
  loop
    for metric_row in
      select *
      from public.get_push_performance_metrics(
        recipient_row.profile_slug,
        recipient_row.code,
        reference_date
      )
    loop
      select *
        into previous_state
      from public.app_push_metric_progress_state state
      where state.recipient_user_id = recipient_row.auth_user_id
        and state.metric_key = metric_row.metric_key
        and state.period_key = metric_row.period_key
        and state.period_start = metric_row.period_start
      limit 1;

      if previous_state.id is null then
        insert into public.app_push_metric_progress_state (
          recipient_user_id,
          metric_key,
          period_key,
          period_start,
          period_end,
          last_progress_pct,
          last_actual_value,
          last_target_value
        )
        values (
          recipient_row.auth_user_id,
          metric_row.metric_key,
          metric_row.period_key,
          metric_row.period_start,
          metric_row.period_end,
          coalesce(metric_row.progress_pct, 0),
          coalesce(metric_row.actual_value, 0),
          coalesce(metric_row.target_value, 0)
        );
        state_count := state_count + 1;
      end if;

      selected_threshold := null;

      if metric_row.progress_pct is not null then
        foreach threshold_value in array threshold_values loop
          if (
            (previous_state.id is null and force_initial_notifications)
            or (
              previous_state.id is not null
              and coalesce(previous_state.last_progress_pct, 0) < threshold_value
            )
          ) and metric_row.progress_pct >= threshold_value then
            selected_threshold := threshold_value;
          end if;
        end loop;
      end if;

      if selected_threshold is not null then
        metric_label := case metric_row.metric_key
          when 'financial' then 'meta financeira'
          when 'sku' then 'meta de SKU'
          else 'meta de positivacao'
        end;

        if metric_row.period_key = 'monthly' then
          title_text := 'Meta mensal avancando!';
          body_text := format(
            'Parabens! Voce atingiu %s%% da %s mensal. Continue nesse ritmo!',
            selected_threshold,
            metric_label
          );
        else
          title_text := 'Meta diaria avancando!';
          body_text := format(
            'Boa! Voce atingiu %s%% da %s de hoje. Continue buscando o proximo marco!',
            selected_threshold,
            metric_label
          );
        end if;

        source_key_text := format(
          'goal:%s:%s:%s:%s:%s:%s',
          recipient_row.auth_user_id,
          metric_row.period_key,
          metric_row.metric_key,
          metric_row.period_start,
          metric_row.period_end,
          selected_threshold
        );

        if public.queue_push_notification_event(
          recipient_row.auth_user_id,
          recipient_row.profile_slug,
          recipient_row.code,
          case
            when metric_row.period_key = 'monthly' then 'monthly_goal_threshold'
            else 'daily_goal_threshold'
          end,
          metric_row.metric_key,
          metric_row.period_key,
          metric_row.period_start,
          metric_row.period_end,
          selected_threshold,
          source_key_text,
          title_text,
          body_text,
          jsonb_build_object(
            'module',
              case
                when metric_row.period_key = 'monthly' then 'performance'
                else 'home_daily'
              end,
            'metric', metric_row.metric_key,
            'period', metric_row.period_key,
            'thresholdPercent', selected_threshold,
            'periodStart', metric_row.period_start,
            'periodEnd', metric_row.period_end
          )
        ) then
          queued_count := queued_count + 1;
        end if;
      end if;

      update public.app_push_metric_progress_state
         set period_end = metric_row.period_end,
             last_progress_pct = coalesce(metric_row.progress_pct, 0),
             last_actual_value = coalesce(metric_row.actual_value, 0),
             last_target_value = coalesce(metric_row.target_value, 0),
             updated_at = timezone('utc', now())
       where recipient_user_id = recipient_row.auth_user_id
         and metric_key = metric_row.metric_key
         and period_key = metric_row.period_key
         and period_start = metric_row.period_start;
    end loop;
  end loop;

  for return_row in
    with active_recipients as (
      select distinct
        u.auth_user_id,
        u.code,
        coalesce(p.slug, 'sem_perfil') as profile_slug
      from public.app_push_tokens pt
      join public.app_users u on u.auth_user_id = pt.user_id
      left join public.app_profiles p on p.id = u.profile_id
      where pt.enabled = true
        and pt.remember_login_enabled = true
        and pt.notifications_enabled = true
        and pt.revoked_at is null
        and u.is_active = true
        and coalesce(p.slug, '') in ('vendedor', 'supervisor', 'coordenador')
    ),
    return_orders as (
      select
        ri.return_date,
        ri.numped,
        ri.codusur,
        ri.codsupervisor,
        ri.codgerente,
        round(sum(ri.item_value), 2)::numeric as total_value,
        max(ri.updated_at) as last_changed_at
      from public.app_return_order_items ri
      where ri.return_date between reference_date - 1 and reference_date
        and ri.updated_at >= changed_since
      group by
        ri.return_date,
        ri.numped,
        ri.codusur,
        ri.codsupervisor,
        ri.codgerente
    )
    select
      ar.auth_user_id,
      ar.code,
      ar.profile_slug,
      ro.return_date,
      ro.numped,
      ro.codusur,
      ro.total_value
    from active_recipients ar
    join return_orders ro
      on (
        (ar.profile_slug = 'vendedor' and ro.codusur = ar.code)
        or (ar.profile_slug = 'supervisor' and ro.codsupervisor = ar.code)
        or (ar.profile_slug = 'coordenador' and ro.codgerente = ar.code)
      )
  loop
    source_key_text := format(
      'return:%s:%s:%s:%s:%s',
      return_row.auth_user_id,
      return_row.return_date,
      return_row.numped,
      return_row.codusur,
      return_row.profile_slug
    );

    if public.queue_push_notification_event(
      return_row.auth_user_id,
      return_row.profile_slug,
      return_row.code,
      'return_created',
      'returns',
      'daily',
      return_row.return_date,
      return_row.return_date,
      null,
      source_key_text,
      'Nova devolucao lancada',
      format('Foi lancada uma nova devolucao no seu usuario. Valor total: R$ %s', replace(to_char(abs(return_row.total_value), 'FM999G999G999G990D00'), '.', ',')),
      jsonb_build_object(
        'module', 'returns',
        'period', 'today',
        'returnDate', return_row.return_date,
        'orderNumber', return_row.numped,
        'totalValue', return_row.total_value
      )
    ) then
      queued_count := queued_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'queued_events', queued_count,
    'initialized_metric_states', state_count,
    'reference_date', reference_date,
    'changed_since', changed_since
  );
end;
$$;

revoke all on function public.evaluate_push_notifications(date, timestamptz, boolean)
  from public;
grant execute on function public.evaluate_push_notifications(date, timestamptz, boolean)
  to service_role;
