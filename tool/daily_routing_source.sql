-- Same eligibility and occurrence semantics as Gold; no financial netting.
-- The expanded attributes are shared by Home daily effectiveness and the
-- Routing Analysis module. Only one requested day is read at a time.
with route_sellers as (
  select distinct codusur::text as seller_code
  from filial."fRoteiro"
  where data = %(day)s
), hierarchy as (
  select distinct on (codusur) codusur, rca, codsup, codgerente,
         coalesce(upper(trim(bloqueio)), 'N') <> 'S'
         and coalesce(upper(trim(time)), '') <> 'OUTROS' as eligible
  from filial.deqpcomercial
  where data_insercao = (select max(data_insercao) from filial.deqpcomercial)
  order by codusur, codsup, codgerente
), types as (
  select distinct on (codusur) codusur, st_tipo
  from filial.tauxtipovendedor
  order by codusur, data_insercao desc nulls last
), sellers as (
  select h.codusur::text as seller_code, coalesce(h.rca,'') as seller_name,
         h.codsup::text as supervisor_code, h.codgerente::text as coordinator_code,
         h.eligible and lower(trim(coalesce(t.st_tipo,''))) not in ('rds rca','rds clt') as eligible,
         lower(trim(coalesce(t.st_tipo,''))) in ('rds rca','rds clt') as is_network
  from hierarchy h
  join route_sellers route on route.seller_code = h.codusur::text
  left join types t on t.codusur=h.codusur
), fast_sales as (
  -- Fonte curta atualizada diretamente do Oracle pela DAG gold_performance.
  -- Ela evita que a efetividade do dia espere a carga histórica de BI.
  select codusur, codcli,
         sum(coalesce(venda,0))::numeric as sale_amount
  from gold_src.fvendas
  where data=%(day)s
  group by codusur,codcli
), local_orders as (
  -- O número de pedidos é apenas metadado auxiliar e não participa da
  -- efetividade nem do valor apresentado. A fonte rápida não guarda numped.
  select codusur,codcli,count(distinct numped)::integer as order_count
  from filial.fvendas
  where data=%(day)s and numped is not null
  group by codusur,codcli
), occurrences as (
  select rt.codusur::text as seller_code, rt.codcli::text as customer_code,
         max(coalesce(rt.cliente,'')) as customer_name,
         max(coalesce(rt.endereco,'')) as address,
         max(coalesce(rt.bairro,'')) as neighborhood,
         max(coalesce(rt.cidade,'')) as city,
         max(rt.latitude) as latitude,
         max(rt.longitude) as longitude,
         max(coalesce(dc.codrota,0))::text as route_code,
         max(coalesce(dc.seqrota,0)) as route_sequence,
         max(coalesce(rt.frequencia,'')) as frequency,
         max(coalesce(rt.tipo,'')) as route_type,
         max(coalesce(rt.dia_da_semana,'')) as weekday,
         bool_or(v.codusur is not null) as purchased,
         max(coalesce(v.sale_amount,0))::numeric as sale_amount,
         max(coalesce(o.order_count,0))::integer as order_count
  from filial."fRoteiro" rt
  join sellers s on s.seller_code=rt.codusur::text and s.eligible
  left join filial.dcliente dc on dc.codcli=rt.codcli
  left join fast_sales v on v.codusur=rt.codusur and v.codcli=rt.codcli
  left join local_orders o on o.codusur=rt.codusur and o.codcli=rt.codcli
  where rt.data = %(day)s
  group by rt.codusur,rt.codcli
)
select jsonb_build_object(
  'reference_date', %(day)s::date,
  'source_updated_at', greatest(
    (select completed_at from gold_src.sync_state where source_name='fvendas'),
    (select last_run_at from filial."fSolicitacoesTradeSyncState" where sync_name='roteiro')
  ),
  'routing_updated_at', (select last_run_at from filial."fSolicitacoesTradeSyncState" where sync_name='roteiro'),
  'sellers', (select coalesce(jsonb_agg(to_jsonb(s) order by s.seller_code),'[]') from sellers s),
  'items', (select coalesce(jsonb_agg(to_jsonb(o) order by o.seller_code,o.customer_code),'[]') from occurrences o)
);
