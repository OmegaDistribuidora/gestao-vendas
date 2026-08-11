create or replace function public.gold_metrics(data jsonb)
returns jsonb
language sql
immutable
as $$
  with normalized as (
    select case
      when lower(coalesce(data ->> 'tipo_usuario', '')) = 'empresa' then
        data || jsonb_build_object(
          'meta_efetividade',
            coalesce(public.gold_number(data, 'meta_efetividade'), 0.30),
          'realizado_efetividade',
            coalesce(public.gold_number(data, 'realizado_efetividade'), 0),
          'percentual_realizado_efetividade',
            coalesce(public.gold_number(data, 'percentual_realizado_efetividade'), 0)
        )
      else data
    end as payload
  )
  select coalesce(
    jsonb_agg(metric order by sequence_number)
      filter (where metric is not null),
    '[]'::jsonb
  )
  from normalized n
  cross join lateral (values
    (1, public.gold_metric(n.payload, 'financial', 'Venda líquida', 'currency', 'meta_financeira', 'realizado_financeiro', 'percentual_realizado_financeiro', 'premio_financeiro', 'possibilidade_financeiro')),
    (2, public.gold_metric(n.payload, 'financial_15', 'Venda líquida até dia 15', 'currency', 'meta_financeira_ate_dia_15', 'realizado_financeiro_ate_dia_15', 'percentual_realizado_financeiro_ate_dia_15', 'premio_financeiro_ate_dia_15', 'possibilidade_financeiro_ate_dia_15')),
    (3, public.gold_metric(n.payload, 'positivation', 'Positivação', 'integer', 'meta_positivacao', 'realizado_positivacao', 'percentual_realizado_positivacao', 'premio_positivacao', 'possibilidade_positivacao')),
    (4, public.gold_metric(n.payload, 'sku', 'SKU', 'integer', 'meta_sku', 'realizado_sku', 'percentual_realizado_sku', 'premio_sku', 'possibilidade_sku')),
    (5, public.gold_metric(n.payload, 'volume', 'Volume', 'decimal', 'meta_volume', 'realizado_volume', 'percentual_realizado_volume', 'premio_volume', 'possibilidade_volume')),
    (6, public.gold_metric(n.payload, 'effectiveness', 'Efetividade', 'percent', 'meta_efetividade', 'realizado_efetividade', 'percentual_realizado_efetividade', 'premio_efetividade', 'possibilidade_efetividade')),
    (7, public.gold_metric(n.payload, 'profitability', 'Lucratividade', 'percent', 'meta_lucratividade', 'realizado_lucratividade', 'percentual_realizado_lucratividade', 'premio_lucratividade', 'possibilidade_lucratividade')),
    (8, public.gold_metric(n.payload, 'average_items', 'Média de itens', 'decimal', 'meta_media_itens', 'realizado_media_itens', 'percentual_realizado_media_itens', 'premio_media_itens', 'possibilidade_media_itens')),
    (9, public.gold_metric(n.payload, 'delinquency', 'Inadimplência', 'percent', 'meta_percentual_inadimplencia', 'realizado_percentual_inadimplencia', 'percentual_da_meta_inadimplencia', 'premio_inadimplencia', 'possibilidade_inadimplencia', true))
  ) as metrics(sequence_number, metric);
$$;
