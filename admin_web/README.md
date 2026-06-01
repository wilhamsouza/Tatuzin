# Tatuzin Admin Web

Painel web interno da plataforma Tatuzin, usado por suporte, operacao e
auditoria administrativa. Este projeto e o **platform admin** da Tatuzin:
ele e separado do `owner_web`, nao atende fluxos owner do cliente e nao deve
consumir contratos `/api/owner/*`.

O admin web consome rotas `/api/admin/*` do backend Tatuzin ERP. Ele nao deve
criar rota `/owner`, nao deve substituir o app Android e nao deve mudar contrato
de API para documentar ou reorganizar navegacao.

## Stack

- Flutter Web
- Riverpod
- GoRouter
- `http`
- `shared_preferences`

## Rotas registradas

Rotas reais registradas em
[`admin_web_router.dart`](c:/Simples/admin_web/lib/src/app/admin_web_router.dart):

| Rota | Uso |
| --- | --- |
| `/` | Redirect para `/dashboard`. |
| `/login` | Login administrativo. |
| `/dashboard` | Dashboard interno da plataforma. |
| `/companies` | Empresas. |
| `/companies/:companyId` | Detalhe administrativo da empresa. |
| `/companies/:companyId/support` | Central de suporte read-only da empresa. |
| `/companies/:companyId/sync` | Sync Center da empresa. |
| `/companies/:companyId/license` | Licenca e billing da empresa. |
| `/companies/:companyId/users` | Usuarios e funcionarios da empresa. |
| `/companies/:companyId/employees` | Alias compat: redirect para `/companies/:companyId/users`. |
| `/companies/:companyId/devices` | Dispositivos e sessoes da empresa. |
| `/companies/:companyId/sessions` | Console read-only de sessoes da empresa. |
| `/sync` | Sync Center global. |
| `/sync/:companyId` | Alias operacional para Sync Center da empresa. |
| `/sync/:companyId/events/:eventId` | Detalhe read-only de evento de sync. |
| `/sync/:companyId/conflicts/:conflictId` | Detalhe read-only de conflito de sync. |
| `/devices` | Inventario global de dispositivos e sessoes. |
| `/licenses` | Licencas read-only. |
| `/licenses/:companyId` | Licenca e billing da empresa. |
| `/plans` | Matriz de planos. |
| `/permissions` | Gestao controlada de permissoes administrativas. |
| `/admin/permissions` | Alias compat: redirect para `/permissions`. |
| `/audit` | Auditoria global. |
| `/billing` | Billing restrito. |
| `/billing/:companyId` | Detalhe restrito de billing por empresa. |
| `/sync-health` | Saude do sync. |
| `/management/dashboard` | Rota gerencial legada, fora do menu principal. |
| `/management/reports` | Relatorios gerenciais legados, fora do menu principal. |
| `/management/governance` | Governanca hibrida legada, fora do menu principal. |
| `/management/crm/customers` | CRM gerencial legado, fora do menu principal. |
| `/management/crm/customers/:customerId` | Detalhe de cliente CRM legado. |

## Nomenclatura da UI

Nomes visiveis devem seguir estes rotulos para evitar aliases confusos:

- Empresas: contas/tenants atendidos pela plataforma.
- Usuarios: contas de acesso vinculadas a uma empresa.
- Funcionarios: perfis operacionais da empresa, quando existirem.
- Dispositivos: aparelhos ou clientes registrados.
- Sessoes: sessoes recentes associadas a dispositivos.
- Licencas: consulta read-only de plano, status e limites.
- Billing: area restrita para suporte administrativo de cobranca.
- Sync Center: triagem de sync, eventos e conflitos.
- Auditoria: historico administrativo normalizado.
- Permissoes administrativas: catalogo, consulta e grant/revoke controlados de
  `AdminUserPermission`.

Aliases mantidos por compatibilidade devem apontar para a nomenclatura canonica:
`employees` redireciona para `users`. `sessions` agora possui rota dedicada
read-only, enquanto a tela de dispositivos segue exibindo sessoes recentes como
secao complementar.

As principais telas usam breadcrumbs no shell para manter o contexto entre
Empresas, Central de suporte, Usuarios, Dispositivos, Licencas, Billing, Sync
Center e Auditoria.

## Fechamento do roadmap

O relatorio final das 12 fases iniciais esta em
[`docs/admin-web-roadmap-closure.md`](docs/admin-web-roadmap-closure.md). Ele
consolida o que foi concluido, o que permanece read-only, dependencias futuras
por backend, Android, infraestrutura, seguranca/auditoria e proximos epicos
recomendados.

## Areas do painel

- Login administrativo e restauracao de sessao.
- Dashboard resumido de plataforma.
- Empresas e detalhe administrativo.
- Central de suporte read-only por empresa.
- Usuarios e funcionarios por empresa.
- Dispositivos e sessoes globais ou por empresa.
- Console de sessoes por empresa em `/companies/:companyId/sessions`.
- Licencas read-only para suporte seguro.
- Permissoes administrativas com consulta e grant/revoke controlados.
- Billing restrito para investigacao e correcao administrativa auditada.
- Sync Center global e por empresa.
- Saude do sync.
- Auditoria administrativa.
- Rotas gerenciais legadas mantidas por compatibilidade interna.

## Documentacao de contratos

A documentacao preliminar dos contratos consumidos pelo admin_web esta em
[`docs/api-contracts.md`](docs/api-contracts.md). Ela inventaria endpoints,
models, payloads esperados, estados de erro, dependencias por tela, lacunas de
contrato e regras futuras para acoes operacionais.

Tambem existe um rascunho OpenAPI inicial em
[`docs/openapi-admin-web-draft.yaml`](docs/openapi-admin-web-draft.yaml). Esse
arquivo documenta apenas endpoints identificados no front-end e nao cria
contratos, endpoints ou acoes novas.

## Seguranca

A politica de seguranca do painel esta em
[`docs/security-admin-web.md`](docs/security-admin-web.md). Ela documenta os
limites do front-end, riscos conhecidos, regras de logs seguros, tratamento de
dados sensiveis na UI e requisitos futuros como Cookie HttpOnly, BFF, CSP,
security headers, MFA, rate limit, expiracao de sessao, auditoria obrigatoria,
permissoes granulares, dry-run e motivo obrigatorio para acoes sensiveis.

Nesta fase, o admin_web continua read-only nas telas operacionais sensiveis e
nao altera autenticacao real, autorizacao real, backend, contratos de API ou
infraestrutura.

## Observabilidade

A base de observabilidade read-only esta documentada em
[`docs/observability-admin-web.md`](docs/observability-admin-web.md). Ela
descreve metricas futuras, alertas desejados, lacunas atuais e como Central de
Suporte, Sync Center, Billing e Auditoria se relacionam com saude operacional.

Esta documentacao nao cria Prometheus, Grafana, coleta real de metricas,
webhooks, alertas externos, endpoints novos ou mudancas de contrato.

## CI/CD

A base de CI/CD do admin_web esta documentada em
[`docs/cicd-admin-web.md`](docs/cicd-admin-web.md). Os comandos obrigatorios de
validacao local sao:

```powershell
cd admin_web
flutter pub get
flutter analyze
flutter test
flutter build web
```

Nesta fase nao ha deploy real, secrets reais, publicacao automatica em producao
ou alteracao de infraestrutura.

## Controle de versao Android

A preparacao para controle futuro de versao Android esta documentada em
[`docs/android-version-control.md`](docs/android-version-control.md). A fase
atual apenas exibe versoes reportadas por dispositivos/sessoes quando ja
existirem no admin_web e documenta versao minima, versao recomendada, versao
instalada e atualizacao obrigatoria futura.

Nao ha enforcement real, bloqueio de app antigo, push/FCM, endpoint novo,
mudanca de contrato, alteracao no Android ou comando operacional real.

## Push Notification / FCM

A preparacao para Push Notification / FCM esta documentada em
[`docs/push-notification-fcm.md`](docs/push-notification-fcm.md). A fase atual
e apenas documental/read-only: sem envio real, sem token real, sem Firebase,
sem credenciais, sem backend, sem Android e sem contrato novo.

Qualquer envio futuro devera exigir token valido, preferencias, permissao
especifica, dry-run, motivo obrigatorio, confirmacao explicita e auditoria
backend.

## Billing

A area `/billing` e interna de plataforma/suporte. Ela consome:

- `GET /api/admin/billing/companies`
- `GET /api/admin/companies/:companyId/billing/status`
- `GET /api/admin/companies/:companyId/billing/events`
- `GET /api/admin/companies/:companyId/billing/checkout-sessions`
- `POST /api/admin/companies/:companyId/billing/refresh`
- `POST /api/admin/companies/:companyId/billing/force-plan`
- `POST /api/admin/companies/:companyId/billing/cancel-local`

Regras de seguranca no painel:

- Listagens nunca exibem `providerSubscriptionId` completo.
- Payloads/eventos sao sanitizados defensivamente antes de renderizar.
- URLs completas de checkout nao sao renderizadas nem copiaveis.
- `cancel-local` deixa claro que nao cancela Mercado Pago.
- Tokens, Authorization, webhook secrets e payloads sensiveis nao devem aparecer
  em UI ou logs.

## Licencas

A rota `/licenses` continua disponivel para consulta read-only de licencas e
assinaturas. Edicoes diretas de licenca legada exigem motivo visual local e
confirmacao final quando expostas em detalhe. Esse motivo nao e auditoria
backend, porque o endpoint legado de licenca nao aceita `reason`.

Para acoes reais de suporte de cobranca, use Billing.

## Permissoes administrativas

A rota `/permissions` consulta o catalogo e as permissoes persistidas:

- `GET /api/admin/permissions/catalog`
- `GET /api/admin/permissions/users/:adminUserId`
- `POST /api/admin/permissions/users/:adminUserId/grant`
- `POST /api/admin/permissions/users/:adminUserId/revoke`

Ela exibe o catalogo de `permissionKeys`, risco, categoria, `actionType` e
flags de dry-run, motivo, confirmacao explicita e auditoria persistente.
Tambem permite consultar permissoes persistidas por `adminUserId`.

Grant/revoke pela UI exigem motivo com pelo menos 12 caracteres, confirmacao
explicita e auditoria backend persistente. Bootstrap inicial continua restrito
ao backend/CLI controlado. A tela nao chama support-actions dry-run e nao expoe
acoes operacionais como bloqueio de usuario, revogacao de sessao, force sync,
alteracao de licenca ou envio de push.

O painel tambem deixa explicito que permissoes sao resolvidas no backend,
`permissionKeys` enviados pelo cliente nao concedem acesso e `isPlatformAdmin`
sozinho nao libera acoes sensiveis.

A UI agrupa o catalogo por categoria e risco, destaca permissionKeys de risco
alto/critico e oferece atalho para auditoria por admin. Bootstrap permanece sem
interface no Admin Web.

## Simulacoes operacionais

A Central de suporte da empresa em `/companies/:companyId/support` permite
pre-visualizar impacto e risco por meio de:

- `POST /api/admin/support-actions/dry-run`

O painel envia apenas `actionType`, `companyId`, `targetType`, `targetId`,
`reason` e `dryRun: true`. Ele nao envia `permissionKeys` nem `actorAdminId`;
autorizacao e ator autenticado sao resolvidos exclusivamente no backend.

As simulacoes nao alteram dados reais. Nao existe botao de execucao, rota de
execute ou suporte a `dryRun: false` no Admin Web. Uma futura execucao real
exigira novo epico, motivo, confirmacao explicita, permissao persistida e
auditoria backend.

O piloto backend de `revoke_session` real permanece fora da UI. A Central de
suporte mostra o gate operacional, a feature flag controlada e a observacao da
rota legada apenas como informacao read-only. O Admin Web nao chama
`POST /api/admin/support-actions/revoke-session/execute`.

## Configuracao da API

A URL base e definida por `TATUZIN_ADMIN_API_URL` via `--dart-define`. O codigo
tambem possui default de producao em `AdminEnv`, portanto um build release nao
falha apenas pela ausencia da variavel.

A URL deve incluir o prefixo `/api`, por exemplo:

```powershell
--dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

## Como rodar localmente

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port 3000 --dart-define=TATUZIN_ADMIN_API_URL=http://localhost:4000/api
```

## Build web

Build de producao para publicar o admin em `https://admin.tatuzin.com.br`:

```powershell
cd admin_web
flutter build web --release --dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

Como o projeto usa `usePathUrlStrategy()`, o servidor web precisa servir
`index.html` nas rotas profundas.

## O que este projeto nao faz

- Nao e painel owner.
- Nao executa operacao de vendas, caixa, compras ou relatorios do cliente.
- Nao substitui o app Tatuzin Android.
- Nao substitui SQLite/local-first do PDV.
- Nao transforma ERP/CRM em local-first.
- Nao consome `/api/owner/*`.
