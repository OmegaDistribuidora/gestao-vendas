create or replace function public.get_home_positive_customers(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile text;
  viewer_code text;
  start_date date := date(window_start at time zone 'America/Sao_Paulo');
  end_date date := date(window_end at time zone 'America/Sao_Paulo');
  month_start date;
  result jsonb;
begin
  select coalesce(p.slug, 'sem_perfil'), u.code
    into viewer_profile, viewer_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if viewer_profile is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  month_start := date_trunc('month', start_date)::date;

  with visible_month_sales as (
    select s.codcli, s.sales_date, s.venda
    from public.app_sales_daily_snapshots s
    where s.sales_date between month_start and end_date
      and case
        when viewer_profile = 'vendedor' then s.codusur = viewer_code
        when viewer_profile = 'supervisor' then s.codsupervisor = viewer_code
        when viewer_profile = 'coordenador' then s.codgerente = viewer_code
        else true
      end
  ), first_purchase_in_month as (
    select codcli, min(sales_date) as first_purchase_date
    from visible_month_sales
    group by codcli
  ), visible_sales as (
    select codcli, sum(venda) as total_amount
    from visible_month_sales
    where sales_date between start_date and end_date
    group by codcli
  ), resolved as (
    select
      v.codcli,
      coalesce(
        nullif(btrim(c.cliente), ''),
        nullif(btrim(c.fantasia), ''),
        v.codcli
      ) as client_name,
      round(v.total_amount, 2) as total_amount,
      f.first_purchase_date between start_date and end_date as is_new_in_month
    from visible_sales v
    join first_purchase_in_month f on f.codcli = v.codcli
    left join public.app_customers c on c.codcli = v.codcli
  )
  select jsonb_build_object(
    'total_clients', count(*),
    'total_new_customers', count(*) filter (where is_new_in_month),
    'total_amount', coalesce(round(sum(total_amount), 2), 0),
    'items', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'client_code', codcli,
          'client_name', client_name,
          'total_amount', total_amount,
          'is_new_in_month', is_new_in_month
        )
        order by is_new_in_month desc, total_amount desc, client_name, codcli
      ),
      '[]'::jsonb
    )
  )
  into result
  from resolved;

  return coalesce(
    result,
    jsonb_build_object(
      'total_clients', 0,
      'total_new_customers', 0,
      'total_amount', 0,
      'items', '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.get_home_positive_customers(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.get_home_positive_customers(timestamptz, timestamptz)
  to authenticated;
