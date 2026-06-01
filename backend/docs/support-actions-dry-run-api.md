# Support Actions Dry-Run API

Data: 2026-05-31

Esta documentacao descreve a primeira API HTTP segura para dry-run de acoes
operacionais administrativas no backend Tatuzin. A API permite consultar
impacto, riscos, entidades afetadas e auditDraft, sem executar nenhuma acao real.

## Endpoint

```http
POST /api/admin/support-actions/dry-run
```

A rota e montada dentro do `adminRouter`, portanto herda a protecao
administrativa existente:

- `requirePlatformAdmin`
- rate limit de plataforma administrativa

O dry-run continua sem executar efeito real. Existe um piloto separado,
estritamente allowlisted para `revoke_session`, documentado em
`backend/docs/support-actions-revoke-session-execution.md`. Nao existe rota
generica de confirmacao ou execucao.

## Payload

```json
{
  "actionType": "revoke_session",
  "companyId": "company-1",
  "targetType": "session",
  "targetId": "session-1",
  "reason": "Chamado de seguranca confirmado",
  "dryRun": true,
  "metadata": {
    "ticketId": "SUP-123",
    "note": "Triagem de sessao suspeita"
  }
}
```

Campos:

| Campo | Obrigatorio | Observacao |
| --- | --- | --- |
| `actionType` | sim | Tipo da acao operacional futura. |
| `companyId` | sim | Empresa alvo. |
| `targetType` | sim | Tipo do alvo operacional. |
| `targetId` | sim | Identificador do alvo. |
| `reason` | sim | Minimo de 12 caracteres, maximo de 1000. |
| `dryRun` | opcional | Se enviado, deve ser `true`; `false` e rejeitado. |
| `metadata` | nao | Dados auxiliares sanitizados no auditDraft. |

`actorAdminId` nao deve ser enviado pelo cliente. A rota usa
`request.auth.userId` extraido do contexto autenticado.

`permissionKeys` enviados pelo cliente sao ignorados. A autorizacao vem de
permissoes persistidas no backend em `AdminUserPermission`.

## Permissoes

A rota respeita a matriz de permissoes do modulo `support-actions`:

| actionType | permissionKey |
| --- | --- |
| `revoke_session` | `support.session.revoke` |
| `block_user` | `support.user.block` |
| `unblock_user` | `support.user.unblock` |
| `force_sync` | `support.sync.force` |
| `resolve_conflict` | `support.sync.conflict.resolve` |
| `update_license` | `support.license.update` |
| `update_android_version_policy` | `support.androidVersionPolicy.update` |
| `send_push_notification` | `support.push.send` |

Permissoes sao resolvidas no backend por
`SupportActionRbacService.getSupportActionPermissionContext(actorAdminId)`.

As permissoes persistidas podem ser gerenciadas pela API interna protegida:

```http
GET /api/admin/permissions/catalog
GET /api/admin/permissions/users/:adminUserId
POST /api/admin/permissions/users/:adminUserId/grant
POST /api/admin/permissions/users/:adminUserId/revoke
```

Essa API exige `admin-permissions.manage` persistida para listar, conceder e
revogar permissoes de outros admins.

`isPlatformAdmin` sozinho nao libera acao sensivel. O fallback por platform
admin depende de contexto backend explicito e nao pode ser habilitado apenas
pelo payload do cliente.

Os testes HTTP/E2E de integracao validam esse fluxo contra banco isolado:

- login real em `/api/auth/login`;
- grant persistido de `support.session.revoke`;
- dry-run permitido apenas para admin com permissao persistida;
- payload com `permissionKeys` forjado pelo cliente continua negado;
- `actorAdminId` enviado no payload e ignorado;
- auditoria de dry-run permitido e negado e persistida em `AdminAuditLog`;
- metadados sensiveis sao sanitizados.

## Resposta de sucesso

```json
{
  "ok": true,
  "code": "OPERATIONAL_ACTION_DRY_RUN_READY",
  "message": "Dry-run preparado. Nenhum dado real foi alterado.",
  "action": {
    "actionType": "revoke_session",
    "permissionKey": "support.session.revoke",
    "companyId": "company-1",
    "targetType": "session",
    "targetId": "session-1",
    "actorAdminId": "admin-1",
    "reason": "Chamado de seguranca confirmado",
    "dryRun": true,
    "confirmationRequired": true,
    "auditRequired": true,
    "auditPrepared": true,
    "auditEventId": "audit-id",
    "expectedImpact": {
      "summary": "Revogaria a sessao alvo e exigiria novo login no proximo uso.",
      "risks": ["Pode interromper um operador em atendimento."],
      "affectedEntities": [
        { "type": "session", "id": "session-1" },
        { "type": "audit", "id": "pending" }
      ],
      "confirmationRequired": true
    }
  }
}
```

## Audit draft

A resposta inclui `action.auditDraft`. Ele prepara a futura auditoria backend,
mas nao e persistido nesta etapa.

O payload seguro remove ou mascara:

- token
- authorization
- password
- secret
- cookie
- jwt
- credential
- webhook
- provider
- dados sensiveis completos

Exemplo sanitizado:

```json
{
  "safePayload": {
    "metadata": {
      "authorization": "[redacted]",
      "token": "[redacted]",
      "note": "Triagem segura"
    }
  }
}
```

## Erros esperados

### dryRun false

Status: `422`

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_VALIDATION_ERROR"
}
```

### Motivo ausente ou curto

Status: `422`

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_VALIDATION_ERROR",
  "message": "Payload de acao operacional invalido."
}
```

### Ator ausente

Status: `401`

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_ACTOR_REQUIRED",
  "message": "Ator administrativo obrigatorio para acao operacional."
}
```

### Permissao granular ausente

Status: `403`

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_MISSING_PERMISSION",
  "message": "Permissao granular ausente. isPlatformAdmin sozinho nao libera acao sensivel."
}
```

### Acao nao suportada

Status: `400`

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_UNSUPPORTED",
  "message": "Acao operacional nao suportada nesta fundacao."
}
```

### Alvo incompativel

Status: `409`

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_STATE_CONFLICT",
  "message": "Tipo de alvo incompativel com a acao operacional solicitada."
}
```

## Exemplos por actionType

### force_sync

```json
{
  "actionType": "force_sync",
  "companyId": "company-1",
  "targetType": "device",
  "targetId": "device-1",
  "reason": "Dispositivo sem sync recente confirmado em atendimento",
  "metadata": { "ticketId": "SUP-456" },
  "dryRun": true
}
```

### resolve_conflict

```json
{
  "actionType": "resolve_conflict",
  "companyId": "company-1",
  "targetType": "conflict",
  "targetId": "conflict-1",
  "reason": "Conflito validado pelo suporte com evidencia do operador"
}
```

### send_push_notification

```json
{
  "actionType": "send_push_notification",
  "companyId": "company-1",
  "targetType": "device",
  "targetId": "device-1",
  "reason": "Preparar comunicacao operacional futura ao dispositivo",
  "metadata": {
    "messagePreview": "Atualize o aplicativo para continuar usando o PDV"
  }
}
```

Este exemplo nao chama Firebase, nao envia push e nao exige token FCM real.

## Limitacoes atuais

- Este endpoint nao executa acao real.
- Persiste auditoria de dry-run em `AdminAuditLog` quando ha ator autenticado.
- Pode fornecer o `auditEventId` exigido pelo piloto separado de
  `revoke_session`.
- Nao altera billing engine.
- Nao altera sync engine.
- Nao altera Android.
- Nao altera Admin Web funcional.
- Nao configura Firebase/FCM.
- `permissionKeys` no payload nao sao fonte de autorizacao e sao ignorados.

## Execucao piloto relacionada

Para o unico caminho executavel allowlisted, consulte:

- `backend/docs/support-actions-revoke-session-execution.md`
- `backend/docs/support-actions-execution-readiness.md`

Qualquer outra execucao futura so pode evoluir depois de:

- RBAC granular persistido;
- auditoria persistida;
- confirmacao explicita por acao;
- idempotencia;
- testes de integracao em banco isolado;
- testes HTTP/E2E com autenticacao real;
- runbook operacional;
- revisao de exposicao no Admin Web.
