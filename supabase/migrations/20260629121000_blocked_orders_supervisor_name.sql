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
  enriched_items as (
    select
      fi.*,
      coalesce(
        nullif(btrim((
          select supervisor.display_name
          from public.app_users supervisor
          where supervisor.code = fi.codsupervisor
          order by supervisor.is_active desc, supervisor.updated_at desc
          limit 1
        )), ''),
        fi.codsupervisor
      ) as supervisor_name
    from filtered_items fi
  ),
  order_summaries as (
    select
      ei.numped,
      max(ei.cod_posicao) as cod_posicao,
      max(ei.posicao_pedido) as posicao_pedido,
      max(ei.data_pedido) as data_pedido,
      max(ei.codcli) as codcli,
      max(ei.client_name) as client_name,
      max(ei.codusur) as codusur,
      max(ei.seller_name) as seller_name,
      max(ei.codsupervisor) as codsupervisor,
      max(ei.supervisor_name) as supervisor_name,
      max(ei.codgerente) as codgerente,
      max(ei.tipo_venda) as tipo_venda,
      max(ei.motivo_bloqueio) as motivo_bloqueio,
      round(sum(ei.valor_total_pedido), 2) as valor_total_pedido,
      round(sum(ei.quantity_item), 4) as total_quantity,
      round(sum(ei.volume_item), 4) as total_volume,
      count(*)::integer as item_count
    from enriched_items ei
    group by ei.numped
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
          'supervisor_name', os.supervisor_name,
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

grant execute on function public.get_blocked_orders_overview()
  to authenticated;
