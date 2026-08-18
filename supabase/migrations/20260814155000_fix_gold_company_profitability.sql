do $$
declare
  function_definition text;
  corrected_definition text;
begin
  function_definition := pg_get_functiondef(
    'public.get_performance_overview_v2(date,text,text)'::regprocedure
  );

  corrected_definition := replace(
    function_definition,
    '''realizado_lucratividade'',(sum(public.gold_number(payload,''realizado_financeiro''))-sum(public.gold_number(payload,''custo_faturamento''))+sum(public.gold_number(payload,''custo_devolucao'')))/nullif(sum(public.gold_number(payload,''realizado_financeiro'')),0),',
    '''realizado_lucratividade'',(sum(public.gold_number(payload,''faturamento_liquido''))+sum(public.gold_number(payload,''custo_devolucao''))-sum(public.gold_number(payload,''custo_faturamento'')))/nullif(sum(public.gold_number(payload,''faturamento_liquido'')),0),'
  );

  if corrected_definition = function_definition then
    raise exception 'Nao foi possivel localizar o calculo consolidado da lucratividade.';
  end if;

  function_definition := corrected_definition;
  corrected_definition := replace(
    function_definition,
    '''percentual_realizado_lucratividade'',((sum(public.gold_number(payload,''realizado_financeiro''))-sum(public.gold_number(payload,''custo_faturamento''))+sum(public.gold_number(payload,''custo_devolucao'')))/nullif(sum(public.gold_number(payload,''realizado_financeiro'')),0))/nullif(max(public.gold_number(payload,''meta_lucratividade'')),0),',
    '''percentual_realizado_lucratividade'',((sum(public.gold_number(payload,''faturamento_liquido''))+sum(public.gold_number(payload,''custo_devolucao''))-sum(public.gold_number(payload,''custo_faturamento'')))/nullif(sum(public.gold_number(payload,''faturamento_liquido'')),0))/nullif(max(public.gold_number(payload,''meta_lucratividade'')),0),'
  );

  if corrected_definition = function_definition then
    raise exception 'Nao foi possivel localizar o percentual consolidado da lucratividade.';
  end if;

  execute corrected_definition;
end;
$$;

comment on function public.get_performance_overview_v2(date, text, text) is
  'Performance Gold do app. Na visao Empresa, a lucratividade consolidada usa faturamento liquido, custo do faturamento e custo das devolucoes somados nas linhas de coordenador.';
