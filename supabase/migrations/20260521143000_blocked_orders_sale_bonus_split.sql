alter table public.app_blocked_orders
  add column if not exists tipo_venda integer not null default 0;

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
    'sales_blocked_amount', coalesce((select round(sum(f.valor_total_pedido), 2) from filtered f where f.tipo_venda = 1), 0),
    'sales_blocked_orders', coalesce((select count(*) from filtered f where f.tipo_venda = 1), 0),
    'bonus_blocked_amount', coalesce((select round(sum(f.valor_total_pedido), 2) from filtered f where f.tipo_venda = 5), 0),
    'bonus_blocked_orders', coalesce((select count(*) from filtered f where f.tipo_venda = 5), 0),
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
          'tipo_venda', f.tipo_venda,
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
    'sales_blocked_amount', 0,
    'sales_blocked_orders', 0,
    'bonus_blocked_amount', 0,
    'bonus_blocked_orders', 0,
    'orders', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.get_blocked_orders_overview() to authenticated;
