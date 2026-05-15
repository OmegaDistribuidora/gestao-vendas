create table if not exists public.app_return_order_items (
  id uuid primary key default gen_random_uuid(),
  return_date date not null,
  numped text not null,
  codcli text not null,
  client_name text not null default '',
  codusur text not null,
  codsupervisor text not null,
  codgerente text not null,
  codfornec text not null,
  return_reason text not null default '',
  codprod text not null,
  product_name text not null default '',
  item_value numeric(18, 2) not null default 0,
  quantity numeric(18, 4) not null default 0,
  volume numeric(18, 4) not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (return_date, numped, codprod, codfornec, codusur, return_reason)
);

create index if not exists idx_app_return_items_date_user
  on public.app_return_order_items (return_date, codusur);

create index if not exists idx_app_return_items_date_supervisor
  on public.app_return_order_items (return_date, codsupervisor);

create index if not exists idx_app_return_items_date_manager
  on public.app_return_order_items (return_date, codgerente);

create index if not exists idx_app_return_items_order
  on public.app_return_order_items (return_date, numped);

drop trigger if exists set_app_return_order_items_updated_at on public.app_return_order_items;
create trigger set_app_return_order_items_updated_at
before update on public.app_return_order_items
for each row
execute function public.set_updated_at();

alter table public.app_return_order_items enable row level security;

grant select, insert, update, delete on public.app_return_order_items to authenticated, service_role;

drop policy if exists "return_items_admin_manage" on public.app_return_order_items;
create policy "return_items_admin_manage"
on public.app_return_order_items
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_return_analysis(timestamptz, timestamptz);

create or replace function public.get_return_analysis(
  window_start timestamptz,
  window_end timestamptz
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

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select max(updated_at)
    into last_updated_at
  from public.app_return_order_items;

  with filtered as (
    select *
    from public.app_return_order_items ri
    where ri.return_date between start_date and end_date
      and (
        case
          when current_profile_slug = 'vendedor' then ri.codusur = current_user_code
          when current_profile_slug = 'supervisor' then ri.codsupervisor = current_user_code
          when current_profile_slug = 'coordenador' then ri.codgerente = current_user_code
          else true
        end
      )
  ),
  orders as (
    select
      ri.return_date,
      ri.numped,
      ri.codcli,
      max(ri.client_name) as client_name,
      max(ri.return_reason) as return_reason,
      round(sum(ri.item_value), 2) as total_value,
      round(sum(ri.volume), 4) as total_volume,
      round(sum(ri.quantity), 4) as total_quantity,
      count(*) as item_count
    from filtered ri
    group by ri.return_date, ri.numped, ri.codcli
  )
  select jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', coalesce((select round(sum(item_value), 2) from filtered), 0),
    'total_clients', coalesce((select count(distinct codcli) from filtered), 0),
    'total_volume', coalesce((select round(sum(volume), 4) from filtered), 0),
    'total_orders', coalesce((select count(distinct numped) from filtered), 0),
    'orders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'return_date', o.return_date,
          'numped', o.numped,
          'codcli', o.codcli,
          'client_name', o.client_name,
          'return_reason', o.return_reason,
          'total_value', o.total_value,
          'total_volume', o.total_volume,
          'total_quantity', o.total_quantity,
          'item_count', o.item_count
        )
        order by o.return_date desc, o.total_value desc, o.numped desc
      )
      from orders o
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'last_updated_at', last_updated_at,
    'total_return_amount', 0,
    'total_clients', 0,
    'total_volume', 0,
    'total_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_return_analysis(timestamptz, timestamptz) to authenticated;

drop function if exists public.get_return_order_details(date, text);

create or replace function public.get_return_order_details(
  target_return_date date,
  target_order_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
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

  select jsonb_build_object(
    'items',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'codprod', ri.codprod,
          'product_name', ri.product_name,
          'item_value', ri.item_value,
          'quantity', ri.quantity,
          'volume', ri.volume,
          'return_reason', ri.return_reason
        )
        order by ri.product_name, ri.codprod
      )
      from public.app_return_order_items ri
      where ri.return_date = target_return_date
        and ri.numped = target_order_number
        and (
          case
            when current_profile_slug = 'vendedor' then ri.codusur = current_user_code
            when current_profile_slug = 'supervisor' then ri.codsupervisor = current_user_code
            when current_profile_slug = 'coordenador' then ri.codgerente = current_user_code
            else true
          end
        )
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object('items', '[]'::jsonb));
end;
$$;

grant execute on function public.get_return_order_details(date, text) to authenticated;
