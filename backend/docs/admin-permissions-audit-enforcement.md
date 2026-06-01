# Admin Permissions & Audit Enforcement

Data: 2026-05-31

Este documento define a base de permissoes granulares e auditoria obrigatoria
para futuras acoes operacionais administrativas no backend Tatuzin. A etapa
atual prepara governanca, contratos internos e um modelo explicito de ator de
auditoria. Depois desta fundacao, foi criado um unico piloto executavel
allowlisted para `revoke_session`; nao existe rota generica de execucao.

## Objetivo

Toda acao operacional sensivel deve seguir um fluxo padrao:

1. Verificar ator administrativo.
2. Verificar permissao granular por `permissionKey`.
3. Preparar dry-run sem alteracao real.
4. Retornar impacto, riscos e entidades afetadas.
5. Exigir confirmacao explicita futura.
6. Executar acao real somente em etapa posterior.
7. Persistir auditoria backend antes/depois conforme contrato da acao.

Para todos os tipos exceto o piloto `revoke_session`, o fluxo para no dry-run
preparado.

A rota HTTP de dry-run inicial esta documentada em:

- `backend/docs/support-actions-dry-run-api.md`

O piloto gated de sessao esta documentado em:

- `backend/docs/support-actions-revoke-session-execution.md`

A base persistida de RBAC e auditoria de dry-run esta documentada em:

- `backend/docs/persistent-rbac-support-audit.md`

A fundacao interna para conceder, revogar e consultar permissoes
administrativas persistidas esta documentada em:

- `backend/docs/admin-permissions-management.md`

Rotas internas protegidas de gestao:

- `GET /api/admin/permissions/catalog`
- `GET /api/admin/permissions/users/:adminUserId`
- `POST /api/admin/permissions/users/:adminUserId/grant`
- `POST /api/admin/permissions/users/:adminUserId/revoke`

O bootstrap excepcional da primeira permissao `admin-permissions.manage`, sem
rota HTTP e sem UX, esta documentado em:

- `backend/docs/admin-permissions-bootstrap.md`

A fundacao de testes de integracao com Prisma real esta documentada em:

- `backend/docs/integration-tests.md`

## Por que isPlatformAdmin nao basta

`isPlatformAdmin` identifica um usuario administrativo da plataforma, mas nao
expressa autorizacao por acao. Acoes como bloquear usuario, alterar licenca,
resolver conflito de sync ou enviar push futuro tem riscos diferentes.

Por isso, o modulo `support-actions` agora usa `permissionKey` granular. O
fallback por `isPlatformAdmin` existe apenas como mecanismo temporario
explicitamente habilitado no helper de permissao, e nao deve ser usado como
politica de producao para acoes sensiveis.

## Matriz de permissoes

| actionType | permissionKey | Escopos | Risco | Dry-run | Confirmacao | Motivo | Auditoria persistida |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `revoke_session` | `support.session.revoke` | platform, company, user, device | high | sim | sim | sim | sim |
| `block_user` | `support.user.block` | platform, company, user | critical | sim | sim | sim | sim |
| `unblock_user` | `support.user.unblock` | platform, company, user | critical | sim | sim | sim | sim |
| `force_sync` | `support.sync.force` | platform, company, device, sync | high | sim | sim | sim | sim |
| `resolve_conflict` | `support.sync.conflict.resolve` | platform, company, sync | critical | sim | sim | sim | sim |
| `update_license` | `support.license.update` | platform, company, billing | critical | sim | sim | sim | sim |
| `update_android_version_policy` | `support.androidVersionPolicy.update` | platform, company, android_version | high | sim | sim | sim | sim |
| `send_push_notification` | `support.push.send` | platform, company, user, device, fcm | high | sim | sim | sim | sim |

A matriz vive em:

- `backend/src/modules/support-actions/support-actions.permissions.ts`

## Tipos internos

Tipos principais:

- `SupportActionPermission`
- `SupportActionPermissionKey`
- `SupportActionPermissionDecision`
- `SupportActionPermissionContext`
- `OperationalActionAuditDraft`

A decisao de permissao retorna:

```json
{
  "allowed": false,
  "denied": true,
  "reason": "Permissao granular ausente. isPlatformAdmin sozinho nao libera acao sensivel.",
  "missingPermission": "support.session.revoke",
  "requiredPermission": {
    "actionType": "revoke_session",
    "permissionKey": "support.session.revoke"
  },
  "actionType": "revoke_session"
}
```

## Contexto de permissao

Exemplo interno permitido:

```json
{
  "actorAdminId": "admin-1",
  "permissionKeys": ["support.session.revoke"],
  "isPlatformAdmin": true
}
```

Exemplo interno negado:

```json
{
  "actorAdminId": "admin-1",
  "permissionKeys": [],
  "isPlatformAdmin": true
}
```

Mesmo com `isPlatformAdmin=true`, a acao e negada quando a permissionKey
granular nao existe. Na rota HTTP, essas permissionKeys sao resolvidas no
backend a partir de `AdminUserPermission`; o cliente nao e fonte confiavel.

Para gerenciar `AdminUserPermission`, o ator precisa da permissao persistida
`admin-permissions.manage`. Essa permissao tambem nao e substituida por
`isPlatformAdmin`.

Para criar a primeira permissao `admin-permissions.manage`, existe apenas o
script CLI de bootstrap controlado por `ADMIN_PERMISSION_BOOTSTRAP_ENABLED=true`.
Ele nao cria bypass permanente para `isPlatformAdmin` e nao aceita
`permissionKeys` do cliente como autorizacao.

Fallback temporario documentado para uso interno:

```json
{
  "actorAdminId": "admin-1",
  "isPlatformAdmin": true,
  "allowPlatformAdminFallback": true
}
```

Esse fallback nao e habilitado por payload do cliente e deve ser removido ou
bloqueado antes de producao para acoes reais.

## Auditoria obrigatoria

O draft de auditoria operacional contem:

- `actorAdminId`
- `companyId`
- `actionType`
- `permissionKey`
- `targetType`
- `targetId`
- `reason`
- `dryRun`
- `confirmationRequired`
- `result`
- `safePayload`
- `riskLevel`
- `affectedEntities`
- `createdAt`
- `errorCode`, se houver
- `errorMessage`, se houver

Exemplo:

```json
{
  "actorAdminId": "admin-1",
  "companyId": "company-1",
  "actionType": "revoke_session",
  "permissionKey": "support.session.revoke",
  "targetType": "session",
  "targetId": "session-1",
  "dryRun": true,
  "confirmationRequired": true,
  "reason": "Chamado de seguranca confirmado",
  "riskLevel": "high",
  "safePayload": {
    "metadata": {
      "authorization": "[redacted]"
    }
  },
  "createdAt": "2026-05-31T12:00:00.000Z"
}
```

## Integracao com auditoria existente

O Prisma ja possui estruturas de auditoria:

- `AdminAuditLog`
- `BillingAdminAuditLog`
- `SessionAuditLog`

Foi criado um mapper seguro para o formato existente de `AdminAuditLog`:

- `mapSupportActionAuditToAdminAuditLog`

Tambem foi criado `SupportActionAuditPersistenceService` para persistir eventos
de dry-run e tentativas negadas quando ha `actorAdminId` seguro.

`AdminAuditLog` foi endurecido de forma aditiva para diferenciar atores humanos
e de sistema:

| Campo | Uso |
| --- | --- |
| `actorType` | `USER`, `SYSTEM`, `BOOTSTRAP` ou `SERVICE`. |
| `actorUserId` | Usuario real quando `actorType=USER`; nullable para atores de sistema. |
| `actorLabel` | Rotulo opcional para atores nao humanos, como `SYSTEM_BOOTSTRAP`. |

Registros antigos continuam compativeis porque `actorType` possui default
`USER` e `actorUserId` existente e preservado.

Formato mapeado:

```json
{
  "actorType": "USER",
  "actorUserId": "admin-1",
  "actorLabel": null,
  "targetCompanyId": "company-1",
  "action": "support.revoke_session.dry_run",
  "details": {
    "actionType": "revoke_session",
    "permissionKey": "support.session.revoke",
    "targetType": "session",
    "targetId": "session-1"
  }
}
```

Persistencia real deve ser implementada somente quando as rotas reais forem
criadas e a politica de auditoria estiver fechada. Se um log operacional
unificado for necessario, isso deve entrar em migration futura nao destrutiva.

Para bootstrap de permissao administrativa, o ator e registrado explicitamente
como `actorType=BOOTSTRAP`, `actorUserId=null` e
`actorLabel=SYSTEM_BOOTSTRAP`. O payload mantem `details.systemActor` apenas
como informacao redundante e legivel.

## Respostas padronizadas

Codigos preparados:

- `OPERATIONAL_ACTION_DRY_RUN_READY`
- `OPERATIONAL_ACTION_VALIDATION_ERROR`
- `OPERATIONAL_ACTION_PERMISSION_REQUIRED`
- `OPERATIONAL_ACTION_PERMISSION_DENIED`
- `OPERATIONAL_ACTION_MISSING_PERMISSION`
- `OPERATIONAL_ACTION_TARGET_NOT_FOUND`
- `OPERATIONAL_ACTION_UNSUPPORTED`
- `OPERATIONAL_ACTION_STATE_CONFLICT`
- `OPERATIONAL_ACTION_AUDIT_REQUIRED`
- `OPERATIONAL_ACTION_AUDIT_PAYLOAD_INVALID`
- `OPERATIONAL_ACTION_ACTOR_REQUIRED`
- `OPERATIONAL_ACTION_INTERNAL_ERROR`

Exemplo de permissao ausente:

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_MISSING_PERMISSION",
  "message": "Permissao granular ausente. isPlatformAdmin sozinho nao libera acao sensivel.",
  "error": {
    "code": "OPERATIONAL_ACTION_MISSING_PERMISSION",
    "message": "Permissao granular ausente. isPlatformAdmin sozinho nao libera acao sensivel."
  }
}
```

Exemplo de ator ausente:

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_ACTOR_REQUIRED",
  "message": "Ator administrativo obrigatorio para acao operacional."
}
```

## O que ainda nao foi implementado

- Rota HTTP publica para dry-run.
- Rota HTTP publica para execucao real.
- UI no Admin Web.
- Comandos destrutivos reais.
- Firebase/FCM real.
- Politica Android real.
- Migration para log operacional unificado.

## O que nao deve ser exposto ao Admin Web ainda

- Botao de bloquear usuario.
- Botao de revogar sessao.
- Botao de forcar sync.
- Botao de resolver conflito.
- Botao de alterar licenca.
- Politica Android mutavel.
- Envio real de push.

Antes de expor qualquer item acima, o backend deve ter:

- permissao granular persistida;
- auditoria persistida;
- dry-run por rota;
- confirmacao explicita por acao;
- runbook operacional;
- testes de integracao contra banco isolado.

## Validacao segura

Comandos desta etapa:

```powershell
cd backend
npx tsx --test src/modules/support-actions/support-actions.service.test.ts
npm run build
npx prisma validate
```

`npm test` completo continua restrito a banco local/teste isolado confirmado,
porque a suite existente cria e apaga dados via Prisma.

Testes de integracao com Prisma real devem ser executados apenas com opt-in:

```powershell
$env:RUN_INTEGRATION_TESTS='true'
$env:INTEGRATION_TEST_DATABASE_URL='postgresql://postgres:postgres@localhost:5432/simples_erp_integration_test?schema=integration_test'
npm run test:integration
```
