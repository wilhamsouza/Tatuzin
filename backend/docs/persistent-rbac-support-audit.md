# Persistent RBAC & Support Audit Foundation

Data: 2026-05-31

Este documento registra a base persistida de RBAC administrativo e auditoria
operacional para `support-actions`.

## Achados atuais

Antes desta etapa, o backend tinha:

- `User.isPlatformAdmin` para identificar administradores de plataforma.
- `requirePlatformAdmin` validando usuario ativo e `isPlatformAdmin=true`.
- Permissoes operacionais de funcionarios em `EmployeeProfile.permissions`.
- Auditorias existentes em `AdminAuditLog`, `BillingAdminAuditLog` e
  `SessionAuditLog`.

Nao havia uma estrutura persistida especifica para permissoes administrativas
granulares como `support.session.revoke` ou `support.sync.force`.

## Estrategia escolhida

Foi criada uma estrutura aditiva minima:

- `AdminUserPermission`

Essa tabela permite associar um usuario/admin a uma `permissionKey` granular,
com escopo generico para evolucao futura.

Campos:

| Campo | Uso |
| --- | --- |
| `id` | Identificador da permissao. |
| `actorUserId` | Usuario/admin que recebe a permissao. |
| `permissionKey` | Chave granular, como `support.session.revoke`. |
| `scope` | Escopo textual, default `platform`. |
| `scopeId` | Identificador do escopo, default `*`. |
| `isActive` | Permite revogar permissao sem apagar historico. |
| `createdAt` | Criacao do registro. |
| `updatedAt` | Atualizacao do registro. |

Migration aditiva:

- `backend/prisma/migrations/20260531170000_support_actions_rbac/migration.sql`

A migration nao remove campos, nao altera login e nao concede permissoes
automaticamente.

## Resolucao de permissao

O service responsavel e:

- `backend/src/modules/support-actions/support-actions.rbac.ts`

Funcoes:

- `getAdminPermissionKeys(actorAdminId)`
- `hasSupportActionPermission(actorAdminId, permissionKey)`
- `getSupportActionPermissionContext(actorAdminId)`

A rota de dry-run nao confia em `permissionKeys` enviados pelo cliente. Ela
extrai `actorAdminId` de `request.auth.userId`, busca permissoes persistidas e
monta o `SupportActionPermissionContext` no backend.

`isPlatformAdmin` sozinho continua insuficiente para liberar acao sensivel.

## Gestao de permissoes administrativas

A fundacao de gestao interna de `AdminUserPermission` fica em:

- `backend/src/modules/admin-permissions`

Ela permite listar permissoes conhecidas, listar permissoes persistidas de um
admin, conceder permissao e revogar permissao. O ator precisa possuir
`admin-permissions.manage`, resolvida no backend pela mesma tabela
`AdminUserPermission`.

Detalhes:

- `backend/docs/admin-permissions-management.md`

Rotas internas protegidas:

- `GET /api/admin/permissions/catalog`
- `GET /api/admin/permissions/users/:adminUserId`
- `POST /api/admin/permissions/users/:adminUserId/grant`
- `POST /api/admin/permissions/users/:adminUserId/revoke`

Essas rotas ficam atras de `requirePlatformAdmin` e usam
`admin-permissions.manage` persistida para listar, conceder e revogar
permissoes administrativas.

## Auditoria persistida

Foi adotado `AdminAuditLog` para registrar eventos de dry-run e tentativas
negadas, sem criar um log operacional novo nesta etapa.

`AdminAuditLog` recebeu um modelo aditivo de ator:

| Campo | Uso |
| --- | --- |
| `actorType` | Tipo do ator: `USER`, `SYSTEM`, `BOOTSTRAP` ou `SERVICE`. |
| `actorUserId` | Usuario autenticado quando o ator e humano; nullable para ator de sistema. |
| `actorLabel` | Rotulo opcional para ator nao humano, como `SYSTEM_BOOTSTRAP`. |

Migration aditiva:

- `backend/prisma/migrations/20260531183000_admin_audit_actor_model/migration.sql`

Logs existentes permanecem compativeis com `actorType=USER` por default.

Os testes de integracao com Prisma real para `AdminAuditLog` e
`AdminUserPermission` estao documentados em:

- `backend/docs/integration-tests.md`

Service:

- `backend/src/modules/support-actions/support-actions.audit-persistence.ts`

Eventos gravados:

- Dry-run permitido: `support.<actionType>.dry_run`
- Dry-run negado: `support.<actionType>.dry_run.denied`

Quando `actorAdminId` esta ausente em support-actions, a tentativa nao e
persistida em `AdminAuditLog`, porque nao ha usuario autenticado confiavel para
atribuir a acao. Esse comportamento e diferente do bootstrap, que possui ator
de sistema explicito.

## Payload seguro

Auditoria persistida usa o mesmo sanitizador do modulo `support-actions`.

Nunca devem ser persistidos em claro:

- token completo
- authorization
- password
- secret
- cookie
- jwt
- credential
- webhook secret
- provider IDs sensiveis completos
- payload bruto nao sanitizado

## Fluxo atual da API

`POST /api/admin/support-actions/dry-run`:

1. Herda `requirePlatformAdmin`.
2. Valida payload de dry-run.
3. Extrai `actorAdminId` do token autenticado.
4. Busca permissoes em `AdminUserPermission`.
5. Ignora qualquer `permissionKeys` enviado pelo cliente.
6. Executa apenas `buildOperationalActionDryRun`.
7. Persiste auditoria segura em `AdminAuditLog` quando ha ator.
8. Retorna `auditEventId` para dry-run permitido.
9. Nao executa acao real.

## Limitacoes atuais

- Ainda nao ha UI para gerenciar `AdminUserPermission`.
- Ainda nao ha seed automatico de permissoes sensiveis.
- Existe somente o piloto explicito
  `POST /api/admin/support-actions/revoke-session/execute`; nao existe rota
  generica de execucao nem execucao para outros `actionType`.
- Ainda nao ha confirmacao persistida de execucao.
- Ainda nao ha log operacional unificado separado de `AdminAuditLog`.
- Escopo granular usa `scope`/`scopeId`, mas a rota atual so exige a chave.

## Requisitos antes de execucao real

- UI ou processo administrativo seguro para conceder/revogar permissoes.
- Auditoria persistida para dry-run e execucao.
- Confirmacao explicita por acao.
- Idempotencia por acao.
- Testes de integracao com banco isolado.
- Runbooks operacionais.
- Revisao de exposicao no Admin Web.
