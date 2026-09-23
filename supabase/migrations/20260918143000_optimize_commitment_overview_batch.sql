-- Calcula os realizados do modulo de Compromisso em lote.
--
-- A implementacao anterior chamava a analise completa por fornecedor uma vez
-- para cada item e repetia o processo para o periodo encerrado. Esta versao
-- preserva as mesmas fontes e regras, mas agrega todos os supervisores e
-- coordenadores em duas leituras: periodo completo e periodo encerrado.

create or replace function public.get_commitment_actuals_batch(
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
  month_start date;
  last_updated_at timestamptz;
  result jsonb;
begin
  if target_start_date is null
     or target_end_date is null
     or target_end_date < target_start_date then
    raise exception 'Periodo do compromisso invalido.';
  end if;

  if date_trunc('month', target_start_date)
     <> date_trunc('month', target_end_date) then
    raise exception 'O periodo do compromisso deve estar dentro do mesmo mes.';
  end if;

  month_start := date_trunc('month', target_start_date)::date;
  last_updated_at := public.get_consistent_sync_finished_at(
    array['oracle_sales_sync', 'oracle_returns_financial_sync']
  );

  with valid_scopes as materialized (
    select distinct
      profile.slug as profile_slug,
      app_user.code as owner_code
    from public.app_users app_user
    join public.app_profiles profile on profile.id = app_user.profile_id
    where app_user.is_active
      and app_user.auth_user_id is not null
      and profile.slug in ('supervisor', 'coordenador')
  ),
  month_scope_sales as materialized (
    select
      'supervisor'::text as profile_slug,
      sale.codsupervisor as owner_code,
      sale.codfornec,
      sale.numped,
      sale.codcli,
      sale.codusur,
      sale.sales_date,
      sale.venda::numeric as gross_amount
    from public.app_sales_daily_snapshots sale
    join valid_scopes scope
      on scope.profile_slug = 'supervisor'
     and scope.owner_code = sale.codsupervisor
    where sale.sales_date between month_start and target_end_date

    union all

    select
      'coordenador'::text as profile_slug,
      sale.codgerente as owner_code,
      sale.codfornec,
      sale.numped,
      sale.codcli,
      sale.codusur,
      sale.sales_date,
      sale.venda::numeric as gross_amount
    from public.app_sales_daily_snapshots sale
    join valid_scopes scope
      on scope.profile_slug = 'coordenador'
     and scope.owner_code = sale.codgerente
    where sale.sales_date between month_start and target_end_date
  ),
  first_purchases as (
    select
      profile_slug,
      owner_code,
      codcli,
      min(sales_date) as first_purchase_date
    from month_scope_sales
    group by profile_slug, owner_code, codcli
  ),
  period_gross_orders as materialized (
    select
      profile_slug,
      owner_code,
      codfornec,
      numped,
      codcli,
      codusur,
      sum(gross_amount)::numeric as gross_amount
    from month_scope_sales
    where sales_date between target_start_date and target_end_date
    group by
      profile_slug,
      owner_code,
      codfornec,
      numped,
      codcli,
      codusur
  ),
  order_balances as materialized (
    select
      gross.profile_slug,
      gross.owner_code,
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
      gross.profile_slug,
      gross.owner_code,
      gross.codfornec,
      gross.numped,
      gross.codcli,
      gross.codusur,
      gross.gross_amount
  ),
  financial_metrics as (
    select
      profile_slug,
      owner_code,
      round(coalesce(sum(gross_amount), 0), 2)
        + round(coalesce(sum(return_amount), 0), 2) as financial_actual
    from order_balances
    group by profile_slug, owner_code
  ),
  client_balances as (
    select
      profile_slug,
      owner_code,
      codcli,
      sum(net_amount) as net_amount
    from order_balances
    group by profile_slug, owner_code, codcli
  ),
  new_positivation_metrics as (
    select
      balance.profile_slug,
      balance.owner_code,
      count(*)::integer as positivation_actual
    from client_balances balance
    join first_purchases first_purchase
      on first_purchase.profile_slug = balance.profile_slug
     and first_purchase.owner_code = balance.owner_code
     and first_purchase.codcli = balance.codcli
    where balance.net_amount > 0.01
      and first_purchase.first_purchase_date
        between target_start_date and target_end_date
    group by balance.profile_slug, balance.owner_code
  )
  select coalesce(
    jsonb_object_agg(
      scope.profile_slug || '|' || scope.owner_code,
      jsonb_build_object(
        'financial_actual', coalesce(financial.financial_actual, 0),
        'positivation_actual', coalesce(positivation.positivation_actual, 0),
        'last_updated_at', last_updated_at
      )
    ),
    '{}'::jsonb
  )
  into result
  from valid_scopes scope
  left join financial_metrics financial
    on financial.profile_slug = scope.profile_slug
   and financial.owner_code = scope.owner_code
  left join new_positivation_metrics positivation
    on positivation.profile_slug = scope.profile_slug
   and positivation.owner_code = scope.owner_code;

  return result;
end;
$$;

revoke all on function public.get_commitment_actuals_batch(date, date)
  from public, anon, authenticated;

comment on function public.get_commitment_actuals_batch(date, date) is
  'Realizado financeiro e positivacao nova de supervisores e coordenadores calculados em lote.';

-- Clona a funcao-base vigente para preservar integralmente permissoes,
-- periodos, escopos e ordenacao, substituindo apenas o calculo N+1.
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
    'DECLARE[[:space:]]+',
    E'DECLARE\n  batch_actuals jsonb;\n  ',
    'i'
  );

  optimized_definition := regexp_replace(
    optimized_definition,
    '([[:space:]]+)FOR target_record IN',
    E'\n  batch_actuals := public.get_commitment_actuals_batch(\n    selected_start_date,\n    selected_end_date\n  );\n\n  for target_record in',
    'i'
  );

  optimized_definition := regexp_replace(
    optimized_definition,
    'actual_payload := public\.get_commitment_actual\([[:space:]]*target_record\.profile_slug,[[:space:]]*target_record\.owner_code,[[:space:]]*selected_start_date,[[:space:]]*selected_end_date[[:space:]]*\);',
    E'actual_payload := coalesce(\n      batch_actuals -> (target_record.profile_slug || ''|'' || target_record.owner_code),\n      jsonb_build_object(\n        ''financial_actual'', 0,\n        ''positivation_actual'', 0,\n        ''last_updated_at'', null\n      )\n    );',
    'i'
  );

  if optimized_definition = original_definition
     or position('get_commitment_overview_fast_base' in optimized_definition) = 0
     or position('batch_actuals jsonb;' in optimized_definition) = 0
     or position('batch_actuals := public.get_commitment_actuals_batch' in optimized_definition) = 0
     or position('batch_actuals -> (target_record.profile_slug' in optimized_definition) = 0
     or position('public.get_commitment_actual(' in optimized_definition) > 0 then
    raise exception 'Nao foi possivel criar a base otimizada de compromissos.';
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
  batch_item jsonb;
  closed_actual jsonb;
  closed_actuals jsonb := '{}'::jsonb;
  selected_start_date date;
  selected_end_date date;
  closed_end_date date;
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

  if date_trunc('month', selected_start_date)
     <> date_trunc('month', selected_end_date) then
    raise exception 'O periodo do compromisso deve estar dentro do mesmo mes.';
  end if;

  closed_end_date := least(
    selected_end_date,
    timezone('America/Sao_Paulo', now())::date - 1
  );
  if closed_end_date >= selected_start_date then
    closed_actuals := public.get_commitment_actuals_batch(
      selected_start_date,
      closed_end_date
    );
  end if;

  for item_record in
    select item.value
    from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) item
  loop
    -- Mantem a correcao vigente que evita duplicacao de metas quando codigos
    -- iguais existem em perfis diferentes.
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

    batch_item := closed_actuals -> (
      (item_record.value ->> 'profile_slug')
      || '|'
      || (item_record.value ->> 'owner_code')
    );
    closed_actual := jsonb_build_object(
      'financial_closed_actual',
        coalesce((batch_item ->> 'financial_actual')::numeric, 0),
      'positivation_closed_actual',
        coalesce((batch_item ->> 'positivation_actual')::integer, 0)
    );

    enriched_items := enriched_items || jsonb_build_array(
      item_record.value || closed_actual
    );
  end loop;

  return payload || jsonb_build_object('items', enriched_items);
end;
$$;

revoke all on function public.get_commitment_overview_optimized(
  date, date, text, text
) from public, anon, authenticated;

comment on function public.get_commitment_overview_optimized(
  date, date, text, text
) is 'Contrato vigente do Compromisso com realizados calculados em lote.';

-- RPC paralelo usado para comparar a implementacao otimizada com a atual
-- antes do corte definitivo.
create or replace function public.get_commitment_overview_v2_shadow(
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
  viewer_profile_slug text;
  requested_profile_slug text := nullif(
    lower(btrim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code text := nullif(
    btrim(coalesce(target_scope_owner_code, '')),
    ''
  );
  target_auth_user_id uuid;
  original_auth_user_id text;
  allowed_profiles constant text[] := array[
    'gerencia', 'coordenador', 'supervisor'
  ]::text[];
  available_scopes jsonb;
  payload jsonb;
begin
  select profile.slug into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Escopo do compromisso incompleto.';
  end if;

  available_scopes := public.app_view_scope_options(allowed_profiles);
  if requested_profile_slug is not null then
    target_auth_user_id := public.app_resolve_view_scope_auth_user(
      requested_profile_slug,
      requested_owner_code,
      allowed_profiles
    );
    if target_auth_user_id is null then
      raise exception 'Escopo do compromisso invalido.';
    end if;
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    if target_auth_user_id is not null then
      perform set_config(
        'request.jwt.claim.sub',
        target_auth_user_id::text,
        true
      );
    end if;
    payload := public.get_commitment_overview_optimized(
      target_start_date,
      target_end_date,
      null,
      null
    );
  exception when others then
    perform set_config(
      'request.jwt.claim.sub',
      coalesce(original_auth_user_id, ''),
      true
    );
    raise;
  end;
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(original_auth_user_id, ''),
    true
  );

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_commitment_overview_v2_shadow(
  date, date, text, text
) from public, anon;
grant execute on function public.get_commitment_overview_v2_shadow(
  date, date, text, text
) to authenticated;

comment on function public.get_commitment_overview_v2_shadow(
  date, date, text, text
) is 'RPC paralelo para validar o Compromisso em lote antes do corte.';
