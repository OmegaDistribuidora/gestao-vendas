create table if not exists public.app_performance_targets (
  id uuid primary key default gen_random_uuid(),
  profile_slug text not null check (profile_slug in ('vendedor', 'supervisor', 'coordenador')),
  owner_code text not null,
  codfornec text not null,
  month_start date not null,
  target_year integer not null check (target_year >= 2026),
  target_month integer not null check (target_month between 1 and 12),
  meta_fin numeric(18, 2) not null default 0,
  meta_pos integer,
  meta_sku integer,
  source_sheet text not null,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (profile_slug, owner_code, codfornec, month_start)
);

create index if not exists idx_app_performance_targets_owner_month
  on public.app_performance_targets (profile_slug, owner_code, month_start desc);

create index if not exists idx_app_performance_targets_supplier
  on public.app_performance_targets (codfornec);

drop trigger if exists set_app_performance_targets_updated_at on public.app_performance_targets;
create trigger set_app_performance_targets_updated_at
before update on public.app_performance_targets
for each row
execute function public.set_updated_at();

alter table public.app_performance_targets enable row level security;

grant select, insert, update, delete on public.app_performance_targets to authenticated, service_role;

drop policy if exists "performance_targets_admin_manage" on public.app_performance_targets;
create policy "performance_targets_admin_manage"
on public.app_performance_targets
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create table if not exists public.app_performance_sku_monthly (
  id uuid primary key default gen_random_uuid(),
  profile_slug text not null check (profile_slug in ('vendedor', 'supervisor', 'coordenador')),
  owner_code text not null,
  codfornec text not null,
  month_start date not null,
  target_year integer not null check (target_year >= 2026),
  target_month integer not null check (target_month between 1 and 12),
  sku_count integer not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (profile_slug, owner_code, codfornec, month_start)
);

create index if not exists idx_app_performance_sku_monthly_owner_month
  on public.app_performance_sku_monthly (profile_slug, owner_code, month_start desc);

create index if not exists idx_app_performance_sku_monthly_supplier
  on public.app_performance_sku_monthly (codfornec);

drop trigger if exists set_app_performance_sku_monthly_updated_at on public.app_performance_sku_monthly;
create trigger set_app_performance_sku_monthly_updated_at
before update on public.app_performance_sku_monthly
for each row
execute function public.set_updated_at();

alter table public.app_performance_sku_monthly enable row level security;

grant select, insert, update, delete on public.app_performance_sku_monthly to authenticated, service_role;

drop policy if exists "performance_sku_monthly_admin_manage" on public.app_performance_sku_monthly;
create policy "performance_sku_monthly_admin_manage"
on public.app_performance_sku_monthly
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_performance_overview(date);

create or replace function public.get_performance_overview(
  target_month_start date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  resolved_month_start date;
  current_month_start date;
  last_targets_updated_at timestamptz;
  last_sales_updated_at timestamptz;
  last_sku_updated_at timestamptz;
  payload jsonb;
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

  current_month_start := date_trunc(
    'month',
    timezone('America/Sao_Paulo', now())
  )::date;

  select max(updated_at)
    into last_targets_updated_at
  from public.app_performance_targets t
  where t.profile_slug = current_profile_slug
    and t.owner_code = current_user_code;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_sku_updated_at
  from public.app_performance_sku_monthly s
  where s.profile_slug = current_profile_slug
    and s.owner_code = current_user_code;

  if current_profile_slug not in ('vendedor', 'supervisor', 'coordenador') then
    return jsonb_build_object(
      'supported', false,
      'profile_slug', current_profile_slug,
      'selected_month_start', target_month_start,
      'last_targets_updated_at', last_targets_updated_at,
      'last_sales_updated_at', last_sales_updated_at,
      'last_sku_updated_at', last_sku_updated_at,
      'available_months', '[]'::jsonb,
      'items', '[]'::jsonb
    );
  end if;

  if target_month_start is not null then
    resolved_month_start := date_trunc('month', target_month_start)::date;
  else
    select max(t.month_start)
      into resolved_month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start;
  end if;

  with available_months as (
    select distinct t.month_start
    from public.app_performance_targets t
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and t.month_start <= current_month_start
  ),
  targets as (
    select
      t.codfornec,
      case
        when t.codfornec = '1' then 'Geral'
        else coalesce(sp.supplier_name, t.codfornec)
      end as supplier_name,
      coalesce(t.meta_fin, 0)::numeric(18, 2) as target_fin,
      t.meta_pos,
      t.meta_sku
    from public.app_performance_targets t
    left join public.app_suppliers sp on sp.codfornec = t.codfornec
    where t.profile_slug = current_profile_slug
      and t.owner_code = current_user_code
      and resolved_month_start is not null
      and t.month_start = resolved_month_start
  ),
  sales_actuals as (
    select
      supplier_rows.codfornec,
      round(sum(supplier_rows.venda), 2) as actual_fin,
      count(distinct supplier_rows.codcli) as actual_pos
    from (
      select
        s.codfornec,
        s.venda,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )

      union all

      select
        '1' as codfornec,
        s.venda,
        s.codcli
      from public.app_sales_daily_snapshots s
      where resolved_month_start is not null
        and s.sales_date >= resolved_month_start
        and s.sales_date < (resolved_month_start + interval '1 month')
        and (
          case
            when current_profile_slug = 'vendedor' then s.codusur = current_user_code
            when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
            else false
          end
        )
    ) supplier_rows
    group by supplier_rows.codfornec
  ),
  sku_actuals as (
    select
      s.codfornec,
      s.sku_count
    from public.app_performance_sku_monthly s
    where s.profile_slug = current_profile_slug
      and s.owner_code = current_user_code
      and resolved_month_start is not null
      and s.month_start = resolved_month_start
  ),
  merged_items as (
    select
      t.codfornec,
      t.supplier_name,
      t.target_fin,
      coalesce(sa.actual_fin, 0)::numeric(18, 2) as actual_fin,
      case
        when t.target_fin > 0 then round((coalesce(sa.actual_fin, 0) / t.target_fin) * 100, 1)
        else null
      end as fin_progress_pct,
      t.meta_pos as target_pos,
      coalesce(sa.actual_pos, 0) as actual_pos,
      case
        when coalesce(t.meta_pos, 0) > 0
          then round((coalesce(sa.actual_pos, 0)::numeric / t.meta_pos) * 100, 1)
        else null
      end as pos_progress_pct,
      t.meta_sku as target_sku,
      coalesce(sk.sku_count, 0) as actual_sku,
      case
        when coalesce(t.meta_sku, 0) > 0
          then round((coalesce(sk.sku_count, 0)::numeric / t.meta_sku) * 100, 1)
        else null
      end as sku_progress_pct,
      case
        when coalesce(t.meta_sku, 0) > 0 then 'sku'
        when coalesce(t.meta_pos, 0) > 0 then 'positivacao'
        else null
      end as secondary_metric_type
    from targets t
    left join sales_actuals sa on sa.codfornec = t.codfornec
    left join sku_actuals sk on sk.codfornec = t.codfornec
  )
  select jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month_start', m.month_start,
          'label',
            case extract(month from m.month_start)::int
              when 1 then 'Jan'
              when 2 then 'Fev'
              when 3 then 'Mar'
              when 4 then 'Abr'
              when 5 then 'Mai'
              when 6 then 'Jun'
              when 7 then 'Jul'
              when 8 then 'Ago'
              when 9 then 'Set'
              when 10 then 'Out'
              when 11 then 'Nov'
              when 12 then 'Dez'
            end || '/' || extract(year from m.month_start)::int
        )
        order by m.month_start desc
      )
      from available_months m
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code', item.codfornec,
          'supplier_name', item.supplier_name,
          'target_fin', item.target_fin,
          'actual_fin', item.actual_fin,
          'fin_progress_pct', item.fin_progress_pct,
          'target_pos', item.target_pos,
          'actual_pos', item.actual_pos,
          'pos_progress_pct', item.pos_progress_pct,
          'target_sku', item.target_sku,
          'actual_sku', item.actual_sku,
          'sku_progress_pct', item.sku_progress_pct,
          'secondary_metric_type', item.secondary_metric_type
        )
        order by
          case when item.codfornec = '1' then 0 else 1 end,
          item.target_fin desc,
          item.supplier_name
      )
      from merged_items item
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'supported', true,
    'profile_slug', current_profile_slug,
    'selected_month_start', resolved_month_start,
    'last_targets_updated_at', last_targets_updated_at,
    'last_sales_updated_at', last_sales_updated_at,
    'last_sku_updated_at', last_sku_updated_at,
    'available_months', '[]'::jsonb,
    'items', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_performance_overview(date) to authenticated;
