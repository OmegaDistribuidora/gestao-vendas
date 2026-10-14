-- Mantem no modulo de inadimplencia somente os 24 meses completos anteriores
-- ao mes corrente. O limite superior preserva a regra de que um titulo passa
-- a afetar a inadimplencia apenas no mes seguinte ao vencimento.
do $$
declare
  original_definition text;
  patched_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_delinquency_overview(text,text)'::regprocedure
  );

  if position(
    'di.dtvenc >= (current_month_start - interval ''24 months'')::date'
    in lower(original_definition)
  ) = 0 then
    patched_definition := regexp_replace(
      original_definition,
      'and[[:space:]]+di\.dtvenc[[:space:]]*<[[:space:]]*current_month_start',
      'and di.dtvenc >= (current_month_start - interval ''24 months'')::date
      and di.dtvenc < current_month_start',
      'i'
    );

    if patched_definition = original_definition
       or position(
         'di.dtvenc >= (current_month_start - interval ''24 months'')::date'
         in lower(patched_definition)
       ) = 0 then
      raise exception 'Nao foi possivel aplicar a janela de 24 meses na inadimplencia.';
    end if;

    execute patched_definition;
  end if;
end;
$$;
