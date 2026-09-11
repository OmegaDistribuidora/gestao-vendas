# Efetividade diária e Roteirização

Recurso publicado em produção na versão 0.9.19+35.

## Regra

- Home: bloco tocável logo abaixo de Positivação/Meta de Positivação.
- Percentual = ocorrências com compra / ocorrências previstas no dia × 100.
- Chave: vendedor + cliente + data; pedidos repetidos contam uma vez.
- O roteiro previsto vem de filial."fRoteiro"; a compra no dia e o valor vêm
  de gold_src.fvendas, fonte curta atualizada diretamente do Oracle.
- Compra fora do roteiro não participa. Não exige cliente novo no mês.
- Não deduz devoluções e não afirma que houve visita física.
- Hierarquia: última carga de deqpcomercial; excluir bloqueados e time Outros.
- Tipos: tauxtipovendedor, registro mais recente por vendedor. Rds Rca/Rds Clt
  ficam fora do numerador/denominador. Supervisores 33/35 não têm o indicador.
- Lideranças: dividir totais das ocorrências, sem média simples de percentuais.
- Gerência: mesmos coordenadores configurados em app_profile_coordinator_scopes.
- Sem roteiro hoje: percentual nulo; roteiro sem compra: 0%.
- Filtro da Home governa resumo e detalhes. Vendedor não vê nome do próprio
  vendedor repetido; liderança vê código/nome em cada ocorrência.

## Dados e consistência

daily_routing_source.sql apura somente um dia, com leitura consistente das fontes.
daily_routing_sync.py mantém a proteção de completude da fonte e rejeita hierarquia
ambígua. O modo padrão apenas lê e imprime contagens; --publish é explícito.

A migration 20260910120000_home_daily_routing.sql cria uma tabela de snapshots e
as RPCs de carga e consulta. app_apply_daily_routing_snapshot aceita somente
service_role ou a conta administrativa usada pelas rotinas de ETL;
as tabelas não têm leitura direta para authenticated/anon. O snapshot inteiro é
substituído atomicamente. O endpoint de consulta autentica o usuário ativo,
valida a troca de visão pelo resolvedor existente e aplica app_scope_matches.

Resumo não transfere a lista. Detalhe tem filtro Todos/Com compra/Sem compra,
paginação de 100 ocorrências e versão de snapshot: uma página de outra versão
é rejeitada e solicita atualização. Respostas antigas não substituem uma nova
visão da Home. Falha de roteirização não interrompe o carregamento dos outros KPIs.

A Home e o módulo consultam a cada dois minutos e ao atualizar manualmente. A
DAG omega_daily_routing_sync também roda a cada dois minutos, mas envia ao
Supabase somente quando roteiro, atendimento, pedidos ou valores mudam. A
fRoteiro é reconstruída atomicamente a cada dez minutos quando suas fontes
mudam; vendas já presentes em gold_src.fvendas entram diretamente no snapshot,
sem aguardar a carga histórica de BI. A sincronização roda nos minutos ímpares,
normalmente depois da atualização Oracle da Gold, e preserva o último snapshot
se a fonte rápida estiver há mais de 15 minutos sem atualização.

## Rodar a prévia

1. Executar `python tool/daily_routing_preview.py` nesta máquina Windows.
2. Executar `adb reverse tcp:8766 tcp:8766`.
3. Compilar/executar Flutter debug com
   `--dart-define=DAILY_ROUTING_PREVIEW_URL=http://127.0.0.1:8766`.

A prévia verifica o JWT no Supabase Auth e valida seleções de usuário no
resolvedor real. Consulta Omega em modo read-only. Executa a migration nova
somente em PostgreSQL isolado na porta 55439, dentro de .dart_tool, e recebe
requisições em 127.0.0.1:8766. A credencial técnica vem do CLI autenticado e
permanece no processo local: não é gravada no APK nem em arquivo.

Apenas esta consulta usa o serviço local; demais módulos continuam com os
serviços habituais. É necessário manter o processo da prévia aberto para testar.
Não se usa URL de prévia em release. A versão publicada consulta somente o
Supabase oficial.

## Produção

- Migrations aplicadas: 20260910120000, 20260911120000 e 20260911123000.
- A DAG executa daily_routing_sync.py --publish a cada dois minutos, com
  max_active_runs=1, timeout e retries.
- A autenticação reutiliza a conta administrativa de ETL já protegida fora do
  repositório; nenhuma credencial administrativa entra no aplicativo.
- O script compara a assinatura local antes de conectar ao Supabase e só
  registra a assinatura depois da publicação bem-sucedida.
- Verificar origem/hierarquia, permissões e controles de completude em produção.
- A Gold mensal, APIs existentes da Home e notificações não são modificadas.

## Validações

- `python tool/test_daily_routing_sql.py`: integração na base isolada, rollback
  das fixtures; escopos, ponderação, Redes, paginação, versão, duplicados e auth.
- `flutter test test/daily_routing_test.dart test/home_dashboard_test.dart`:
  percentual, detalhes/filtro, resposta atrasada, ocultação e ausência de roteiro.
- `flutter analyze --no-pub`.
