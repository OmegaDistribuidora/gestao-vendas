-- Ensure that concurrent Edge Function invocations cannot process the same
-- notification event. The row lock and the status transition happen in one
-- database statement, and only rows claimed by this invocation are returned.
create or replace function public.claim_app_push_notification_events(
  target_limit integer default 50
)
returns table (
  id uuid,
  recipient_user_id uuid,
  title text,
  body text,
  data jsonb,
  attempts integer
)
language sql
security definer
set search_path = public
as $function$
  with candidates as (
    select event.id
      from public.app_push_notification_events as event
     where event.status = 'queued'
     order by event.created_at asc
     limit least(greatest(coalesce(target_limit, 50), 1), 200)
     for update skip locked
  ),
  claimed as (
    update public.app_push_notification_events as event
       set status = 'sending',
           attempts = event.attempts + 1,
           last_error = null
      from candidates
     where event.id = candidates.id
       and event.status = 'queued'
    returning
      event.id,
      event.recipient_user_id,
      event.title,
      event.body,
      event.data,
      event.attempts
  )
  select
    claimed.id,
    claimed.recipient_user_id,
    claimed.title,
    claimed.body,
    claimed.data,
    claimed.attempts
  from claimed;
$function$;

revoke all on function public.claim_app_push_notification_events(integer)
  from public, anon, authenticated;
grant execute on function public.claim_app_push_notification_events(integer)
  to service_role;

comment on function public.claim_app_push_notification_events(integer) is
  'Atomically claims queued push events so concurrent senders cannot deliver the same event.';
