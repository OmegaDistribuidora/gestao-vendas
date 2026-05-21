create table if not exists public.app_blocked_orders (
  id uuid primary key default gen_random_uuid(),
  numped text not null unique,
  cod_posicao text not null default '',
  posicao_pedido text not null default '',
  data_pedido date not null,
  codcli text not null,
  client_name text not null default '',
  codusur text not null,
  seller_name text not null default '',
  codsupervisor text not null default '',
  codgerente text not null default '',
  motivo_bloqueio text not null default '',
  valor_total_pedido numeric(18, 2) not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_app_blocked_orders_date_user
  on public.app_blocked_orders (data_pedido desc, codusur);

create index if not exists idx_app_blocked_orders_date_supervisor
  on public.app_blocked_orders (data_pedido desc, codsupervisor);

create index if not exists idx_app_blocked_orders_date_manager
  on public.app_blocked_orders (data_pedido desc, codgerente);

create index if not exists idx_app_blocked_orders_client
  on public.app_blocked_orders (codcli, data_pedido desc);

drop trigger if exists set_app_blocked_orders_updated_at on public.app_blocked_orders;
create trigger set_app_blocked_orders_updated_at
before update on public.app_blocked_orders
for each row
execute function public.set_updated_at();

alter table public.app_blocked_orders enable row level security;

grant select, insert, update, delete on public.app_blocked_orders to authenticated, service_role;

drop policy if exists "blocked_orders_admin_manage" on public.app_blocked_orders;
create policy "blocked_orders_admin_manage"
on public.app_blocked_orders
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop function if exists public.get_blocked_orders_overview();

create or replace function public.get_blocked_orders_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
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

  select max(updated_at)
    into last_updated_at
  from public.app_blocked_orders;

  with filtered as (
    select *
    from public.app_blocked_orders bo
    where (
      case
        when current_profile_slug = 'vendedor' then bo.codusur = current_user_code
        when current_profile_slug = 'supervisor' then bo.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then bo.codgerente = current_user_code
        else true
      end
    )
  )
  select jsonb_build_object(
    'profile_slug', current_profile_slug,
    'last_updated_at', last_updated_at,
    'total_blocked_amount', coalesce((select round(sum(f.valor_total_pedido), 2) from filtered f), 0),
    'total_blocked_orders', coalesce((select count(*) from filtered), 0),
    'orders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'numped', f.numped,
          'cod_posicao', f.cod_posicao,
          'posicao_pedido', f.posicao_pedido,
          'data_pedido', f.data_pedido,
          'codcli', f.codcli,
          'client_name', f.client_name,
          'codusur', f.codusur,
          'seller_name', f.seller_name,
          'codsupervisor', f.codsupervisor,
          'codgerente', f.codgerente,
          'motivo_bloqueio', f.motivo_bloqueio,
          'valor_total_pedido', f.valor_total_pedido
        )
        order by f.data_pedido desc, f.numped desc
      )
      from filtered f
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'profile_slug', current_profile_slug,
    'last_updated_at', last_updated_at,
    'total_blocked_amount', 0,
    'total_blocked_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_blocked_orders_overview() to authenticated;
