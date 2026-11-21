# Admin da plataforma — implementação e publicação

Entrega de 14/11/2026. Painel: https://admin.tatuzin.com.br. Esta entrega pertence ao `admin_web`; o painel proprietário e o ERP mobile continuam separados.

## Resultado das seis etapas

| Etapa | Implementação |
| --- | --- |
| Fundamentos | Agregações no servidor, disponibilidade por seção, métricas com definição e período UTC; permissões por área e empresa. |
| Estrutura | Tema Material 3 roxo, tipografia local Noto Sans, menu lateral/rail/drawer responsivo, busca por toque ou Ctrl/Cmd+K com debounce de 300 ms. |
| Visão geral e empresas | Seis indicadores, evolução separada de empresas e pagamentos, prioridades, trabalho do administrador, lista paginada e espaço contextual da empresa. |
| Suporte e sincronização | Triagem paginada, chamados próprios da plataforma, responsável, notas, resolução e reabertura, evidências e revisão concorrente. |
| Comercial e operações | Assinaturas e cobranças unificadas; ações com prévia, motivo, confirmação, revisão de condições, deduplicação e auditoria. |
| Delegação e acabamento | Modelos de gestão/suporte/financeiro/auditoria, permissões individuais, uso observado, estados independentes e validação responsiva. |

## Fontes e regras dos indicadores

- Empresas: contagem filtrada no banco, sem inferir o total a partir de uma página.
- Assinaturas pagas ativas: contrato com provedor e situação ativa/autorizada. Trial não é receita recorrente paga.
- Pagamentos: cobranças BRL confirmadas por `paidAt` no período. Nunca são vendas dos lojistas.
- Vencidas: cobranças elegíveis com vencimento passado; detalhe comercial mantém moeda e situação reais.
- Problemas: conflitos abertos e falhas/rejeições de sincronização ainda relevantes. A triagem consulta todas as empresas autorizadas, com paginação.
- Chamados: entidades próprias `AdminSupportCase` e histórico, separadas do CRM.
- Uso: somente eventos `ProductJourneyEvent` existentes. Ausência de evento não comprova inatividade ou dispositivo saudável.

Consultas independentes permitem mostrar dados parciais. Sem informação recente ou sem permissão, a seção informa a indisponibilidade. Atualização de 60 segundos ocorre na visão geral e triagem enquanto a página está visível; formulários não são interrompidos.

## Navegação para testar

1. Entre com o administrador principal e abra `/dashboard`. Se necessário, atualize com Ctrl+F5.
2. Use a busca do topo ou Ctrl/Cmd+K para localizar uma empresa. Filtros e página ficam na URL.
3. Na empresa, percorra **Resumo, Suporte, Pessoas e acessos, Dispositivos, Sincronização, Assinatura e cobranças e Histórico**.
4. Em Suporte, abra um problema, crie/localize o chamado, assuma, anote e resolva com descrição do resultado. Reabrir mantém o histórico.
5. Em Operações da empresa, escolha uma ação autorizada, selecione o alvo e informe o motivo. Confira a prévia antes da confirmação. Use um alvo de teste para operações que alterem acesso/licença.
6. Para diagnóstico, confira os estados solicitado, recebido/em processamento e concluído no histórico do aparelho. Enviar não significa concluir.
7. Consulte a auditoria e volte à lista. Repita em 360/390 px ou no celular, e no desktop.

Rotas principais: `/dashboard`, `/companies`, `/support`, `/support/cases`, `/sync`, `/commercial`, `/devices`, `/usage`, `/audit`, `/administration`. As rotas anteriores continuam registradas; as de cobrança/licença direcionam à experiência comercial nova para o piloto.

## Contratos e autorização

Novas APIs sob `/api/admin`: `overview`, `capabilities`, `search`, `platform-companies`, `triage`, `subscriptions`, `invoices`, `usage`, `administrators`, `permission-templates/:key/apply`, `support/cases` e `operations/preview|execute`. Detalhes usam também as APIs existentes de empresa, auditoria, dispositivo, sessão e sincronização.

Leituras exigem `admin.<área>.read`, com escopo de plataforma ou empresa. Gestão de chamados exige `admin.support.manage`; cobrança, `admin.billing.manage`; delegação, `admin-permissions.manage`. Ações operacionais reutilizam os grants `support.*` correspondentes. Permissões são verificadas no servidor inclusive nas rotas legadas. Não há autoconcessão.

As migrações adicionam chamados/histórico, concessões **somente de leitura** para administradores existentes e consumo único da prévia. As novas permissões de alteração da conta principal foram concedidas separadamente após autorização explícita do usuário, com auditoria. A lista piloto permanece restrita pelo ambiente `ADMIN_PLATFORM_PILOT_USER_IDS`.

Ações liberadas: revogar sessão, bloquear/reativar acesso, prorrogar/suspender/reativar licença, atualizar cobrança pelo fluxo existente e solicitar diagnóstico já suportado pelo protocolo. Uma repetição usa a mesma chave de operação; resultado incerto não é reenviado automaticamente. A autorização e o estado do alvo são revalidados na execução.

## Arquivos centrais

- `admin_web/lib/src/features/platform/`: API/providers, páginas, componentes, chamados, operações, comercial, busca e espaço da empresa.
- `admin_web/lib/src/core/widgets/admin_platform_shell_scaffold.dart`: shell responsivo e alternância do piloto; shell anterior preservado.
- `admin_web/lib/src/app/admin_web_router.dart`, `lib/src/theme/admin_theme.dart`, `assets/fonts/`, `web/`: rotas, tema e recursos locais.
- `backend/src/modules/admin-platform/`, `admin-support-cases/`, `admin-platform-actions/`: contratos e controles novos.
- `backend/src/modules/admin/admin.routes.ts` e `admin-permissions/`: integração com autorização existente.
- `backend/prisma/migrations/20261114150000_admin_support_cases`, `20261114151000_admin_platform_read_permissions`, `20261114152000_admin_operation_preview_once`: alterações aditivas.
- `admin_web/test/admin_platform_test.dart` e testes backend dos módulos: regressões de navegação, estado, escopo, concorrência e execução.
- `backend/observability/admin-platform.nginx.conf`: publicação com recursos imutáveis por versão e entrada sem cache.

## Validação realizada

- `flutter analyze`: sem problemas.
- Suíte Flutter completa: 131 testes passaram, registrados em `admin_web/build/admin-platform/flutter-tests.log`; inclui testes existentes e os novos cenários de navegação real, confirmação, formulários e estados.
- Backend: 87 testes em oito suítes passaram; regressão final de operações/contratos também passou (40 testes, subconjunto das suítes anteriores). TypeScript sem erros.
- Navegador Chromium com o Flutter compilado: 360, 390, 768, 1280 e 1440 px, busca pelo teclado, sem exceções JavaScript nem falhas de recursos. APIs interceptadas com fixtures identificadas como demonstração, sem credenciais reais ou mutações remotas.
- Publicação HTTPS: oito caminhos do painel retornaram a versão final, checksum remoto conferido, entrada sem cache e recursos imutáveis. Login público abriu sem exceções, falhas de recursos ou respostas HTTP de erro; APIs administrativas sem autenticação retornaram 401, com CORS correto.
- Widgets nas mesmas cinco larguras com texto a 100% e 200%, abertura de drawer, rotas reais, criação de chamado, estados de carregamento/erro/permissão e recuperação. Capturas em `admin_web/build/admin-platform/`.
- O teste antigo de sessão usava vencimento fixo já passado. O fixture passou a usar vencimento futuro relativo; a regra de expiração da aplicação foi preservada.

As capturas automatizadas contêm dados de demonstração exclusivos dos testes. Produção consulta as fontes reais. A repetição autenticada pelo usuário no ambiente publicado continua necessária para aceite final; nenhum fluxo financeiro real foi alterado para produzir evidência de teste.

## Publicação e reversão

Backend publicado primeiro: `tatuzin-backend:admin-platform-20261114-r3`. Migrações aplicadas e container saudável. Frontend atual: `admin-platform-20261114-r2`; `/release.json` informa versão, imagem compatível e SHA-256 de `main.dart.js`.

O nginx serve `/var/www/tatuzin-admin-current`, apontando para uma pasta imutável em `/var/www/tatuzin-admin-releases/`. O painel anterior foi preservado em `admin-before-platform-20261114`; o primeiro release novo também foi mantido. Para reversão visual, trocar o symlink atomicamente para a versão anterior. Para desligar o piloto, limpar o allowlist do ambiente e recriar apenas o backend. Migrações aditivas permanecem compatíveis; não remover tabelas durante rollback.

Backup privado anterior às migrações, configuração de ambiente, imagem anterior e configuração nginx foram preservados em `.release-backups/admin-platform-20261114/`, com acesso restrito. Não publicar esses arquivos. Recursos imutáveis e índice sem cache evitam misturar versões; um service worker antigo é desregistrado.

## Limites explícitos

MRR, churn, previsão, comunicação externa, ajustes financeiros excepcionais, resolução automática de conflitos e exclusão definitiva seguem fora desta evolução. As operações financeiras legadas excepcionais não foram concedidas ao piloto. A área restrita de privacidade só aparece com sua permissão própria.

O formulário de modelos concede escopo de plataforma; concessões granulares por empresa continuam disponíveis na gestão individual e no contrato backend. Dados de uso/diagnóstico dependem da telemetria que os aparelhos realmente enviarem. O rollout para outros administradores depende de aceite e concessões explícitas.
