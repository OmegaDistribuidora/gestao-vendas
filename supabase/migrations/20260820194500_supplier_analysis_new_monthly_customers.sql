alter function public.get_supplier_analysis(timestamptz, timestamptz, text)
  rename to get_supplier_analysis_effective_balances;

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
  start_date date := date(window_start at time zone 'America/Sao_Paulo');
  end_date date := date(window_end at time zone 'America/Sao_Paulo');
  month_start date;
  normalized_metric_source text := lower(trim(coalesce(metric_source, 'venda')));
  payload jsonb;
  enriched_suppliers jsonb;
  overall_new_positivation integer := 0;
begin
  payload := public.get_supplier_analysis_effective_balances(
    window_start,
    window_end,
    metric_source
  );

  -- Clientes novos fazem sentido somente para vendas dentro de um unico mes.
  if normalized_metric_source <> 'venda'
     or start_date is null
     or end_date is null
     or date_trunc('month', start_date) <> date_trunc('month', end_date) then
    return payload;
  end if;

  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  month_start := date_trunc('month', start_date)::date;

  with visible_month_sales as (
    select
      s.codfornec,
      s.codcli,
      s.sales_date
    from public.app_sales_daily_snapshots s
    where s.sales_date between month_start and end_date
      and case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        else true
      end
  ),
  supplier_first_purchase as (
    select codfornec, codcli, min(sales_date) as first_purchase_date
    from visible_month_sales
    group by codfornec, codcli
  ),
  overall_first_purchase as (
    select codcli, min(sales_date) as first_purchase_date
    from visible_month_sales
    group by codcli
  ),
  period_gross_orders as (
    select
      s.codfornec,
      s.numped,
      s.codcli,
      s.codusur,
      sum(s.venda)::numeric as gross_amount
    from public.app_sales_daily_snapshots s
    where s.sales_date between start_date and end_date
      and case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        else true
      end
    group by s.codfornec, s.numped, s.codcli, s.codusur
  ),
  period_order_balances as (
    select
      g.codfornec,
      g.codcli,
      g.gross_amount + coalesce(sum(d.faturamento), 0)::numeric as net_amount
    from period_gross_orders g
    left join public.app_financial_snapshots d
      on d.snapshot_type = 'D'
     and d.numped = g.numped
     and d.codcli = g.codcli
     and d.codusur = g.codusur
     and d.codfornec = g.codfornec
    group by g.codfornec, g.numped, g.codcli, g.codusur, g.gross_amount
  ),
  supplier_client_balances as (
    select codfornec, codcli, sum(net_amount) as net_amount
    from period_order_balances
    group by codfornec, codcli
  ),
  overall_client_balances as (
    select codcli, sum(net_amount) as net_amount
    from period_order_balances
    group by codcli
  ),
  supplier_new_counts as (
    select
      b.codfornec,
      count(*)::integer as new_positivation
    from supplier_client_balances b
    join supplier_first_purchase f
      on f.codfornec = b.codfornec
     and f.codcli = b.codcli
    where b.net_amount > 0.01
      and f.first_purchase_date between start_date and end_date
    group by b.codfornec
  ),
  overall_new_count as (
    select count(*)::integer as new_positivation
    from overall_client_balances b
    join overall_first_purchase f on f.codcli = b.codcli
    where b.net_amount > 0.01
      and f.first_purchase_date between start_date and end_date
  ),
  enriched as (
    select coalesce(
      jsonb_agg(
        supplier.value || jsonb_build_object(
          'new_positivation', coalesce(n.new_positivation, 0)
        )
        order by supplier.ordinality
      ),
      '[]'::jsonb
    ) as suppliers
    from jsonb_array_elements(coalesce(payload -> 'suppliers', '[]'::jsonb))
      with ordinality as supplier(value, ordinality)
    left join supplier_new_counts n
      on n.codfornec = supplier.value ->> 'code'
  )
  select
    enriched.suppliers,
    overall_new_count.new_positivation
  into enriched_suppliers, overall_new_positivation
  from enriched
  cross join overall_new_count;

  return payload || jsonb_build_object(
    'overall', case
      when payload -> 'overall' is null
        or payload -> 'overall' = 'null'::jsonb then null
      else (payload -> 'overall') || jsonb_build_object(
        'new_positivation', coalesce(overall_new_positivation, 0)
      )
    end,
    'suppliers', coalesce(enriched_suppliers, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_supplier_analysis(timestamptz, timestamptz, text)
  from public, anon;
grant execute on function public.get_supplier_analysis(timestamptz, timestamptz, text)
  to authenticated;

comment on function public.get_supplier_analysis(timestamptz, timestamptz, text) is
  'Analise por fornecedor com saldos efetivos e clientes novos no mes para periodos de venda contidos em um unico mes.';
