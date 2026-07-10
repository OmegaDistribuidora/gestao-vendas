create extension if not exists pgcrypto;

create table if not exists public.app_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  profile_slug text not null,
  user_code text not null,
  fcm_token text not null,
  token_hash text not null unique,
  device_id text not null,
  platform text not null default 'android',
  app_version text,
  remember_login_enabled boolean not null default true,
  notifications_enabled boolean not null default true,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_app_push_tokens_user_enabled
  on public.app_push_tokens (user_id, enabled, last_seen_at desc);

create index if not exists idx_app_push_tokens_device
  on public.app_push_tokens (device_id);

drop trigger if exists set_app_push_tokens_updated_at on public.app_push_tokens;
create trigger set_app_push_tokens_updated_at
before update on public.app_push_tokens
for each row
execute function public.set_updated_at();

alter table public.app_push_tokens enable row level security;

revoke all on public.app_push_tokens from anon, authenticated;
grant select, insert, update, delete on public.app_push_tokens to service_role;

create table if not exists public.app_push_notification_events (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  recipient_profile_slug text not null,
  recipient_user_code text not null,
  event_type text not null check (
    event_type in (
      'daily_goal_threshold',
      'monthly_goal_threshold',
      'return_created'
    )
  ),
  metric_key text not null,
  period_key text,
  period_start date,
  period_end date,
  threshold_percent integer,
  source_key text not null unique,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (
    status in ('queued', 'sending', 'sent', 'skipped', 'failed')
  ),
  attempts integer not null default 0,
  last_error text,
  queued_at timestamptz not null default timezone('utc', now()),
  sent_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_app_push_events_status_created
  on public.app_push_notification_events (status, created_at);

create index if not exists idx_app_push_events_recipient_created
  on public.app_push_notification_events (recipient_user_id, created_at desc);

drop trigger if exists set_app_push_notification_events_updated_at
  on public.app_push_notification_events;
create trigger set_app_push_notification_events_updated_at
before update on public.app_push_notification_events
for each row
execute function public.set_updated_at();

alter table public.app_push_notification_events enable row level security;

revoke all on public.app_push_notification_events from anon, authenticated;
grant select, insert, update, delete on public.app_push_notification_events
  to service_role;

create table if not exists public.app_push_notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.app_push_notification_events (id) on delete cascade,
  token_id uuid references public.app_push_tokens (id) on delete set null,
  token_hash text not null,
  status text not null check (status in ('sent', 'failed', 'skipped')),
  firebase_message_id text,
  error_message text,
  sent_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_app_push_deliveries_event
  on public.app_push_notification_deliveries (event_id);

alter table public.app_push_notification_deliveries enable row level security;

revoke all on public.app_push_notification_deliveries from anon, authenticated;
grant select, insert, update, delete on public.app_push_notification_deliveries
  to service_role;

create table if not exists public.app_push_metric_progress_state (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.app_users (auth_user_id) on delete cascade,
  metric_key text not null,
  period_key text not null check (period_key in ('daily', 'monthly')),
  period_start date not null,
  period_end date not null,
  last_progress_pct numeric(8, 2) not null default 0,
  last_actual_value numeric(18, 4) not null default 0,
  last_target_value numeric(18, 4) not null default 0,
  updated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  unique (recipient_user_id, metric_key, period_key, period_start)
);

create index if not exists idx_app_push_metric_state_user_period
  on public.app_push_metric_progress_state (
    recipient_user_id,
    period_key,
    period_start
  );

alter table public.app_push_metric_progress_state enable row level security;

revoke all on public.app_push_metric_progress_state from anon, authenticated;
grant select, insert, update, delete on public.app_push_metric_progress_state
  to service_role;

create or replace function public.register_push_token(
  target_fcm_token text,
  target_device_id text,
  target_platform text default 'android',
  target_app_version text default null,
  target_remember_login_enabled boolean default false,
  target_notifications_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_row record;
  normalized_token text;
  normalized_device_id text;
  normalized_platform text;
  computed_token_hash text;
  token_row_id uuid;
  should_enable boolean;
begin
  if auth.uid() is null then
    raise exception 'Sessao autenticada obrigatoria.';
  end if;

  normalized_token := btrim(coalesce(target_fcm_token, ''));
  normalized_device_id := btrim(coalesce(target_device_id, ''));
  normalized_platform := lower(btrim(coalesce(target_platform, 'android')));

  if normalized_token = '' then
    raise exception 'Token FCM obrigatorio.';
  end if;

  if normalized_device_id = '' then
    normalized_device_id := 'unknown:' || auth.uid()::text;
  end if;

  select
    u.auth_user_id,
    u.code,
    coalesce(p.slug, 'sem_perfil') as profile_slug,
    u.is_active
    into current_user_row
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_user_row.auth_user_id is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  computed_token_hash := encode(digest(normalized_token, 'sha256'), 'hex');
  should_enable :=
    current_user_row.is_active
    and current_user_row.profile_slug in ('vendedor', 'supervisor', 'coordenador')
    and coalesce(target_remember_login_enabled, false)
    and coalesce(target_notifications_enabled, false);

  if not should_enable then
    update public.app_push_tokens
       set enabled = false,
           notifications_enabled = coalesce(target_notifications_enabled, false),
           remember_login_enabled = coalesce(target_remember_login_enabled, false),
           revoked_at = timezone('utc', now()),
           last_seen_at = timezone('utc', now())
     where token_hash = computed_token_hash
        or (user_id = current_user_row.auth_user_id and device_id = normalized_device_id);

    return jsonb_build_object(
      'registered', false,
      'enabled', false,
      'profile_slug', current_user_row.profile_slug
    );
  end if;

  update public.app_push_tokens
     set enabled = false,
         revoked_at = timezone('utc', now()),
         last_seen_at = timezone('utc', now())
   where enabled = true
     and device_id = normalized_device_id
     and user_id <> current_user_row.auth_user_id;

  insert into public.app_push_tokens (
    user_id,
    profile_slug,
    user_code,
    fcm_token,
    token_hash,
    device_id,
    platform,
    app_version,
    remember_login_enabled,
    notifications_enabled,
    enabled,
    revoked_at,
    last_seen_at
  )
  values (
    current_user_row.auth_user_id,
    current_user_row.profile_slug,
    current_user_row.code,
    normalized_token,
    computed_token_hash,
    normalized_device_id,
    normalized_platform,
    nullif(btrim(coalesce(target_app_version, '')), ''),
    true,
    true,
    true,
    null,
    timezone('utc', now())
  )
  on conflict (token_hash) do update
     set user_id = excluded.user_id,
         profile_slug = excluded.profile_slug,
         user_code = excluded.user_code,
         fcm_token = excluded.fcm_token,
         device_id = excluded.device_id,
         platform = excluded.platform,
         app_version = excluded.app_version,
         remember_login_enabled = true,
         notifications_enabled = true,
         enabled = true,
         revoked_at = null,
         last_seen_at = timezone('utc', now())
  returning id into token_row_id;

  return jsonb_build_object(
    'registered', true,
    'enabled', true,
    'token_id', token_row_id,
    'profile_slug', current_user_row.profile_slug
  );
end;
$$;

revoke all on function public.register_push_token(
  text,
  text,
  text,
  text,
  boolean,
  boolean
) from public;
grant execute on function public.register_push_token(
  text,
  text,
  text,
  text,
  boolean,
  boolean
) to authenticated;

create or replace function public.revoke_push_token(
  target_fcm_token text default null,
  target_device_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_token text;
  normalized_device_id text;
  computed_token_hash text;
begin
  if auth.uid() is null then
    return;
  end if;

  normalized_token := btrim(coalesce(target_fcm_token, ''));
  normalized_device_id := btrim(coalesce(target_device_id, ''));

  if normalized_token <> '' then
    computed_token_hash := encode(digest(normalized_token, 'sha256'), 'hex');
  end if;

  update public.app_push_tokens
     set enabled = false,
         remember_login_enabled = false,
         revoked_at = timezone('utc', now()),
         last_seen_at = timezone('utc', now())
   where user_id = auth.uid()
     and (
       (computed_token_hash is not null and token_hash = computed_token_hash)
       or (normalized_device_id <> '' and device_id = normalized_device_id)
       or (computed_token_hash is null and normalized_device_id = '')
     );
end;
$$;

revoke all on function public.revoke_push_token(text, text) from public;
grant execute on function public.revoke_push_token(text, text) to authenticated;

create or replace function public.push_is_business_day(target_date date)
returns boolean
language sql
stable
as $$
  select extract(isodow from target_date) between 1 and 5
    and to_char(target_date, 'MM-DD') not in (
      '01-01',
      '03-19',
      '03-25',
      '04-21',
      '05-01',
      '09-07',
      '10-12',
      '11-02',
      '11-15',
      '11-20',
      '12-25'
    );
$$;

create or replace function public.push_business_days_between(
  start_date date,
  end_date date
)
returns integer
language sql
stable
as $$
  select count(*)::integer
  from generate_series(start_date, end_date, interval '1 day') as day(value)
  where end_date >= start_date
    and public.push_is_business_day(day.value::date);
$$;

create or replace function public.push_remaining_business_days(
  month_start date,
  reference_date date
)
returns integer
language plpgsql
stable
as $$
declare
  normalized_month_start date := date_trunc('month', month_start)::date;
  month_end date := (date_trunc('month', month_start)::date + interval '1 month - 1 day')::date;
  total_days integer;
  elapsed_days integer;
  include_reference integer;
  remaining_days integer;
begin
  total_days := public.push_business_days_between(normalized_month_start, month_end);

  if date_trunc('month', reference_date)::date > normalized_month_start then
    return total_days;
  end if;

  if date_trunc('month', reference_date)::date < normalized_month_start
     or reference_date > month_end then
    return 0;
  end if;

  elapsed_days := public.push_business_days_between(normalized_month_start, least(reference_date, month_end));
  include_reference := case when public.push_is_business_day(reference_date) then 1 else 0 end;
  remaining_days := total_days - elapsed_days + include_reference;

  if remaining_days < 0 then
    return 0;
  end if;

  if remaining_days > total_days then
    return total_days;
  end if;

  return remaining_days;
end;
$$;

create or replace function public.get_push_performance_metrics(
  target_profile_slug text,
  target_owner_code text,
  target_reference_date date default (timezone('America/Sao_Paulo', now()))::date
)
returns table (
  metric_key text,
  period_key text,
  period_start date,
  period_end date,
  actual_value numeric,
  target_value numeric,
  progress_pct numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_profile text := lower(btrim(coalesce(target_profile_slug, '')));
  normalized_owner text := btrim(coalesce(target_owner_code, ''));
  reference_date date := coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date);
  month_start date := date_trunc('month', coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date))::date;
  month_end date := (date_trunc('month', coalesce(target_reference_date, (timezone('America/Sao_Paulo', now()))::date)) + interval '1 month - 1 day')::date;
  financial_source text;
  secondary_source text;
  remaining_days integer;
begin
  if normalized_profile not in ('vendedor', 'supervisor', 'coordenador')
     or normalized_owner = '' then
    return;
  end if;

  financial_source := case
    when normalized_profile in ('supervisor', 'coordenador') then 'faturamento'
    else 'venda'
  end;
  secondary_source := case
    when normalized_profile = 'coordenador' then 'faturamento'
    else 'venda'
  end;
  remaining_days := public.push_remaining_business_days(month_start, reference_date);

  return query
  with target_row as (
    select
      coalesce(max(t.meta_fin), 0)::numeric as target_fin,
      max(t.meta_pos)::numeric as target_pos,
      max(t.meta_sku)::numeric as target_sku
    from public.app_performance_targets t
    where t.profile_slug = normalized_profile
      and t.owner_code = normalized_owner
      and t.month_start = month_start
      and t.codfornec = '1'
  ),
  sales_month as (
    select
      coalesce(round(sum(s.venda), 2), 0)::numeric as amount,
      coalesce(count(distinct s.codcli), 0)::numeric as pos
    from public.app_sales_daily_snapshots s
    where s.sales_date between month_start and reference_date
      and (
        case
          when normalized_profile = 'vendedor' then s.codusur = normalized_owner
          when normalized_profile = 'supervisor' then s.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then s.codgerente = normalized_owner
        end
      )
  ),
  sales_day as (
    select
      coalesce(round(sum(s.venda), 2), 0)::numeric as amount,
      coalesce(count(distinct s.codcli), 0)::numeric as pos
    from public.app_sales_daily_snapshots s
    where s.sales_date = reference_date
      and (
        case
          when normalized_profile = 'vendedor' then s.codusur = normalized_owner
          when normalized_profile = 'supervisor' then s.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then s.codgerente = normalized_owner
        end
      )
  ),
  financial_month as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date between month_start and reference_date
      and (
        case
          when normalized_profile = 'vendedor' then f.codusur = normalized_owner
          when normalized_profile = 'supervisor' then f.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then f.codgerente = normalized_owner
        end
      )
  ),
  financial_day as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'F'
      and f.snapshot_date = reference_date
      and (
        case
          when normalized_profile = 'vendedor' then f.codusur = normalized_owner
          when normalized_profile = 'supervisor' then f.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then f.codgerente = normalized_owner
        end
      )
  ),
  returns_month as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'D'
      and f.snapshot_date between month_start and reference_date
      and (
        case
          when normalized_profile = 'vendedor' then f.codusur = normalized_owner
          when normalized_profile = 'supervisor' then f.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then f.codgerente = normalized_owner
        end
      )
  ),
  returns_day as (
    select
      coalesce(round(sum(f.faturamento), 2), 0)::numeric as amount,
      coalesce(count(distinct f.codcli), 0)::numeric as pos
    from public.app_financial_snapshots f
    where f.snapshot_type = 'D'
      and f.snapshot_date = reference_date
      and (
        case
          when normalized_profile = 'vendedor' then f.codusur = normalized_owner
          when normalized_profile = 'supervisor' then f.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then f.codgerente = normalized_owner
        end
      )
  ),
  sku_month as (
    select coalesce(max(s.sku_count), 0)::numeric as value
    from public.app_performance_sku_monthly s
    where s.profile_slug = normalized_profile
      and s.owner_code = normalized_owner
      and s.month_start = month_start
      and s.codfornec = '1'
      and s.metric_source = secondary_source
  ),
  sku_day as (
    select coalesce(count(distinct nullif(soi.codprod, '')), 0)::numeric as value
    from public.app_sales_order_items soi
    where soi.sales_date = reference_date
      and (
        case
          when normalized_profile = 'vendedor' then soi.codusur = normalized_owner
          when normalized_profile = 'supervisor' then soi.codsupervisor = normalized_owner
          when normalized_profile = 'coordenador' then soi.codgerente = normalized_owner
        end
      )
  ),
  computed as (
    select
      tr.target_fin,
      tr.target_pos,
      tr.target_sku,
      case
        when financial_source = 'faturamento' then fm.amount
        else sm.amount
      end + rm.amount as financial_month_actual,
      case
        when financial_source = 'faturamento' then fd.amount
        else sd.amount
      end + rd.amount as financial_day_actual,
      case
        when secondary_source = 'faturamento' then fm.pos
        else sm.pos
      end as pos_month_actual,
      greatest(
        (case when secondary_source = 'faturamento' then fd.pos else sd.pos end) - rd.pos,
        0
      ) as pos_day_actual,
      skm.value as sku_month_actual,
      skd.value as sku_day_actual
    from target_row tr
    cross join sales_month sm
    cross join sales_day sd
    cross join financial_month fm
    cross join financial_day fd
    cross join returns_month rm
    cross join returns_day rd
    cross join sku_month skm
    cross join sku_day skd
  ),
  metric_rows as (
    select
      'financial'::text as metric_key,
      'monthly'::text as period_key,
      month_start as period_start,
      month_end as period_end,
      financial_month_actual as actual_value,
      target_fin as target_value
    from computed
    where target_fin > 0

    union all

    select
      'financial',
      'daily',
      reference_date,
      reference_date,
      financial_day_actual,
      case
        when target_fin <= 0 or remaining_days <= 0 then null::numeric
        when target_fin - financial_month_actual <= 0 then 0::numeric
        else (target_fin - financial_month_actual) / remaining_days
      end
    from computed
    where target_fin > 0

    union all

    select
      case when coalesce(target_sku, 0) > 0 then 'sku' else 'positivation' end,
      'monthly',
      month_start,
      month_end,
      case when coalesce(target_sku, 0) > 0 then sku_month_actual else pos_month_actual end,
      case when coalesce(target_sku, 0) > 0 then target_sku else target_pos end
    from computed
    where coalesce(target_sku, 0) > 0 or coalesce(target_pos, 0) > 0

    union all

    select
      case when coalesce(target_sku, 0) > 0 then 'sku' else 'positivation' end,
      'daily',
      reference_date,
      reference_date,
      case when coalesce(target_sku, 0) > 0 then sku_day_actual else pos_day_actual end,
      case
        when remaining_days <= 0 then null::numeric
        when coalesce(target_sku, 0) > 0 and target_sku - sku_month_actual > 0
          then (target_sku - sku_month_actual) / remaining_days
        when coalesce(target_sku, 0) > 0 then 0::numeric
        when coalesce(target_pos, 0) > 0 and target_pos - pos_month_actual > 0
          then (target_pos - pos_month_actual) / remaining_days
        when coalesce(target_pos, 0) > 0 then 0::numeric
        else null::numeric
      end
    from computed
    where coalesce(target_sku, 0) > 0 or coalesce(target_pos, 0) > 0
  )
  select
    mr.metric_key,
    mr.period_key,
    mr.period_start,
    mr.period_end,
    coalesce(mr.actual_value, 0)::numeric,
    mr.target_value::numeric,
    case
      when coalesce(mr.target_value, 0) > 0
        then round((coalesce(mr.actual_value, 0) / mr.target_value) * 100, 2)
      else null::numeric
    end as progress_pct
  from metric_rows mr
  where coalesce(mr.target_value, 0) > 0;
end;
$$;

revoke all on function public.get_push_performance_metrics(text, text, date)
  from public;
grant execute on function public.get_push_performance_metrics(text, text, date)
  to service_role;

create or replace function public.queue_push_notification_event(
  target_recipient_user_id uuid,
  target_recipient_profile_slug text,
  target_recipient_user_code text,
  target_event_type text,
  target_metric_key text,
  target_period_key text,
  target_period_start date,
  target_period_end date,
  target_threshold_percent integer,
  target_source_key text,
  target_title text,
  target_body text,
  target_data jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_push_notification_events (
    recipient_user_id,
    recipient_profile_slug,
    recipient_user_code,
    event_type,
    metric_key,
    period_key,
    period_start,
    period_end,
    threshold_percent,
    source_key,
    title,
    body,
    data
  )
  values (
    target_recipient_user_id,
    target_recipient_profile_slug,
    target_recipient_user_code,
    target_event_type,
    target_metric_key,
    target_period_key,
    target_period_start,
    target_period_end,
    target_threshold_percent,
    target_source_key,
    target_title,
    target_body,
    coalesce(target_data, '{}'::jsonb)
  )
  on conflict (source_key) do nothing;

  return found;
end;
$$;

revoke all on function public.queue_push_notification_event(
  uuid,
  text,
  text,
  text,
  text,
  text,
  date,
  date,
  integer,
  text,
  text,
  text,
  jsonb
) from public;
grant execute on function public.queue_push_notification_event(
  uuid,
  text,
  text,
  text,
  text,
  text,
  date,
  date,
  integer,
  text,
  text,
  text,
  jsonb
) to service_role;

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

      if metric_row.progress_pct is not null then
        foreach threshold_value in array threshold_values loop
          if (
            (previous_state.id is null and force_initial_notifications)
            or (
              previous_state.id is not null
              and coalesce(previous_state.last_progress_pct, 0) < threshold_value
            )
          ) and metric_row.progress_pct >= threshold_value then
            metric_label := case metric_row.metric_key
              when 'financial' then 'meta financeira'
              when 'sku' then 'meta de SKU'
              else 'meta de positivacao'
            end;

            if metric_row.period_key = 'monthly' then
              title_text := 'Meta mensal avancando!';
              body_text := format(
                'Parabens! Voce atingiu %s%% da %s mensal. Continue nesse ritmo!',
                threshold_value,
                metric_label
              );
            else
              title_text := 'Meta diaria avancando!';
              body_text := format(
                'Boa! Voce atingiu %s%% da %s de hoje. Continue buscando o proximo marco!',
                threshold_value,
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
              threshold_value
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
              threshold_value,
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
                'thresholdPercent', threshold_value,
                'periodStart', metric_row.period_start,
                'periodEnd', metric_row.period_end
              )
            ) then
              queued_count := queued_count + 1;
            end if;
          end if;
        end loop;
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

create or replace function public.handle_push_relevant_sync_applied()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'applied'
     and (tg_op = 'INSERT' or old.status is distinct from new.status)
     and new.job_name in (
       'oracle_sales_sync',
       'oracle_billing_sync',
       'oracle_returns_financial_sync',
       'oracle_return_items_sync'
     ) then
    perform public.evaluate_push_notifications(
      new.window_end,
      coalesce(new.started_at, timezone('utc', now()) - interval '6 hours'),
      false
    );
  end if;

  return new;
end;
$$;

drop trigger if exists evaluate_push_notifications_after_sync
  on public.etl_sync_runs;
create trigger evaluate_push_notifications_after_sync
after insert or update of status on public.etl_sync_runs
for each row
execute function public.handle_push_relevant_sync_applied();
