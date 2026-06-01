# Backend Support Actions Foundation

Data: 2026-05-31

Este documento define a fundacao backend para futuras acoes reais de suporte
operacional no Tatuzin. A primeira etapa cria contrato, tipos, validacoes,
dry-run e payload seguro para auditoria futura, mas nao cria rota HTTP publica
de execucao nem executa efeito destrutivo. A rota HTTP segura de dry-run foi
adicionada posteriormente e esta documentada em
`backend/docs/support-actions-dry-run-api.md`.

Depois dessa fundacao, um piloto gated e estritamente isolado foi adicionado
somente para `revoke_session`. Consulte
`backend/docs/support-actions-revoke-session-execution.md`. As demais acoes
continuam em dry-run.

## Objetivo

Preparar um padrao unico para acoes operacionais sensiveis, com:

- `dry-run` obrigatorio nesta fase.
- motivo obrigatorio.
- confirmacao explicita futura.
- impacto estimado.
- riscos e entidades afetadas.
- payload seguro para auditoria.
- respostas padronizadas.
- integracao futura com permissao e auditoria backend.

## Acoes mapeadas

Tipos iniciais de acao:

| actionType | Status nesta etapa | Observacao |
| --- | --- | --- |
| `revoke_session` | Dry-run + piloto gated | Execucao real isolada e auditada em rota explicita. |
| `block_user` | Dry-run apenas | Preparacao para bloquear usuario/acesso. |
| `unblock_user` | Dry-run apenas | Preparacao para reativar usuario/acesso. |
| `force_sync` | Dry-run apenas | Preparacao para solicitar sync controlado. |
| `resolve_conflict` | Dry-run apenas | Preparacao para resolver conflito de sync. |
| `update_license` | Dry-run apenas | Preparacao para ajuste de licenca. |
| `update_android_version_policy` | Dry-run apenas | Preparacao para politica de versao Android. |
| `send_push_notification` | Dry-run apenas | Preparacao para push futuro, sem Firebase/FCM real. |

Na fundacao original nenhum desses tipos executava alteracao real. Atualmente,
somente `revoke_session` possui piloto executavel allowlisted.

## Contrato base

Toda acao operacional deve convergir para a estrutura abaixo:

```json
{
  "actionType": "revoke_session",
  "companyId": "company-1",
  "targetType": "session",
  "targetId": "session-1",
  "actorAdminId": "admin-1",
  "reason": "Chamado de seguranca confirmado",
  "dryRun": true,
  "confirmationRequired": true,
  "expectedImpact": {
    "summary": "Revogaria a sessao alvo e exigiria novo login no proximo uso.",
    "risks": ["Pode interromper um operador em atendimento."],
    "affectedEntities": [
      { "type": "session", "id": "session-1" },
      { "type": "audit", "id": "pending" }
    ],
    "confirmationRequired": true
  },
  "result": {
    "status": "dry_run_ready",
    "code": "OPERATIONAL_ACTION_DRY_RUN_READY",
    "message": "Dry-run preparado. Nenhum dado real foi alterado."
  },
  "auditEventId": null,
  "createdAt": "2026-05-31T12:00:00.000Z"
}
```

O contrato TypeScript vive em:

- `backend/src/modules/support-actions/support-actions.types.ts`
- `backend/src/modules/support-actions/support-actions.schemas.ts`
- `backend/src/modules/support-actions/support-actions.service.ts`

A matriz de permissoes granulares e a politica de auditoria obrigatoria estao
documentadas em:

- `backend/docs/admin-permissions-audit-enforcement.md`

A primeira API HTTP de dry-run esta documentada em:

- `backend/docs/support-actions-dry-run-api.md`

A analise tecnica para futura execucao real esta documentada em:

- `backend/docs/support-actions-execution-readiness.md`

O piloto gated de `revoke_session` esta documentado em:

- `backend/docs/support-actions-revoke-session-execution.md`

A base persistida de RBAC administrativo e auditoria operacional esta
documentada em:

- `backend/docs/persistent-rbac-support-audit.md`

## Fluxo recomendado

1. Admin solicita dry-run.
2. Backend valida `actionType`, empresa, alvo, ator e motivo.
3. Backend valida permissao granular por `permissionKey`.
4. Backend calcula impacto estimado sem alterar estado.
5. Backend retorna riscos, entidades afetadas e confirmacao esperada.
6. UI mostra impacto, riscos e confirmacao.
7. Futuramente, admin confirma explicitamente.
8. Backend executa acao real apenas se o contrato da acao existir.
9. Backend registra auditoria completa.

Para todos os tipos exceto `revoke_session`, o fluxo continua parando no
dry-run preparado. O piloto de sessao segue contrato proprio e rota explicita.

## Payload de dry-run

Exemplo:

```json
{
  "actionType": "force_sync",
  "companyId": "company-1",
  "targetType": "device",
  "targetId": "device-1",
  "actorAdminId": "admin-1",
  "reason": "Dispositivo com fila parada validada pelo suporte",
  "dryRun": true,
  "metadata": {
    "ticketId": "SUP-123",
    "note": "Cliente reportou atraso de sincronizacao"
  }
}
```

Campos obrigatorios:

- `actionType`
- `companyId`
- `targetType`
- `targetId`
- `actorAdminId`
- `reason`
- `dryRun=true`

`reason` deve ter pelo menos 12 caracteres e no maximo 1000 caracteres.

## Respostas padronizadas

### Sucesso de dry-run

```json
{
  "ok": true,
  "code": "OPERATIONAL_ACTION_DRY_RUN_READY",
  "message": "Dry-run preparado. Nenhum dado real foi alterado.",
  "action": {}
}
```

### Erro de validacao

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_VALIDATION_ERROR",
  "message": "Payload de acao operacional invalido.",
  "error": {
    "code": "OPERATIONAL_ACTION_VALIDATION_ERROR",
    "message": "Payload de acao operacional invalido."
  }
}
```

### Ausencia de permissao futura

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_PERMISSION_REQUIRED",
  "message": "Permissao especifica sera exigida antes da execucao real."
}
```

### Alvo nao encontrado

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_TARGET_NOT_FOUND",
  "message": "Alvo operacional nao encontrado."
}
```

### Acao nao suportada

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_UNSUPPORTED",
  "message": "Acao operacional nao suportada nesta fundacao."
}
```

### Conflito de estado

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_STATE_CONFLICT",
  "message": "Tipo de alvo incompativel com a acao operacional solicitada."
}
```

### Erro interno seguro

```json
{
  "ok": false,
  "code": "OPERATIONAL_ACTION_INTERNAL_ERROR",
  "message": "Erro interno ao preparar acao operacional."
}
```

## Auditoria preparada

Cada dry-run gera um `auditDraft`, sem persistir no banco nesta etapa:

```json
{
  "actorAdminId": "admin-1",
  "companyId": "company-1",
  "actionType": "revoke_session",
  "targetType": "session",
  "targetId": "session-1",
  "dryRun": true,
  "reason": "Chamado de seguranca confirmado",
  "result": {
    "status": "dry_run_ready",
    "code": "OPERATIONAL_ACTION_DRY_RUN_READY"
  },
  "safePayload": {},
  "createdAt": "2026-05-31T12:00:00.000Z"
}
```

O payload seguro remove ou mascara chaves com indicios de:

- authorization
- password
- secret
- token
- jwt
- cookie
- provider
- webhook
- credential
- refresh/access token
- card

Quando a execucao real for implementada, esse draft deve ser persistido em
auditoria backend. Como ja existem `AdminAuditLog`, `BillingAdminAuditLog` e
`SessionAuditLog`, a proxima etapa deve decidir se cria um log operacional
unificado ou se integra com os logs existentes. Isso pode exigir migration
futura, mas nenhuma migration foi criada nesta etapa.

## Requisitos de seguranca

- Nao aceitar execucao real sem dry-run anterior.
- Exigir permissao granular por acao.
- Exigir motivo obrigatorio.
- Exigir confirmacao explicita por tipo de acao.
- Sanitizar payload antes de UI, logs ou auditoria.
- Nao registrar tokens, cookies, secrets, provider IDs completos ou payloads
  sensiveis.
- Nao expor acao real no Admin Web antes de backend, auditoria e runbooks.

## Validacao segura

Teste unitario isolado:

```powershell
cd backend
npx tsx --test src/modules/support-actions/support-actions.service.test.ts
```

Validacao de tipos:

```powershell
cd backend
npm run build
```

Validacao Prisma sem migration:

```powershell
cd backend
npx prisma validate
```

`npm test` completo deve rodar apenas contra banco local/teste isolado, porque a
suite backend existente cria e apaga dados via Prisma.
