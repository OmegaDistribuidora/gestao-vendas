-- The closed-month actual is fixed for a reference day (it only considers
-- dates through yesterday). Cache it once per scope/day so the push evaluator
-- does not repeat the same monthly joins every two minutes.

alter function public.get_home_closed_month_liquid_actuals(text, text, date)
  rename to compute_home_closed_month_liquid_actuals;

create table if not exists public.app_home_closed_liquid_actuals_cache (
  reference_date date not null,
  profile_slug text not null,
  owner_code text not null,
  actuals jsonb not null,
  computed_at timestamptz not null default timezone('utc', now()),
  primary key (reference_date, profile_slug, owner_code)
);

alter table public.app_home_closed_liquid_actuals_cache enable row level security;
revoke all on table public.app_home_closed_liquid_actuals_cache
  from public, anon, authenticated;
grant select, insert, update, delete
  on table public.app_home_closed_liquid_actuals_cache
  to service_role;

create or replace function public.get_home_closed_month_liquid_actuals(
  target_profile_slug text,
  target_owner_code text,
  target_reference_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_profile text := lower(btrim(coalesce(target_profile_slug, '')));
  normalized_owner text := btrim(coalesce(target_owner_code, ''));
  cache_profile text;
  cache_owner text;
  cached_actuals jsonb;
begin
  if normalized_profile in ('vendedor', 'supervisor', 'coordenador') then
    cache_profile := normalized_profile;
    cache_owner := normalized_owner;
  else
    -- Diretoria/Outros share the same company-wide scope.
    cache_profile := 'geral';
    cache_owner := 'geral';
  end if;

  select cache.actuals
    into cached_actuals
  from public.app_home_closed_liquid_actuals_cache cache
  where cache.reference_date = target_reference_date
    and cache.profile_slug = cache_profile
    and cache.owner_code = cache_owner;

  if cached_actuals is not null then
    return cached_actuals;
  end if;

  cached_actuals := public.compute_home_closed_month_liquid_actuals(
    cache_profile,
    cache_owner,
    target_reference_date
  );

  insert into public.app_home_closed_liquid_actuals_cache (
    reference_date,
    profile_slug,
    owner_code,
    actuals
  )
  values (
    target_reference_date,
    cache_profile,
    cache_owner,
    cached_actuals
  )
  on conflict (reference_date, profile_slug, owner_code)
  do update set
    actuals = excluded.actuals,
    computed_at = timezone('utc', now());

  return cached_actuals;
end;
$$;

revoke all on function public.compute_home_closed_month_liquid_actuals(text, text, date)
  from public, anon, authenticated;
grant execute on function public.compute_home_closed_month_liquid_actuals(text, text, date)
  to service_role;

revoke all on function public.get_home_closed_month_liquid_actuals(text, text, date)
  from public, anon, authenticated;
grant execute on function public.get_home_closed_month_liquid_actuals(text, text, date)
  to service_role;

alter function public.evaluate_push_notifications(date, timestamptz, boolean)
  set statement_timeout = '60s';
alter function public.evaluate_push_notifications_after_gold_sync(date)
  set statement_timeout = '60s';
alter function public.evaluate_push_return_notifications_all_profiles(date, timestamptz)
  set statement_timeout = '30s';

comment on table public.app_home_closed_liquid_actuals_cache is
  'Daily immutable cache for closed-through-yesterday liquid actuals used by Home targets and push notifications.';

comment on function public.get_home_closed_month_liquid_actuals(text, text, date) is
  'Returns cached closed-through-yesterday liquid actuals per profile scope and reference day.';
