create table if not exists public.app_financial_snapshots (
  id uuid primary key default gen_random_uuid(),
  snapshot_type text not null check (snapshot_type in ('F', 'D')),
  snapshot_date date not null,
  numped text not null,
  codcli text not null,
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  faturamento numeric(18, 2) not null default 0,
  volume numeric(18, 4) not null default 0,
  custo numeric(18, 2) not null default 0,
  lucro numeric(18, 2) not null default 0,
  mix numeric(18, 2) not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (snapshot_type, snapshot_date, numped, codcli, codusur, codfornec)
);

create index if not exists idx_app_financial_snapshots_type_date_user
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codusur);

create index if not exists idx_app_financial_snapshots_type_date_supervisor
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codsupervisor);

create index if not exists idx_app_financial_snapshots_type_date_manager
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codgerente);

create index if not exists idx_app_financial_snapshots_type_date_supplier
  on public.app_financial_snapshots (snapshot_type, snapshot_date, codfornec);

drop trigger if exists set_app_financial_snapshots_updated_at on public.app_financial_snapshots;
create trigger set_app_financial_snapshots_updated_at
before update on public.app_financial_snapshots
for each row
execute function public.set_updated_at();

alter table public.app_financial_snapshots enable row level security;

grant select, insert, update, delete on public.app_financial_snapshots to authenticated, service_role;

drop policy if exists "financial_snapshots_admin_manage" on public.app_financial_snapshots;
create policy "financial_snapshots_admin_manage"
on public.app_financial_snapshots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create table if not exists public.app_suppliers (
  codfornec text primary key,
  supplier_name text not null,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_app_suppliers_updated_at on public.app_suppliers;
create trigger set_app_suppliers_updated_at
before update on public.app_suppliers
for each row
execute function public.set_updated_at();

alter table public.app_suppliers enable row level security;

grant select, insert, update, delete on public.app_suppliers to authenticated, service_role;

drop policy if exists "suppliers_admin_manage" on public.app_suppliers;
create policy "suppliers_admin_manage"
on public.app_suppliers
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_home_kpis(timestamptz, timestamptz);
drop function if exists public.get_home_kpis(timestamptz, timestamptz, text);

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

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select max(updated_at)
    into last_financial_updated_at
  from public.app_financial_snapshots;

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
    'last_sales_updated_at', last_sales_updated_at,
    'last_financial_updated_at', last_financial_updated_at
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz, text) to authenticated;

drop function if exists public.get_supplier_analysis(timestamptz, timestamptz, text);

create or replace function public.get_supplier_analysis(
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
  payload jsonb;
  last_updated_at timestamptz;
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

  if normalized_metric_source = 'venda' then
    select max(updated_at) into last_updated_at from public.app_sales_daily_snapshots;

    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
          select
            s.codfornec,
            coalesce(sp.supplier_name, s.codfornec) as supplier_name,
            round(sum(s.venda), 2) as gross_amount,
            round(sum(s.volume), 4) as gross_volume,
            count(distinct s.numped) as gross_orders,
            count(distinct s.codcli) as gross_positivation
          from public.app_sales_daily_snapshots s
          left join public.app_suppliers sp on sp.codfornec = s.codfornec
          where s.sales_date between start_date and end_date
            and (
              case
                when current_profile_slug = 'vendedor' then s.codusur = current_user_code
                when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
                when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
                else true
              end
            )
          group by s.codfornec, coalesce(sp.supplier_name, s.codfornec)
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  else
    select max(updated_at) into last_updated_at from public.app_financial_snapshots;

    select jsonb_build_object(
      'metric_source', normalized_metric_source,
      'last_updated_at', last_updated_at,
      'suppliers',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'code', bucket.codfornec,
            'supplier_name', bucket.supplier_name,
            'gross_amount', bucket.gross_amount,
            'gross_volume', bucket.gross_volume,
            'gross_orders', bucket.gross_orders,
            'gross_positivation', bucket.gross_positivation
          )
          order by bucket.gross_amount desc, bucket.supplier_name
        )
        from (
          select
            f.codfornec,
            coalesce(sp.supplier_name, f.codfornec) as supplier_name,
            round(sum(f.faturamento), 2) as gross_amount,
            round(sum(f.volume), 4) as gross_volume,
            count(distinct f.numped) as gross_orders,
            count(distinct f.codcli) as gross_positivation
          from public.app_financial_snapshots f
          left join public.app_suppliers sp on sp.codfornec = f.codfornec
          where f.snapshot_type = 'F'
            and f.snapshot_date between start_date and end_date
            and (
              case
                when current_profile_slug = 'vendedor' then f.codusur = current_user_code
                when current_profile_slug = 'supervisor' then f.codsupervisor = current_user_code
                when current_profile_slug = 'coordenador' then f.codgerente = current_user_code
                else true
              end
            )
          group by f.codfornec, coalesce(sp.supplier_name, f.codfornec)
        ) bucket
      ), '[]'::jsonb)
    ) into payload;
  end if;

  return coalesce(payload, jsonb_build_object(
    'metric_source', normalized_metric_source,
    'last_updated_at', last_updated_at,
    'suppliers', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_supplier_analysis(timestamptz, timestamptz, text) to authenticated;
