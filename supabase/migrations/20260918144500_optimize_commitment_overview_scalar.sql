-- Segunda estrategia de otimizacao do Compromisso.
--
-- O lote global aumenta demais o conjunto intermediario no banco. Esta
-- funcao usa os indices por hierarquia e calcula, em uma unica chamada por
-- item, tanto o periodo completo quanto o periodo encerrado. Ela continua
-- sem montar a lista por fornecedor, que nao e consumida pelo modulo.

create or replace function public.get_commitment_actual_pair(
  target_profile_slug text,
  target_owner_code text,
  target_start_date date,
  target_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized_profile_slug text := lower(btrim(coalesce(target_profile_slug, '')));
  normalized_owner_code text := btrim(coalesce(target_owner_code, ''));
  month_start date;
  closed_end_date date;
  last_updated_at timestamptz;
  result jsonb;
begin
  if normalized_profile_slug not in ('supervisor', 'coordenador')
     or normalized_owner_code = '' then
    return jsonb_build_object(
      'financial_actual', 0,
      'positivation_actual', 0,
      'financial_closed_actual', 0,
      'positivation_closed_actual', 0,
      'last_updated_at', null
    );
  end if;

  if target_start_date is null
     or target_end_date is null
     or target_end_date < target_start_date then
    raise exception 'Periodo do compromisso invalido.';
  end if;
  if date_trunc('month', target_start_date)
     <> date_trunc('month', target_end_date) then
    raise exception 'O periodo do compromisso deve estar dentro do mesmo mes.';
  end if;

  if not exists (
    select 1
    from public.app_users app_user
    join public.app_profiles profile on profile.id = app_user.profile_id
    where app_user.is_active
      and app_user.auth_user_id is not null
      and profile.slug = normalized_profile_slug
      and app_user.code = normalized_owner_code
  ) then
    return jsonb_build_object(
      'financial_actual', 0,
      'positivation_actual', 0,
      'financial_closed_actual', 0,
      'positivation_closed_actual', 0,
      'last_updated_at', null
    );
  end if;

  month_start := date_trunc('month', target_start_date)::date;
  closed_end_date := least(
    target_end_date,
    timezone('America/Sao_Paulo', now())::date - 1
  );
  last_updated_at := public.get_consistent_sync_finished_at(
    array['oracle_sales_sync', 'oracle_returns_financial_sync']
  );

  with visible_month_sales as materialized (
    select
      sale.codfornec,
      sale.numped,
      sale.codcli,
      sale.codusur,
      sale.sales_date,
      sale.venda::numeric as gross_amount
    from public.app_sales_daily_snapshots sale
    where sale.sales_date between month_start and target_end_date
      and case normalized_profile_slug
        when 'supervisor' then sale.codsupervisor = normalized_owner_code
        else sale.codgerente = normalized_owner_code
      end
  ),
  window_sales as materialized (
    select
      'current'::text as window_key,
      sale.*
    from visible_month_sales sale

    union all

    select
      'closed'::text as window_key,
      sale.*
    from visible_month_sales sale
    where closed_end_date >= target_start_date
      and sale.sales_date <= closed_end_date
  ),
  first_purchases as (
    select
      window_key,
      codcli,
      min(sales_date) as first_purchase_date
    from window_sales
    group by window_key, codcli
  ),
  period_gross_orders as materialized (
    select
      window_key,
      codfornec,
      numped,
      codcli,
      codusur,
      sum(gross_amount)::numeric as gross_amount
    from window_sales
    where sales_date >= target_start_date
    group by window_key, codfornec, numped, codcli, codusur
  ),
  order_balances as materialized (
    select
      gross.window_key,
      gross.codfornec,
      gross.numped,
      gross.codcli,
      gross.codusur,
      gross.gross_amount,
      coalesce(sum(return_row.faturamento), 0)::numeric as return_amount,
      gross.gross_amount
        + coalesce(sum(return_row.faturamento), 0)::numeric as net_amount
    from period_gross_orders gross
    left join public.app_financial_snapshots return_row
      on return_row.snapshot_type = 'D'
     and return_row.numped = gross.numped
     and return_row.codcli = gross.codcli
     and return_row.codusur = gross.codusur
     and return_row.codfornec = gross.codfornec
    group by
      gross.window_key,
      gross.codfornec,
      gross.numped,
      gross.codcli,
      gross.codusur,
      gross.gross_amount
  ),
  financial_metrics as (
    select
      window_key,
      round(coalesce(sum(gross_amount), 0), 2)
        + round(coalesce(sum(return_amount), 0), 2) as financial_actual
    from order_balances
    group by window_key
  ),
  client_balances as (
    select window_key, codcli, sum(net_amount) as net_amount
    from order_balances
    group by window_key, codcli
  ),
  positivation_metrics as (
    select
      balance.window_key,
      count(*)::integer as positivation_actual
    from client_balances balance
    join first_purchases first_purchase
      on first_purchase.window_key = balance.window_key
     and first_purchase.codcli = balance.codcli
    where balance.net_amount > 0.01
      and first_purchase.first_purchase_date
        between target_start_date
        and case balance.window_key
          when 'closed' then closed_end_date
          else target_end_date
        end
    group by balance.window_key
  )
  select jsonb_build_object(
    'financial_actual',
      coalesce((
        select metric.financial_actual
        from financial_metrics metric
        where metric.window_key = 'current'
      ), 0),
    'positivation_actual',
      coalesce((
        select metric.positivation_actual
        from positivation_metrics metric
        where metric.window_key = 'current'
      ), 0),
    'financial_closed_actual',
      coalesce((
        select metric.financial_actual
        from financial_metrics metric
        where metric.window_key = 'closed'
      ), 0),
    'positivation_closed_actual',
      coalesce((
        select metric.positivation_actual
        from positivation_metrics metric
        where metric.window_key = 'closed'
      ), 0),
    'last_updated_at', last_updated_at
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_commitment_actual_pair(
  text, text, date, date
) from public, anon, authenticated;

comment on function public.get_commitment_actual_pair(
  text, text, date, date
) is 'Realizados atual e encerrado do Compromisso calculados juntos, sem detalhamento por fornecedor.';

-- Recria a base paralela a partir da funcao vigente. Assim, toda evolucao de
-- escopo (inclusive Gerencia) permanece identica e apenas o calculo interno e
-- trocado.
do $$
declare
  original_definition text;
  optimized_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_commitment_overview_base(date,date,text,text)'::regprocedure
  );

  optimized_definition := regexp_replace(
    original_definition,
    'CREATE OR REPLACE FUNCTION public\.get_commitment_overview_base\(',
    'CREATE OR REPLACE FUNCTION public.get_commitment_overview_fast_base(',
    'i'
  );

  optimized_definition := regexp_replace(
    optimized_definition,
    'actual_payload := public\.get_commitment_actual\([[:space:]]*target_record\.profile_slug,[[:space:]]*target_record\.owner_code,[[:space:]]*selected_start_date,[[:space:]]*selected_end_date[[:space:]]*\);',
    E'actual_payload := public.get_commitment_actual_pair(\n      target_record.profile_slug,\n      target_record.owner_code,\n      selected_start_date,\n      selected_end_date\n    );',
    'i'
  );

  optimized_definition := regexp_replace(
    optimized_definition,
    '''last_updated_at'', actual_payload -> ''last_updated_at''',
    E'''last_updated_at'', actual_payload -> ''last_updated_at'',\n      ''financial_closed_actual'', actual_payload -> ''financial_closed_actual'',\n      ''positivation_closed_actual'', actual_payload -> ''positivation_closed_actual''',
    'i'
  );

  if optimized_definition = original_definition
     or position('get_commitment_overview_fast_base' in optimized_definition) = 0
     or position('public.get_commitment_actual_pair(' in optimized_definition) = 0
     or position('financial_closed_actual' in optimized_definition) = 0
     or position('public.get_commitment_actual(' in optimized_definition) > 0 then
    raise exception 'Nao foi possivel criar a base escalar otimizada.';
  end if;

  execute optimized_definition;
end;
$$;

revoke all on function public.get_commitment_overview_fast_base(
  date, date, text, text
) from public, anon, authenticated;

create or replace function public.get_commitment_overview_optimized(
  target_start_date date default null,
  target_end_date date default null,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  enriched_items jsonb := '[]'::jsonb;
  item_record record;
  selected_start_date date;
  selected_end_date date;
  corrected_financial_target numeric;
  corrected_positivation_target numeric;
  supervisor_target_count integer;
begin
  payload := public.get_commitment_overview_fast_base(
    target_start_date,
    target_end_date,
    target_scope_profile_slug,
    target_scope_owner_code
  );

  selected_start_date := (payload ->> 'selected_start_date')::date;
  selected_end_date := (payload ->> 'selected_end_date')::date;
  if selected_start_date is null or selected_end_date is null then
    return payload;
  end if;

  for item_record in
    select item.value
    from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) item
  loop
    if item_record.value ->> 'profile_slug' = 'coordenador' then
      select
        count(*)::integer,
        coalesce(sum(commitment.financial_target), 0),
        coalesce(sum(commitment.positivation_target), 0)
      into
        supervisor_target_count,
        corrected_financial_target,
        corrected_positivation_target
      from public.app_commitments commitment
      where commitment.profile_slug = 'supervisor'
        and commitment.start_date = selected_start_date
        and commitment.end_date = selected_end_date
        and exists (
          select 1
          from public.app_users supervisor
          join public.app_profiles supervisor_profile
            on supervisor_profile.id = supervisor.profile_id
          where supervisor.is_active
            and supervisor_profile.slug = 'supervisor'
            and supervisor.code = commitment.owner_code
            and supervisor.coordinator_code = item_record.value ->> 'owner_code'
        );

      if supervisor_target_count > 0 then
        item_record.value := item_record.value || jsonb_build_object(
          'financial_target', corrected_financial_target,
          'positivation_target', corrected_positivation_target
        );
      end if;
    end if;

    enriched_items := enriched_items || jsonb_build_array(item_record.value);
  end loop;

  return payload || jsonb_build_object('items', enriched_items);
end;
$$;

revoke all on function public.get_commitment_overview_optimized(
  date, date, text, text
) from public, anon, authenticated;

comment on function public.get_commitment_overview_optimized(
  date, date, text, text
) is 'Contrato vigente do Compromisso com calculo escalar enxuto por item.';
