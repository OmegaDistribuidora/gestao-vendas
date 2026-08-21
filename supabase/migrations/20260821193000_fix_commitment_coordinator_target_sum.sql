-- Evita duplicar metas de compromisso quando perfis diferentes compartilham
-- o mesmo codigo dentro da hierarquia comercial (por exemplo, codigo 1).

create or replace function public.get_commitment_overview(
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
  closed_actual jsonb;
  selected_start_date date;
  selected_end_date date;
  corrected_financial_target numeric;
  corrected_positivation_target numeric;
  supervisor_target_count integer;
begin
  payload := public.get_commitment_overview_base(
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

  for item_record in
    select item.value
    from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) item
  loop
    -- A meta do coordenador e a soma de compromissos distintos dos seus
    -- supervisores reais. EXISTS impede que codigos iguais de outros perfis
    -- multipliquem a mesma linha de compromisso.
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

    closed_actual := public.get_commitment_closed_actual(
      item_record.value ->> 'profile_slug',
      item_record.value ->> 'owner_code',
      selected_start_date,
      selected_end_date
    );

    enriched_items := enriched_items || jsonb_build_array(
      item_record.value || closed_actual
    );
  end loop;

  return payload || jsonb_build_object('items', enriched_items);
end;
$$;

revoke all on function public.get_commitment_overview(date, date, text, text)
  from public, anon;
grant execute on function public.get_commitment_overview(date, date, text, text)
  to authenticated;

comment on function public.get_commitment_overview(date, date, text, text) is
  'Metas sem duplicacao por codigo, realizado ao vivo e bases encerradas para tendencia.';
