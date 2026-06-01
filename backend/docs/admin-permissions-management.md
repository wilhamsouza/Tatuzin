# Admin Permissions Management

Data: 2026-05-31

Este documento descreve a fundacao backend para conceder, revogar e consultar
`AdminUserPermission` em ambiente controlado. Esta etapa inclui service interno,
testes e API administrativa protegida, mas nao cria UX no Admin Web e nao cria
execucao real de support-actions.

## Objetivo

Permitir que o backend tenha uma base segura para gerenciar permissoes
administrativas persistidas antes de qualquer execucao real de support-actions.

## Modulo

Arquivos:

- `backend/src/modules/admin-permissions/admin-permissions.catalog.ts`
- `backend/src/modules/admin-permissions/admin-permissions.bootstrap.ts`
- `backend/src/modules/admin-permissions/admin-permissions.routes.ts`
- `backend/src/modules/admin-permissions/admin-permissions.schemas.ts`
- `backend/src/modules/admin-permissions/admin-permissions.service.ts`
- `backend/src/modules/admin-permissions/admin-permissions.types.ts`
- `backend/src/modules/admin-permissions/index.ts`

## Permissao de gerenciamento

A permissao exigida para conceder, revogar e listar permissoes persistidas de
outro admin e:

```text
admin-permissions.manage
```

Essa permissao tambem e persistida em `AdminUserPermission`. `isPlatformAdmin`
continua insuficiente sozinho.

## Funcoes do service

`AdminPermissionsService` implementa:

- `listKnownPermissions()`
- `listAdminPermissions(actorAdminId, targetAdminId)`
- `grantPermission(actorAdminId, targetAdminId, permissionKey, reason)`
- `revokePermission(actorAdminId, targetAdminId, permissionKey, reason)`

O service nao recebe permissionKeys do cliente como autorizacao. Ele consulta as
permissoes persistidas do ator no backend.

## API administrativa

As rotas ficam sob `adminRouter`, portanto herdam `requirePlatformAdmin`, rate
limit administrativo e ator autenticado por `request.auth.userId`.

Endpoints:

```http
GET /api/admin/permissions/catalog
GET /api/admin/permissions/users/:adminUserId
POST /api/admin/permissions/users/:adminUserId/grant
POST /api/admin/permissions/users/:adminUserId/revoke
```

`GET /api/admin/permissions/catalog` retorna o catalogo read-only de permissoes
conhecidas.

`GET /api/admin/permissions/users/:adminUserId` lista permissoes persistidas e
ativas de um AdminUser. O ator precisa possuir `admin-permissions.manage`.

Payload de grant/revoke:

```json
{
  "permissionKey": "support.session.revoke",
  "reason": "Concessao aprovada em chamado",
  "scope": "platform",
  "scopeId": "*"
}
```

Campos:

| Campo | Obrigatorio | Observacao |
| --- | --- | --- |
| `permissionKey` | sim | Precisa existir no catalogo conhecido. |
| `reason` | sim | Minimo de 12 caracteres. |
| `scope` | nao | Default `platform`. |
| `scopeId` | nao | Default `*`. |

As rotas nao aceitam `actorAdminId` do cliente. O ator vem do token
autenticado. As rotas tambem nao aceitam `permissionKeys` do cliente como
autorizacao.

Os testes HTTP/E2E de integracao exercitam essas rotas por meio de login real
em `/api/auth/login`, passando pelo `requirePlatformAdmin` e pelo rate limit do
`adminRouter`. Esses testes sao opt-in e exigem banco/schema isolado.

Grant permitido:

```json
{
  "ok": true,
  "code": "ADMIN_PERMISSION_GRANTED",
  "message": "Permissao administrativa concedida.",
  "auditEventId": "audit-id"
}
```

Revoke permitido:

```json
{
  "ok": true,
  "code": "ADMIN_PERMISSION_REVOKED",
  "message": "Permissao administrativa revogada.",
  "details": {
    "revokedCount": 1
  }
}
```

Sem permissao de gestao:

```json
{
  "ok": false,
  "code": "ADMIN_PERMISSION_MANAGE_REQUIRED",
  "message": "Permissao admin-permissions.manage obrigatoria para gerenciar permissoes administrativas."
}
```

PermissionKey desconhecida:

```json
{
  "ok": false,
  "code": "ADMIN_PERMISSION_UNSUPPORTED",
  "message": "Permissao administrativa nao suportada."
}
```

## Permissoes conhecidas

O catalogo inclui:

- `admin-permissions.manage`
- `support.session.revoke`
- `support.user.block`
- `support.user.unblock`
- `support.sync.force`
- `support.sync.conflict.resolve`
- `support.license.update`
- `support.androidVersionPolicy.update`
- `support.push.send`

Permissoes desconhecidas sao rejeitadas.

O catalogo HTTP expoe, quando aplicavel:

- `permissionKey`;
- `description`;
- `category`;
- `riskLevel`;
- `scopes`;
- `actionType`;
- `requiresDryRun`;
- `requiresReason`;
- `requiresPersistentAudit`;
- `requiresExplicitConfirmation`.

## Autoelevacao

Por padrao, um admin nao pode conceder permissoes criticas a si mesmo. Isso
inclui permissoes `high` ou `critical`, como:

- `admin-permissions.manage`
- `support.license.update`
- `support.sync.conflict.resolve`
- `support.user.block`
- `support.user.unblock`

Qualquer excecao futura deve ser documentada, auditada e executada por processo
operacional separado.

## Bootstrap inicial

A primeira concessao de `admin-permissions.manage` nao pode depender do proprio
`AdminPermissionsService`, porque ainda nao existe ator com permissao de gestao.

Para isso existe um bootstrap excepcional, sem rota HTTP e sem UX:

- `backend/scripts/bootstrap-admin-permission.ts`
- `backend/src/modules/admin-permissions/admin-permissions.bootstrap.ts`
- `backend/docs/admin-permissions-bootstrap.md`

O bootstrap exige `ADMIN_PERMISSION_BOOTSTRAP_ENABLED=true`, motivo obrigatorio,
alvo explicito e AdminUser existente. Ele permite apenas
`admin-permissions.manage` e bloqueia a execucao se qualquer manager ativo ja
existir.

Nao ha `--force` por padrao.

Na auditoria, o bootstrap usa ator explicito de sistema:

- `actorType=BOOTSTRAP`
- `actorUserId=null`
- `actorLabel=SYSTEM_BOOTSTRAP`

## Auditoria

O service persiste auditoria em `AdminAuditLog` quando ha ator autenticado.

Acoes:

- `admin.permission.list`
- `admin.permission.list.denied`
- `admin.permission.grant`
- `admin.permission.grant.denied`
- `admin.permission.revoke`
- `admin.permission.revoke.denied`
- `admin_permissions.bootstrap.attempted`
- `admin_permissions.bootstrap.granted`
- `admin_permissions.bootstrap.denied`

O payload de auditoria inclui:

- ator;
- alvo;
- permissao;
- acao;
- resultado;
- motivo quando aplicavel;
- metadados seguros.

Tentativas com payload invalido, permissionKey desconhecida, concessao
duplicada idempotente e revogacao inexistente sao tratadas de forma segura.
Sempre que houver ator autenticado, tentativas negadas sao auditadas.

O payload e sanitizado com o sanitizador de `support-actions`, removendo tokens,
authorization, password, secret, cookie, jwt, credential e termos sensiveis.

## O que ainda nao existe

- UX no Admin Web.
- Execucao real de support-actions.
- Processo operacional final de aprovacao humana para uso do bootstrap em
  ambiente real.

## Requisitos antes de UX

- Validar permissao persistida do ator no backend.
- Manter bloqueio de autoelevacao critica.
- Auditar todas as tentativas permitidas e negadas.
- Rodar testes de integracao com banco isolado, incluindo
  `npm run test:integration:http`.
