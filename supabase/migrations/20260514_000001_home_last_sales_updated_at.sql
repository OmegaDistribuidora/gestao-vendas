drop function if exists public.get_home_kpis();

create or replace function public.get_home_kpis(
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
  last_sales_updated_at timestamptz;
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

  if start_date is null or end_date is null then
    raise exception 'Periodo invalido.';
  end if;

  if end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select max(updated_at)
    into last_sales_updated_at
  from public.app_sales_daily_snapshots;

  select jsonb_build_object(
    'total_venda', coalesce(round(sum(s.venda), 2), 0),
    'total_volume', coalesce(round(sum(s.volume), 2), 0),
    'total_pedidos', coalesce(count(distinct s.numped), 0),
    'total_positivacao', coalesce(count(distinct s.codcli), 0),
    'last_sales_updated_at', last_sales_updated_at
  )
    into payload
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

  return coalesce(
    payload,
    jsonb_build_object(
      'total_venda', 0,
      'total_volume', 0,
      'total_pedidos', 0,
      'total_positivacao', 0,
      'last_sales_updated_at', last_sales_updated_at
    )
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz) to authenticated;
