# Auditoria de capacidade do Supabase

Data da auditoria: 30/06/2026

Este documento registra o diagnostico de espaco do banco e as medidas seguras
adotadas. Ele nao contem credenciais, tokens ou chaves.

## Resultado

- Tamanho antes da manutencao: 664 MB (695.782.547 bytes).
- Tamanho depois da manutencao: 452 MB (474.418.323 bytes).
- Espaco recuperado: aproximadamente 212 MB.
- Nenhuma tabela funcional do aplicativo foi apagada ou reduzida.
- Nenhuma tabela do schema `auth` foi alterada manualmente.
- As sincronizacoes continuaram concluindo com sucesso depois da manutencao.

O ganho veio da remocao de dados temporarios abandonados em tabelas
`etl_stg_*`. Esses dados pertenciam somente a execucoes ETL ja encerradas com
falha e nunca eram consultados pelo aplicativo.

## Principais consumidores antes da manutencao

| Objeto | Tamanho aproximado | Funcao | Decisao |
| --- | ---: | --- | --- |
| `etl_stg_financial_snapshots` e indice primario | 200 MB | Area temporaria da ETL financeira | Limpeza segura aplicada |
| `app_sales_order_items` | 106 MB | Itens e detalhes de pedidos | Manter |
| `app_customer_opportunities` | 75 MB | Mapa de oportunidades | Manter |
| `auth.refresh_tokens` | 42 MB | Sessoes gerenciadas pelo Supabase Auth | Nao alterar manualmente |
| `app_sales_daily_snapshots` | 37 MB | Home e performance | Manter |
| `app_financial_snapshots` | 37 MB | Home, performance e fornecedor | Manter |
| `app_customers` | 33 MB | Clientes e seus detalhes | Manter |
| `etl_sync_runs` | 20 MB | Historico e datas de atualizacao | Criar retencao futura controlada |

Observacao: o painel lista tabelas e indices separadamente entre os maiores
objetos. Por isso, o indice primario de `etl_stg_financial_snapshots` aparecia
como outro consumidor de 104 MB.

## Causa confirmada

A tabela temporaria `etl_stg_financial_snapshots` continha 545.329 linhas de
106 execucoes que terminaram com falha entre 25/06 e 29/06. Nao havia execucao
ativa proprietaria dessas linhas. As falhas eram principalmente timeout de
comando, com um caso de deadlock.

A funcao de falha marcava a execucao em `etl_sync_runs`, mas nao removia o lote
temporario. Com repetidas tentativas, tanto a tabela quanto seu indice cresceram.

## Correcao aplicada

A migration
`supabase/migrations/20260630210000_cleanup_failed_etl_staging.sql`:

1. Faz `mark_sync_run_failed` remover o lote da execucao em todas as tabelas
   temporarias antes de registrar a falha.
2. Bloqueia as tabelas temporarias durante a limpeza inicial.
3. Interrompe e desfaz a operacao se encontrar qualquer lote de uma execucao
   ainda ativa ou sem encerramento registrado.
4. Limpa somente as tabelas `etl_stg_*` depois dessa validacao.

Essa protecao evita que uma execucao em andamento seja apagada e impede que o
mesmo acumulo volte a ocorrer quando uma sincronizacao falhar.

## Dependencias que impedem exclusoes simples

- `app_sales_order_items`: detalhes dos ultimos pedidos em Clientes sem compra
  e contagem de produtos distintos na Home.
- `app_customer_opportunities`: pontos, filtros e detalhes do Mapa de
  oportunidades, alem do fluxo de clientes recuperados.
- `app_sales_daily_snapshots`: indicadores da Home e da Performance.
- `app_financial_snapshots`: indicadores financeiros, Performance e Analise
  por fornecedor.
- `app_customers` e `app_customer_seller_bases`: clientes, enderecos, bloqueio
  e escopo por vendedor.
- `etl_sync_runs`: datas de ultima atualizacao exibidas no app e auditoria das
  sincronizacoes.

Essas tabelas nao devem ser truncadas, ter historico removido ou perder indices
sem uma mudanca funcional previamente testada no aplicativo.

## Proximas acoes recomendadas

### Prioridade 1 - evitar crescimento do Supabase Auth

Os processos ETL atualmente autenticam com e-mail e senha a cada execucao. A
auditoria encontrou muitas insercoes e exclusoes nas tabelas internas de
sessoes, embora existam poucos usuarios ativos. Isso causa bloat em
`auth.refresh_tokens`, `auth.sessions` e `auth.mfa_amr_claims`.

Migrar as ETLs para uma chave secreta de servidor do Supabase, armazenada apenas
no ambiente do servidor e nunca no app ou no Git. Depois da migracao, acompanhar
o crescimento por alguns dias. Nao apagar registros do schema `auth`
manualmente.

### Prioridade 2 - retencao de logs da ETL

`etl_sync_runs` acumulou mais de 14 mil linhas em cerca de 11 dias. Implementar
retencao controlada, inicialmente de 30 dias, mantendo sempre as execucoes mais
recentes de cada fonte. Antes de aplicar, validar novamente as chaves
estrangeiras e as consultas de ultima atualizacao.

### Prioridade 3 - monitoramento

- Aviso preventivo ao atingir 450 MB.
- Aviso critico ao atingir 480 MB.
- Conferir semanalmente tamanho total, maiores tabelas e indices, linhas mortas
  e execucoes ETL com falha.
- Alertar quando qualquer tabela `etl_stg_*` mantiver linhas de execucoes
  encerradas.

## Acoes que nao devem ser feitas agora

- Nao remover historico das tabelas `app_*` grandes apenas para ganhar espaco.
- Nao remover indices sem medir os planos das consultas e o impacto nas APIs.
- Nao truncar ou editar tabelas do schema `auth` manualmente.
- Nao executar `VACUUM FULL` em horario de uso: ele exige bloqueio exclusivo e
  espaco temporario adicional.
- Nao usar `pg_repack` sem janela de manutencao e folga de disco; a operacao
  precisa de espaco temporario significativo.

## Criterio de seguranca

Qualquer manutencao futura deve seguir esta ordem:

1. Medir tamanho e confirmar a origem do crescimento.
2. Mapear consultas, funcoes, chaves estrangeiras e telas dependentes.
3. Fazer backup ou garantir um ponto de restauracao.
4. Aplicar primeiro em uma transacao com validacoes de abortagem.
5. Confirmar sincronizacoes e consultas do app imediatamente depois.
6. Registrar o antes, o depois e a migration correspondente.
