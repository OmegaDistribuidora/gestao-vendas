create table if not exists public.app_customers (
  codcli text primary key,
  cliente text not null default '',
  cod_cliente text not null default '',
  fantasia text not null default '',
  cod_fantasia text not null default '',
  end_compl text not null default '',
  bairro text not null default '',
  cep text not null default '',
  codatv text not null default '',
  codcidade text not null default '',
  codrede text not null default '',
  codpraca text not null default '',
  uf text not null default '',
  limcred numeric(18, 2) not null default 0,
  codusur1 text not null default '',
  codusur2 text not null default '',
  codibge text not null default '',
  status text not null default '',
  motivo_bloq text not null default '',
  dtultcomp date,
  dtbloq date,
  cnpj text not null default '',
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_customer_seller_bases (
  codcli text not null references public.app_customers (codcli) on delete cascade,
  codusur text not null,
  status_cliente text not null default '',
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (codcli, codusur)
);

create index if not exists idx_app_customer_seller_bases_seller
  on public.app_customer_seller_bases (codusur, status_cliente);

create index if not exists idx_app_customers_status
  on public.app_customers (status);

drop trigger if exists set_app_customers_updated_at on public.app_customers;
create trigger set_app_customers_updated_at
before update on public.app_customers
for each row
execute function public.set_updated_at();

drop trigger if exists set_app_customer_seller_bases_updated_at on public.app_customer_seller_bases;
create trigger set_app_customer_seller_bases_updated_at
before update on public.app_customer_seller_bases
for each row
execute function public.set_updated_at();

alter table public.app_customers enable row level security;
alter table public.app_customer_seller_bases enable row level security;

grant select, insert, update, delete on public.app_customers to authenticated, service_role;
grant select, insert, update, delete on public.app_customer_seller_bases to authenticated, service_role;

drop policy if exists "customers_admin_manage" on public.app_customers;
create policy "customers_admin_manage"
on public.app_customers
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "customer_seller_bases_admin_manage" on public.app_customer_seller_bases;
create policy "customer_seller_bases_admin_manage"
on public.app_customer_seller_bases
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create unlogged table if not exists public.etl_stg_customers (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  codcli text not null,
  cliente text not null default '',
  cod_cliente text not null default '',
  fantasia text not null default '',
  cod_fantasia text not null default '',
  end_compl text not null default '',
  bairro text not null default '',
  cep text not null default '',
  codatv text not null default '',
  codcidade text not null default '',
  codrede text not null default '',
  codpraca text not null default '',
  uf text not null default '',
  limcred numeric(18, 2) not null default 0,
  codusur1 text not null default '',
  codusur2 text not null default '',
  codibge text not null default '',
  status text not null default '',
  motivo_bloq text not null default '',
  dtultcomp date,
  dtbloq date,
  cnpj text not null default '',
  imported_at timestamptz not null,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, codcli)
);

create unlogged table if not exists public.etl_stg_customer_seller_bases (
  run_id uuid not null references public.etl_sync_runs (id) on delete cascade,
  codcli text not null,
  codusur text not null,
  status_cliente text not null default '',
  imported_at timestamptz not null,
  staged_at timestamptz not null default timezone('utc', now()),
  primary key (run_id, codcli, codusur)
);

alter table public.etl_stg_customers enable row level security;
alter table public.etl_stg_customer_seller_bases enable row level security;

grant select, insert, delete on public.etl_stg_customers to authenticated, service_role;
grant select, insert, delete on public.etl_stg_customer_seller_bases to authenticated, service_role;

drop policy if exists "etl_stg_customers_admin_manage" on public.etl_stg_customers;
create policy "etl_stg_customers_admin_manage"
on public.etl_stg_customers
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "etl_stg_customer_seller_bases_admin_manage" on public.etl_stg_customer_seller_bases;
create policy "etl_stg_customer_seller_bases_admin_manage"
on public.etl_stg_customer_seller_bases
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.apply_customer_base_sync(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.etl_sync_runs%rowtype;
  v_customer_rows_staged integer := 0;
  v_base_rows_staged integer := 0;
  v_customer_rows_inserted integer := 0;
  v_customer_rows_updated integer := 0;
  v_base_rows_inserted integer := 0;
  v_base_rows_updated integer := 0;
  v_base_rows_deleted integer := 0;
begin
  select *
    into v_run
  from public.etl_sync_runs
  where id = p_run_id;

  if not found then
    raise exception 'Sync run not found.';
  end if;

  select count(*)
    into v_customer_rows_staged
  from public.etl_stg_customers
  where run_id = p_run_id;

  select count(*)
    into v_base_rows_staged
  from public.etl_stg_customer_seller_bases
  where run_id = p_run_id;

  select count(*)
    into v_customer_rows_inserted
  from public.etl_stg_customers s
  left join public.app_customers t on t.codcli = s.codcli
  where s.run_id = p_run_id
    and t.codcli is null;

  select count(*)
    into v_customer_rows_updated
  from public.etl_stg_customers s
  join public.app_customers t on t.codcli = s.codcli
  where s.run_id = p_run_id
    and (
      t.cliente is distinct from s.cliente
      or t.cod_cliente is distinct from s.cod_cliente
      or t.fantasia is distinct from s.fantasia
      or t.cod_fantasia is distinct from s.cod_fantasia
      or t.end_compl is distinct from s.end_compl
      or t.bairro is distinct from s.bairro
      or t.cep is distinct from s.cep
      or t.codatv is distinct from s.codatv
      or t.codcidade is distinct from s.codcidade
      or t.codrede is distinct from s.codrede
      or t.codpraca is distinct from s.codpraca
      or t.uf is distinct from s.uf
      or t.limcred is distinct from s.limcred
      or t.codusur1 is distinct from s.codusur1
      or t.codusur2 is distinct from s.codusur2
      or t.codibge is distinct from s.codibge
      or t.status is distinct from s.status
      or t.motivo_bloq is distinct from s.motivo_bloq
      or t.dtultcomp is distinct from s.dtultcomp
      or t.dtbloq is distinct from s.dtbloq
      or t.cnpj is distinct from s.cnpj
    );

  insert into public.app_customers (
    codcli,
    cliente,
    cod_cliente,
    fantasia,
    cod_fantasia,
    end_compl,
    bairro,
    cep,
    codatv,
    codcidade,
    codrede,
    codpraca,
    uf,
    limcred,
    codusur1,
    codusur2,
    codibge,
    status,
    motivo_bloq,
    dtultcomp,
    dtbloq,
    cnpj,
    imported_at
  )
  select
    s.codcli,
    s.cliente,
    s.cod_cliente,
    s.fantasia,
    s.cod_fantasia,
    s.end_compl,
    s.bairro,
    s.cep,
    s.codatv,
    s.codcidade,
    s.codrede,
    s.codpraca,
    s.uf,
    s.limcred,
    s.codusur1,
    s.codusur2,
    s.codibge,
    s.status,
    s.motivo_bloq,
    s.dtultcomp,
    s.dtbloq,
    s.cnpj,
    s.imported_at
  from public.etl_stg_customers s
  where s.run_id = p_run_id
  on conflict (codcli)
  do update
    set cliente = excluded.cliente,
        cod_cliente = excluded.cod_cliente,
        fantasia = excluded.fantasia,
        cod_fantasia = excluded.cod_fantasia,
        end_compl = excluded.end_compl,
        bairro = excluded.bairro,
        cep = excluded.cep,
        codatv = excluded.codatv,
        codcidade = excluded.codcidade,
        codrede = excluded.codrede,
        codpraca = excluded.codpraca,
        uf = excluded.uf,
        limcred = excluded.limcred,
        codusur1 = excluded.codusur1,
        codusur2 = excluded.codusur2,
        codibge = excluded.codibge,
        status = excluded.status,
        motivo_bloq = excluded.motivo_bloq,
        dtultcomp = excluded.dtultcomp,
        dtbloq = excluded.dtbloq,
        cnpj = excluded.cnpj,
        imported_at = excluded.imported_at
  where public.app_customers.cliente is distinct from excluded.cliente
     or public.app_customers.cod_cliente is distinct from excluded.cod_cliente
     or public.app_customers.fantasia is distinct from excluded.fantasia
     or public.app_customers.cod_fantasia is distinct from excluded.cod_fantasia
     or public.app_customers.end_compl is distinct from excluded.end_compl
     or public.app_customers.bairro is distinct from excluded.bairro
     or public.app_customers.cep is distinct from excluded.cep
     or public.app_customers.codatv is distinct from excluded.codatv
     or public.app_customers.codcidade is distinct from excluded.codcidade
     or public.app_customers.codrede is distinct from excluded.codrede
     or public.app_customers.codpraca is distinct from excluded.codpraca
     or public.app_customers.uf is distinct from excluded.uf
     or public.app_customers.limcred is distinct from excluded.limcred
     or public.app_customers.codusur1 is distinct from excluded.codusur1
     or public.app_customers.codusur2 is distinct from excluded.codusur2
     or public.app_customers.codibge is distinct from excluded.codibge
     or public.app_customers.status is distinct from excluded.status
     or public.app_customers.motivo_bloq is distinct from excluded.motivo_bloq
     or public.app_customers.dtultcomp is distinct from excluded.dtultcomp
     or public.app_customers.dtbloq is distinct from excluded.dtbloq
     or public.app_customers.cnpj is distinct from excluded.cnpj;

  select count(*)
    into v_base_rows_inserted
  from public.etl_stg_customer_seller_bases s
  left join public.app_customer_seller_bases t
    on t.codcli = s.codcli
   and t.codusur = s.codusur
  where s.run_id = p_run_id
    and t.codcli is null;

  select count(*)
    into v_base_rows_updated
  from public.etl_stg_customer_seller_bases s
  join public.app_customer_seller_bases t
    on t.codcli = s.codcli
   and t.codusur = s.codusur
  where s.run_id = p_run_id
    and t.status_cliente is distinct from s.status_cliente;

  select count(*)
    into v_base_rows_deleted
  from public.app_customer_seller_bases t
  where not exists (
    select 1
    from public.etl_stg_customer_seller_bases s
    where s.run_id = p_run_id
      and s.codcli = t.codcli
      and s.codusur = t.codusur
  );

  delete from public.app_customer_seller_bases t
  where not exists (
    select 1
    from public.etl_stg_customer_seller_bases s
    where s.run_id = p_run_id
      and s.codcli = t.codcli
      and s.codusur = t.codusur
  );

  insert into public.app_customer_seller_bases (
    codcli,
    codusur,
    status_cliente,
    imported_at
  )
  select
    s.codcli,
    s.codusur,
    s.status_cliente,
    s.imported_at
  from public.etl_stg_customer_seller_bases s
  join public.app_customers c on c.codcli = s.codcli
  where s.run_id = p_run_id
  on conflict (codcli, codusur)
  do update
    set status_cliente = excluded.status_cliente,
        imported_at = excluded.imported_at
  where public.app_customer_seller_bases.status_cliente is distinct from excluded.status_cliente;

  delete from public.etl_stg_customer_seller_bases
  where run_id = p_run_id;

  delete from public.etl_stg_customers
  where run_id = p_run_id;

  update public.etl_sync_runs
     set status = 'applied',
         rows_staged = v_customer_rows_staged + v_base_rows_staged,
         rows_inserted = v_customer_rows_inserted + v_base_rows_inserted,
         rows_updated = v_customer_rows_updated + v_base_rows_updated,
         rows_deleted = v_base_rows_deleted,
         finished_at = timezone('utc', now()),
         error_message = null,
         notes = jsonb_build_object(
           'customer_rows_staged', v_customer_rows_staged,
           'base_rows_staged', v_base_rows_staged,
           'customer_rows_inserted', v_customer_rows_inserted,
           'customer_rows_updated', v_customer_rows_updated,
           'base_rows_inserted', v_base_rows_inserted,
           'base_rows_updated', v_base_rows_updated,
           'base_rows_deleted', v_base_rows_deleted
         )
   where id = p_run_id;

  return jsonb_build_object(
    'customer_rows_staged', v_customer_rows_staged,
    'base_rows_staged', v_base_rows_staged,
    'customer_rows_inserted', v_customer_rows_inserted,
    'customer_rows_updated', v_customer_rows_updated,
    'base_rows_inserted', v_base_rows_inserted,
    'base_rows_updated', v_base_rows_updated,
    'base_rows_deleted', v_base_rows_deleted
  );
end;
$$;

grant execute on function public.apply_customer_base_sync(uuid) to authenticated, service_role;

create or replace function public.get_customers_without_purchase(
  window_start timestamptz,
  window_end timestamptz,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_profile_slug text;
  requested_owner_code text;
  effective_profile_slug text;
  effective_owner_code text;
  aggregate_all_mode boolean := false;
  start_date date;
  end_date date;
  anchor_month date;
  prev_month_1 date;
  prev_month_2 date;
  prev_month_3 date;
  last_updated_at timestamptz;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  anchor_month := date_trunc('month', start_date)::date;
  prev_month_1 := (anchor_month - interval '1 month')::date;
  prev_month_2 := (anchor_month - interval '2 months')::date;
  prev_month_3 := (anchor_month - interval '3 months')::date;

  requested_profile_slug := nullif(lower(trim(coalesce(target_scope_profile_slug, ''))), '');
  requested_owner_code := nullif(trim(coalesce(target_scope_owner_code, '')), '');

  if viewer_profile_slug = 'vendedor' then
    effective_profile_slug := 'vendedor';
    effective_owner_code := viewer_user_code;
  elsif viewer_profile_slug = 'supervisor' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'supervisor';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'vendedor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'vendedor'
        and u.code = requested_owner_code
        and coalesce(u.supervisor_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'vendedor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo invalido para supervisor.';
    end if;
  elsif viewer_profile_slug = 'coordenador' then
    if requested_profile_slug is null or requested_owner_code is null then
      effective_profile_slug := 'coordenador';
      effective_owner_code := viewer_user_code;
    elsif requested_profile_slug = 'supervisor' and exists (
      select 1
      from public.app_users seller
      join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
      where seller.is_active = true
        and seller_profile.slug = 'vendedor'
        and coalesce(seller.supervisor_code, '') = requested_owner_code
        and coalesce(seller.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'supervisor';
      effective_owner_code := requested_owner_code;
    elsif requested_profile_slug = 'vendedor' and exists (
      select 1
      from public.app_users u
      join public.app_profiles p on p.id = u.profile_id
      where u.is_active = true
        and p.slug = 'vendedor'
        and u.code = requested_owner_code
        and coalesce(u.coordinator_code, '') = viewer_user_code
    ) then
      effective_profile_slug := 'vendedor';
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo invalido para coordenador.';
    end if;
  elsif viewer_profile_slug in ('admin', 'diretoria', 'outros') then
    if requested_profile_slug is null or requested_owner_code is null then
      aggregate_all_mode := true;
      effective_profile_slug := viewer_profile_slug;
      effective_owner_code := null;
    elsif requested_profile_slug in ('coordenador', 'supervisor', 'vendedor')
      and exists (
        select 1
        from public.app_users u
        join public.app_profiles p on p.id = u.profile_id
        where u.is_active = true
          and p.slug = requested_profile_slug
          and u.code = requested_owner_code
      ) then
      effective_profile_slug := requested_profile_slug;
      effective_owner_code := requested_owner_code;
    else
      raise exception 'Escopo invalido para o perfil atual.';
    end if;
  else
    aggregate_all_mode := true;
    effective_profile_slug := viewer_profile_slug;
    effective_owner_code := null;
  end if;

  last_updated_at := public.get_latest_sync_finished_at(
    array['oracle_customer_base_sync']
  );

  with available_scope_rows as (
    select distinct
      p.slug as profile_slug,
      u.code as owner_code,
      coalesce(nullif(btrim(u.display_name), ''), u.code) as display_name,
      trim(
        case
          when btrim(coalesce(u.code, '')) <> '' and btrim(coalesce(u.display_name, '')) <> ''
            then u.code || ' - ' || u.display_name
          when btrim(coalesce(u.display_name, '')) <> ''
            then u.display_name
          else u.code
        end
      ) as label
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.is_active = true
      and viewer_profile_slug = 'supervisor'
      and p.slug = 'vendedor'
      and coalesce(u.supervisor_code, '') = viewer_user_code

    union all

    select distinct
      'supervisor' as profile_slug,
      seller.supervisor_code as owner_code,
      coalesce(nullif(btrim(supervisor.display_name), ''), seller.supervisor_code) as display_name,
      trim(
        case
          when btrim(coalesce(seller.supervisor_code, '')) <> ''
            and btrim(coalesce(supervisor.display_name, '')) <> ''
            then seller.supervisor_code || ' - ' || supervisor.display_name
          when btrim(coalesce(supervisor.display_name, '')) <> ''
            then supervisor.display_name
          else seller.supervisor_code
        end
      ) as label
    from public.app_users seller
    join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
    left join public.app_users supervisor on supervisor.code = seller.supervisor_code
    where seller.is_active = true
      and viewer_profile_slug = 'coordenador'
      and seller_profile.slug = 'vendedor'
      and coalesce(seller.coordinator_code, '') = viewer_user_code
      and coalesce(seller.supervisor_code, '') <> ''

    union all

    select distinct
      'vendedor' as profile_slug,
      seller.code as owner_code,
      coalesce(nullif(btrim(seller.display_name), ''), seller.code) as display_name,
      trim(
        case
          when btrim(coalesce(seller.code, '')) <> ''
            and btrim(coalesce(seller.display_name, '')) <> ''
            then seller.code || ' - ' || seller.display_name
          when btrim(coalesce(seller.display_name, '')) <> ''
            then seller.display_name
          else seller.code
        end
      ) as label
    from public.app_users seller
    join public.app_profiles seller_profile on seller_profile.id = seller.profile_id
    where seller.is_active = true
      and viewer_profile_slug = 'coordenador'
      and seller_profile.slug = 'vendedor'
      and coalesce(seller.coordinator_code, '') = viewer_user_code

    union all

    select distinct
      p.slug as profile_slug,
      u.code as owner_code,
      coalesce(nullif(btrim(u.display_name), ''), u.code) as display_name,
      trim(
        case
          when btrim(coalesce(u.code, '')) <> '' and btrim(coalesce(u.display_name, '')) <> ''
            then u.code || ' - ' || u.display_name
          when btrim(coalesce(u.display_name, '')) <> ''
            then u.display_name
          else u.code
        end
      ) as label
    from public.app_users u
    join public.app_profiles p on p.id = u.profile_id
    where u.is_active = true
      and viewer_profile_slug in ('admin', 'diretoria', 'outros')
      and p.slug in ('coordenador', 'supervisor', 'vendedor')
  ),
  base_rows as (
    select
      b.codcli,
      b.codusur,
      b.status_cliente,
      c.cliente,
      c.cod_cliente,
      c.fantasia,
      c.cod_fantasia,
      c.end_compl,
      c.bairro,
      c.cep,
      c.codatv,
      c.codcidade,
      c.codrede,
      c.codpraca,
      c.uf,
      c.limcred,
      c.codibge,
      c.status,
      c.motivo_bloq,
      c.dtultcomp,
      c.dtbloq,
      c.cnpj,
      coalesce(nullif(seller.display_name, ''), b.codusur) as seller_name,
      coalesce(seller.supervisor_code, '') as codsupervisor,
      coalesce(seller.coordinator_code, '') as codgerente,
      coalesce(nullif(supervisor.display_name, ''), seller.supervisor_code, '') as supervisor_name,
      coalesce(nullif(coordinator.display_name, ''), seller.coordinator_code, '') as coordinator_name
    from public.app_customer_seller_bases b
    join public.app_customers c on c.codcli = b.codcli
    left join public.app_users seller on seller.code = b.codusur
    left join public.app_profiles seller_profile
      on seller_profile.id = seller.profile_id
     and seller_profile.slug = 'vendedor'
    left join public.app_users supervisor
      on supervisor.code = seller.supervisor_code
    left join public.app_users coordinator
      on coordinator.code = seller.coordinator_code
    where lower(b.status_cliente) = 'desbloqueado'
      and (
        aggregate_all_mode
        or (effective_profile_slug = 'vendedor' and b.codusur = effective_owner_code)
        or (effective_profile_slug = 'supervisor' and coalesce(seller.supervisor_code, '') = effective_owner_code)
        or (effective_profile_slug = 'coordenador' and coalesce(seller.coordinator_code, '') = effective_owner_code)
      )
      and not exists (
        select 1
        from public.app_sales_daily_snapshots s
        where s.codcli = b.codcli
          and s.codusur = b.codusur
          and s.sales_date between start_date and end_date
      )
  ),
  classified as (
    select
      br.*,
      exists (
        select 1 from public.app_sales_daily_snapshots s
        where s.codcli = br.codcli
          and s.codusur = br.codusur
          and s.sales_date >= prev_month_1
          and s.sales_date < anchor_month
      ) as bought_prev_1,
      exists (
        select 1 from public.app_sales_daily_snapshots s
        where s.codcli = br.codcli
          and s.codusur = br.codusur
          and s.sales_date >= prev_month_2
          and s.sales_date < prev_month_1
      ) as bought_prev_2,
      exists (
        select 1 from public.app_sales_daily_snapshots s
        where s.codcli = br.codcli
          and s.codusur = br.codusur
          and s.sales_date >= prev_month_3
          and s.sales_date < prev_month_2
      ) as bought_prev_3,
      last_order.last_purchase_date,
      last_order.last_purchase_amount,
      recent_orders.orders as recent_orders
    from base_rows br
    left join lateral (
      select
        o.sales_date as last_purchase_date,
        o.total_amount as last_purchase_amount
      from (
        select
          s.sales_date,
          s.numped,
          round(sum(s.venda), 2) as total_amount
        from public.app_sales_daily_snapshots s
        where s.codcli = br.codcli
          and s.codusur = br.codusur
          and s.sales_date < start_date
        group by s.sales_date, s.numped
        order by s.sales_date desc, s.numped desc
        limit 1
      ) o
    ) last_order on true
    left join lateral (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'numped', item.numped,
          'sales_date', item.sales_date,
          'total_amount', item.total_amount,
          'total_volume', item.total_volume,
          'item_count', item.item_count
        )
        order by item.sales_date desc, item.numped desc
      ), '[]'::jsonb) as orders
      from (
        select
          s.numped,
          s.sales_date,
          round(sum(s.venda), 2) as total_amount,
          round(sum(s.volume), 4) as total_volume,
          count(*) as item_count
        from public.app_sales_daily_snapshots s
        where s.codcli = br.codcli
          and s.codusur = br.codusur
          and s.sales_date < start_date
        group by s.numped, s.sales_date
        order by s.sales_date desc, s.numped desc
        limit 3
      ) item
    ) recent_orders on true
  ),
  enriched as (
    select
      c.*,
      case
        when c.bought_prev_1 and c.bought_prev_2 and c.bought_prev_3 then 'Regular'
        when c.bought_prev_1 and c.bought_prev_2 then 'Semi-Regular'
        else 'Normal'
      end as regularity_label,
      case
        when c.last_purchase_date is null then 9999
        else greatest(start_date - c.last_purchase_date, 0)
      end as days_without_purchase
    from classified c
  )
  select jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'profile_slug', effective_profile_slug,
    'selected_scope_profile_slug', case when aggregate_all_mode then null else effective_profile_slug end,
    'selected_scope_owner_code', case when aggregate_all_mode then null else effective_owner_code end,
    'period_start', start_date,
    'period_end', end_date,
    'anchor_month', anchor_month,
    'last_updated_at', last_updated_at,
    'available_scopes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile_slug', a.profile_slug,
          'owner_code', a.owner_code,
          'display_name', a.display_name,
          'label', a.label
        )
        order by
          case a.profile_slug
            when 'coordenador' then 1
            when 'supervisor' then 2
            when 'vendedor' then 3
            else 4
          end,
          a.label
      )
      from available_scope_rows a
    ), '[]'::jsonb),
    'total_clients', coalesce((select count(*) from enriched), 0),
    'regular_clients', coalesce((select count(*) from enriched where regularity_label = 'Regular'), 0),
    'semi_regular_clients', coalesce((select count(*) from enriched where regularity_label = 'Semi-Regular'), 0),
    'normal_clients', coalesce((select count(*) from enriched where regularity_label = 'Normal'), 0),
    'customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'codcli', e.codcli,
          'client_name', e.cliente,
          'cod_cliente', e.cod_cliente,
          'fantasia', e.fantasia,
          'cod_fantasia', e.cod_fantasia,
          'address', e.end_compl,
          'district', e.bairro,
          'cep', e.cep,
          'activity_code', e.codatv,
          'city_code', e.codcidade,
          'network_code', e.codrede,
          'market_code', e.codpraca,
          'uf', e.uf,
          'credit_limit', e.limcred,
          'ibge_code', e.codibge,
          'status', e.status,
          'block_reason', e.motivo_bloq,
          'blocked_at', e.dtbloq,
          'cnpj', e.cnpj,
          'codusur', e.codusur,
          'seller_name', e.seller_name,
          'codsupervisor', e.codsupervisor,
          'supervisor_name', e.supervisor_name,
          'codgerente', e.codgerente,
          'coordinator_name', e.coordinator_name,
          'last_purchase_date', e.last_purchase_date,
          'last_purchase_amount', coalesce(e.last_purchase_amount, 0),
          'days_without_purchase', e.days_without_purchase,
          'regularity_label', e.regularity_label,
          'recent_orders', coalesce(e.recent_orders, '[]'::jsonb)
        )
        order by e.days_without_purchase desc, e.cliente, e.codcli, e.codusur
      )
      from enriched e
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_customers_without_purchase(timestamptz, timestamptz, text, text) to authenticated;
