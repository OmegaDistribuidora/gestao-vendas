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
    '''realizado_efetividade'',sum(public.gold_number(payload,''quantidade_pedidos_efetividade''))/nullif(sum(public.gold_number(payload,''quantidade_pedidos_roteirizados_no_dia'')),0),',
    '''realizado_efetividade'',sum(public.gold_number(payload,''quantidade_pedidos_roteirizados_no_dia''))/nullif(sum(public.gold_number(payload,''quantidade_pedidos_efetividade'')),0),'
  );

  if corrected_definition = function_definition then
    raise exception 'Nao foi possivel localizar o calculo realizado da efetividade consolidada.';
  end if;

  function_definition := corrected_definition;
  corrected_definition := replace(
    function_definition,
    '''percentual_realizado_efetividade'',(sum(public.gold_number(payload,''quantidade_pedidos_efetividade''))/nullif(sum(public.gold_number(payload,''quantidade_pedidos_roteirizados_no_dia'')),0))/nullif(max(public.gold_number(payload,''meta_efetividade'')),0),',
    '''percentual_realizado_efetividade'',(sum(public.gold_number(payload,''quantidade_pedidos_roteirizados_no_dia''))/nullif(sum(public.gold_number(payload,''quantidade_pedidos_efetividade'')),0))/nullif(max(public.gold_number(payload,''meta_efetividade'')),0),'
  );

  if corrected_definition = function_definition then
    raise exception 'Nao foi possivel localizar o percentual da meta de efetividade consolidada.';
  end if;

  execute corrected_definition;
end;
$$;

comment on function public.get_performance_overview_v2(date, text, text) is
  'Performance Gold do app. Na visao Empresa, a efetividade consolidada e o total positivado no dia roteirizado dividido pelo total de ocorrencias roteirizadas dos coordenadores.';
