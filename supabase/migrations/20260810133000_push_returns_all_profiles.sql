create or replace function public.evaluate_push_return_notifications_all_profiles(
  target_reference_date date default null,
  target_changed_since timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reference_date date := coalesce(target_reference_date, timezone('America/Sao_Paulo', now())::date);
  changed_since timestamptz := coalesce(target_changed_since, timezone('utc', now()) - interval '6 hours');
  return_row record;
  source_key_text text;
  queued_count integer := 0;
begin
  for return_row in
    with active_recipients as (
      select distinct u.auth_user_id, coalesce(u.code, '') code,
        coalesce(p.slug, 'sem_perfil') profile_slug
      from public.app_push_tokens pt
      join public.app_users u on u.auth_user_id=pt.user_id
      left join public.app_profiles p on p.id=u.profile_id
      where pt.enabled and pt.remember_login_enabled and pt.notifications_enabled
        and pt.revoked_at is null and u.is_active
        and coalesce(p.slug,'sem_perfil') not in ('sem_perfil','vendedor','supervisor','coordenador')
    ), return_orders as (
      select ri.return_date,ri.numped,ri.codusur,
        round(sum(ri.item_value),2)::numeric total_value
      from public.app_return_order_items ri
      where ri.return_date between reference_date-1 and reference_date
        and ri.updated_at>=changed_since
      group by ri.return_date,ri.numped,ri.codusur
    )
    select ar.auth_user_id,ar.code,ar.profile_slug,ro.*
    from active_recipients ar cross join return_orders ro
  loop
    source_key_text:=format('return:%s:%s:%s:%s:%s',return_row.auth_user_id,
      return_row.return_date,return_row.numped,return_row.codusur,return_row.profile_slug);
    if public.queue_push_notification_event(
      return_row.auth_user_id,return_row.profile_slug,return_row.code,
      'return_created','returns','daily',return_row.return_date,return_row.return_date,
      null,source_key_text,'Nova devolucao lancada',
      format('Foi lancada uma nova devolucao. Valor total: R$ %s',
        replace(to_char(abs(return_row.total_value),'FM999G999G999G990D00'),'.',',')),
      jsonb_build_object('module','returns','period','today','returnDate',return_row.return_date,
        'orderNumber',return_row.numped,'totalValue',return_row.total_value)
    ) then queued_count:=queued_count+1; end if;
  end loop;
  return jsonb_build_object('queued_events',queued_count,'reference_date',reference_date,
    'changed_since',changed_since);
end;
$$;

revoke all on function public.evaluate_push_return_notifications_all_profiles(date,timestamptz) from public;
grant execute on function public.evaluate_push_return_notifications_all_profiles(date,timestamptz) to service_role;

create or replace function public.handle_push_relevant_sync_applied()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status='applied' and (tg_op='INSERT' or old.status is distinct from new.status)
    and new.job_name in ('oracle_sales_sync','oracle_billing_sync','oracle_returns_financial_sync','oracle_return_items_sync') then
    perform public.evaluate_push_notifications(new.window_end,
      coalesce(new.started_at,timezone('utc',now())-interval '6 hours'),false);
    if new.job_name in ('oracle_returns_financial_sync','oracle_return_items_sync') then
      perform public.evaluate_push_return_notifications_all_profiles(new.window_end,
        coalesce(new.started_at,timezone('utc',now())-interval '6 hours'));
    end if;
  end if;
  return new;
end;
$$;
