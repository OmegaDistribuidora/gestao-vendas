-- Ativa a implementacao otimizada depois da validacao paralela de todos os
-- periodos e escopos disponiveis. O contrato publico e as permissoes do RPC
-- permanecem inalterados; somente a funcao interna e substituida.

do $$
declare
  original_definition text;
  optimized_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_commitment_overview_v2(date,date,text,text)'::regprocedure
  );

  optimized_definition := regexp_replace(
    original_definition,
    'payload := public\.get_commitment_overview\(',
    'payload := public.get_commitment_overview_optimized(',
    'i'
  );

  if optimized_definition = original_definition
     or position(
       'payload := public.get_commitment_overview_optimized('
       in optimized_definition
     ) = 0
     or position(
       'payload := public.get_commitment_overview('
       in optimized_definition
     ) > 0 then
    raise exception 'Nao foi possivel ativar o Compromisso otimizado.';
  end if;

  execute optimized_definition;
end;
$$;

comment on function public.get_commitment_overview_v2(
  date, date, text, text
) is 'Compromisso com espelho hierarquico e calculo escalar otimizado, mantendo o contrato original.';

-- A primeira tentativa em lote global nao e usada porque o conjunto
-- intermediario ficou maior que o plano escalar por hierarquia.
drop function if exists public.get_commitment_actuals_batch(date, date);
