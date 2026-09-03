# Gestão de Vendas

Aplicativo Flutter para Android e iOS voltado à autenticação de usuários,
acompanhamento comercial e gestão operacional integrada ao Supabase.

## Visão Geral

O app foi desenhado para operação remota, com Supabase como backend principal para:

- autenticação de usuários
- perfis e permissões
- gestão administrativa
- relatórios de uso
- snapshots de dados operacionais consumidos na home
- módulos como Compromisso, Performance, Agenda, devoluções e análise por fornecedor

O armazenamento local é usado apenas para itens de sessão e conveniência do usuário, como a preferência de lembrar login.

## Arquitetura

Estrutura principal:

- `lib/main.dart`: inicialização do Flutter e do Supabase
- `lib/app.dart`: configuração do app e tema global
- `lib/services/app_repository.dart`: camada central de acesso a dados e regras de integração
- `lib/screens/`: telas do fluxo de login, home, administração, relatórios e módulos operacionais
- `lib/models/`: modelos de domínio usados pelo app
- `supabase/migrations/`: histórico de schema e funções SQL
- `supabase/functions/admin-users/`: Edge Function para operações administrativas sensíveis
- `supabase/functions/send-push-notifications/`: avaliação e envio de notificações comerciais
- `tool/oracle_sales_sync.py`: sincronização manual ou automatizada de vendas do dia para KPIs
- `tool/oracle_sellers_sync.py`: sincronização manual ou automatizada de vendedores vindos do Oracle
- `tool/oracle_billing_sync.py`: faturamento e agregação oficial de fornecedores
- `docs/IOS_CODEMAGIC_SETUP.md`: preparação e distribuição do iOS pelo Codemagic

## Fluxos Principais

Autenticação:

- vendedores entram com código e senha
- demais perfis entram com nome de exibição e senha
- o app resolve o login técnico no backend antes de autenticar no Supabase Auth

Autorização:

- administradores têm acesso à área administrativa e aos relatórios
- usuários comuns acessam os módulos permanentes do aplicativo pelo menu lateral
- o perfil Gerência acessa somente os coordenadores 9, 10, 12, 13 e 14 e suas hierarquias
- diretoria e outros preservam a visão completa da empresa

Home:

- admin vê acesso direto à administração
- os perfis comerciais veem os KPIs diários permitidos pelo próprio escopo
- supervisor, coordenador, Gerência, diretoria e outros podem trocar a visão conforme a hierarquia autorizada

## Integrações Externas

Os scripts em `tool/` foram pensados para execução manual ou orquestrada:

- sincronização de vendas do Oracle para o Supabase
- sincronização de faturamento, devoluções e itens dos pedidos
- sincronização de vendedores do Oracle para o Supabase

Esses scripts dependem de variáveis de ambiente para conexão e autenticação. Não há credenciais sensíveis documentadas neste repositório.

## Desenvolvimento

Pré-requisitos:

- Flutter compatível com a versão do projeto
- Android SDK
- Node.js para fluxo do Supabase CLI quando necessário
- Python para os scripts de integração

Comandos úteis:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build appbundle --release
```

## Segurança

Boas práticas adotadas neste projeto:

- nenhuma credencial de banco relacional é embutida diretamente no app
- operações administrativas sensíveis ficam atrás de Edge Function
- dados locais são limitados ao mínimo necessário para a experiência do usuário
- este README não documenta chaves, senhas, URLs privadas ou procedimentos de acesso privilegiado

## Observações

- O app depende de estrutura remota no Supabase já provisionada pelas migrations locais.
- Os scripts Python devem ser executados em ambiente controlado, com variáveis de ambiente definidas fora do código.
