-- Exclui titulos classificados pelos codigos de cobranca de perda do modulo
-- de inadimplencia, preservando integralmente as regras de escopo atuais.
do $$
declare
  original_definition text;
  patched_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_delinquency_overview(text,text)'::regprocedure
  );

  if position('PER2' in original_definition) = 0 then
    patched_definition := regexp_replace(
      original_definition,
      'where[[:space:]]+coalesce\(di\.tipo,[[:space:]]*''Geral''\)[[:space:]]*=[[:space:]]*''Geral''[[:space:]]+and[[:space:]]+di\.dtvenc',
      'where coalesce(di.tipo, ''Geral'') = ''Geral''
      and upper(btrim(coalesce(di.codcob, ''''))) not in (''PERD'', ''PER2'')
      and di.dtvenc',
      'i'
    );

    if patched_definition = original_definition
       or position('PER2' in patched_definition) = 0 then
      raise exception 'Nao foi possivel aplicar a exclusao de PERD/PER2 na inadimplencia.';
    end if;

    execute patched_definition;
  end if;
end;
$$;
