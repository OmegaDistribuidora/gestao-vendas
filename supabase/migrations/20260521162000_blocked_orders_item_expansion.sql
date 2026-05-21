alter table public.app_blocked_orders
  add column if not exists codprod text not null default '',
  add column if not exists product_name text not null default '',
  add column if not exists quantity_item numeric(18, 4) not null default 0,
  add column if not exists volume_item numeric(18, 4) not null default 0;

alter table public.app_blocked_orders
  drop constraint if exists app_blocked_orders_numped_key;

create unique index if not exists uq_app_blocked_orders_order_product
  on public.app_blocked_orders (numped, codprod);

create index if not exists idx_app_blocked_orders_order_number
  on public.app_blocked_orders (numped);

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

  with filtered_items as (
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
  ),
  order_summaries as (
    select
      fi.numped,
      max(fi.cod_posicao) as cod_posicao,
      max(fi.posicao_pedido) as posicao_pedido,
      max(fi.data_pedido) as data_pedido,
      max(fi.codcli) as codcli,
      max(fi.client_name) as client_name,
      max(fi.codusur) as codusur,
      max(fi.seller_name) as seller_name,
      max(fi.codsupervisor) as codsupervisor,
      max(fi.codgerente) as codgerente,
      max(fi.tipo_venda) as tipo_venda,
      max(fi.motivo_bloqueio) as motivo_bloqueio,
      round(sum(fi.valor_total_pedido), 2) as valor_total_pedido,
      round(sum(fi.quantity_item), 4) as total_quantity,
      round(sum(fi.volume_item), 4) as total_volume,
      count(*)::integer as item_count
    from filtered_items fi
    group by fi.numped
  )
  select jsonb_build_object(
    'profile_slug', current_profile_slug,
    'last_updated_at', last_updated_at,
    'total_blocked_amount', coalesce((select round(sum(fi.valor_total_pedido), 2) from filtered_items fi), 0),
    'total_blocked_orders', coalesce((select count(*) from order_summaries), 0),
    'sales_blocked_amount', coalesce((select round(sum(os.valor_total_pedido), 2) from order_summaries os where os.tipo_venda = 1), 0),
    'sales_blocked_orders', coalesce((select count(*) from order_summaries os where os.tipo_venda = 1), 0),
    'bonus_blocked_amount', coalesce((select round(sum(os.valor_total_pedido), 2) from order_summaries os where os.tipo_venda = 5), 0),
    'bonus_blocked_orders', coalesce((select count(*) from order_summaries os where os.tipo_venda = 5), 0),
    'orders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'numped', os.numped,
          'cod_posicao', os.cod_posicao,
          'posicao_pedido', os.posicao_pedido,
          'data_pedido', os.data_pedido,
          'codcli', os.codcli,
          'client_name', os.client_name,
          'codusur', os.codusur,
          'seller_name', os.seller_name,
          'codsupervisor', os.codsupervisor,
          'codgerente', os.codgerente,
          'tipo_venda', os.tipo_venda,
          'motivo_bloqueio', os.motivo_bloqueio,
          'valor_total_pedido', os.valor_total_pedido,
          'total_quantity', os.total_quantity,
          'total_volume', os.total_volume,
          'item_count', os.item_count,
          'items', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'codprod', fi.codprod,
                'product_name', fi.product_name,
                'quantity', fi.quantity_item,
                'volume', fi.volume_item,
                'item_value', fi.valor_total_pedido
              )
              order by fi.codprod
            )
            from filtered_items fi
            where fi.numped = os.numped
          ), '[]'::jsonb)
        )
        order by os.data_pedido desc, os.numped desc
      )
      from order_summaries os
    ), '[]'::jsonb)
  )
  into payload;

  return coalesce(payload, jsonb_build_object(
    'profile_slug', current_profile_slug,
    'last_updated_at', last_updated_at,
    'total_blocked_amount', 0,
    'total_blocked_orders', 0,
    'sales_blocked_amount', 0,
    'sales_blocked_orders', 0,
    'bonus_blocked_amount', 0,
    'bonus_blocked_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_blocked_orders_overview() to authenticated;
