# Support Action Execution Pilot: revoke_session

Data: 2026-05-31

Este documento descreve o primeiro piloto de execucao real do contrato
`support-actions`. O piloto e restrito exclusivamente a `revoke_session`.
Nao existe rota generica de execucao, suporte a `dryRun=false` ou efeito real
para qualquer outro `actionType`.

## Endpoint

```http
POST /api/admin/support-actions/revoke-session/execute
```

A rota herda `requirePlatformAdmin` e rate limit do `adminRouter`. Isso nao e
suficiente para autorizar a acao: o ator autenticado tambem precisa possuir
`support.session.revoke` ativo em `AdminUserPermission`.

`actorAdminId` vem do token autenticado. Valores enviados pelo cliente sao
sobrescritos. `permissionKeys` enviados pelo cliente nao autorizam execucao.

## Rollout controlado

A execucao real e bloqueada por padrao. Para habilitar o piloto em um ambiente
autorizado:

```powershell
$env:SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED='true'
```

Se a flag estiver ausente ou for `false`, a rota retorna
`SUPPORT_ACTION_EXECUTION_DISABLED`, persiste auditoria
`support.revoke_session.execute_denied` e nao altera a sessao. O endpoint de
dry-run continua disponivel normalmente.

Habilitar a flag em producao exige decisao operacional explicita, runbook
aprovado, operadores autorizados e monitoramento ativo.

## Payload

```json
{
  "actionType": "revoke_session",
  "companyId": "company-1",
  "targetType": "session",
  "targetId": "session-1",
  "reason": "Chamado de seguranca confirmado",
  "dryRunAuditEventId": "audit-id-do-dry-run",
  "idempotencyKey": "SUP-123-revoke-session-1",
  "explicitConfirmation": true,
  "confirmationText": "REVOGAR_SESSAO",
  "metadata": {
    "ticketId": "SUP-123"
  }
}
```

## Guardrails

- Aceita apenas `actionType=revoke_session`.
- Exige `SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=true`.
- Aceita apenas `targetType=session`.
- Exige motivo com no minimo 12 caracteres.
- Exige `explicitConfirmation=true` e texto exato `REVOGAR_SESSAO`.
- Exige dry-run persistido em `AdminAuditLog`.
- O dry-run deve ter no maximo 15 minutos.
- O dry-run deve corresponder a ator, empresa, alvo e motivo.
- Revalida sessao ativa e pertencente a empresa antes do efeito.
- Exige `support.session.revoke` persistida no momento da execucao.
- Persiste recibo unico por `idempotencyKey` em `SupportActionExecution`.
- Repete resposta segura sem novo efeito quando a mesma chave ja concluiu.
- Rejeita reutilizacao da chave com payload diferente.
- Sanitiza metadados e detalhes de auditoria.

## Auditoria

Uma execucao aceita grava:

```text
support.revoke_session.execute_requested
support.revoke_session.execute_succeeded
```

Uma falha durante o efeito grava:

```text
support.revoke_session.execute_failed
```

Uma tentativa negada apos autenticacao e validacao estrutural grava:

```text
support.revoke_session.execute_denied
```

Os detalhes incluem ator, empresa, alvo, motivo sanitizado, hash da
`idempotencyKey`, a propria chave sanitizada, referencia ao dry-run, timestamp
e resultado seguro. Tokens, secrets, senhas, cookies e payload bruto perigoso
nao sao persistidos.

## Resposta de sucesso

```json
{
  "ok": true,
  "code": "SUPPORT_ACTION_EXECUTED",
  "message": "Sessao revogada com auditoria persistida.",
  "execution": {
    "id": "execution-id",
    "actionType": "revoke_session",
    "target": {
      "type": "session",
      "id": "session-1",
      "companyId": "company-1"
    },
    "result": {
      "status": "succeeded",
      "effectApplied": true
    },
    "idempotencyKey": "SUP-123-revoke-session-1",
    "correlationId": "audit-id-do-dry-run",
    "dryRunAuditEventId": "audit-id-do-dry-run",
    "auditBeforeId": "audit-before",
    "auditAfterId": "audit-after",
    "executedAt": "2026-05-31T22:30:00.000Z"
  }
}
```

Ao repetir a mesma chave e o mesmo payload, a resposta usa
`SUPPORT_ACTION_IDEMPOTENT_REPLAY`. Reutilizar a chave com payload diferente
retorna conflito.

## Erros esperados

- `SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR`: payload, motivo ou confirmacao
  invalidos.
- `SUPPORT_ACTION_EXECUTION_DISABLED`: feature flag ausente ou desligada.
- `SUPPORT_ACTION_EXECUTION_PERMISSION_DENIED`: permissao persistida ausente.
- `SUPPORT_ACTION_EXECUTION_DRY_RUN_REQUIRED`: dry-run nao encontrado.
- `SUPPORT_ACTION_EXECUTION_DRY_RUN_EXPIRED`: janela de 15 minutos encerrada.
- `SUPPORT_ACTION_EXECUTION_DRY_RUN_MISMATCH`: ator, empresa, alvo ou motivo
  divergente.
- `SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND`: sessao inexistente ou fora da
  empresa.
- `SUPPORT_ACTION_EXECUTION_STATE_CONFLICT`: sessao ja revogada ou
  `idempotencyKey` conflitante.
- `SUPPORT_ACTION_EXECUTION_UNSUPPORTED`: outro `actionType`.

## Persistencia aditiva

A migration:

```text
prisma/migrations/20260531223000_support_action_revoke_session_execution
```

adiciona `SupportActionExecution` e o enum `SupportActionExecutionStatus`.
Ela nao foi aplicada em banco real durante este epico.

## Runbook operacional

Status: pronto para aprovacao operacional. Habilitar a flag em producao exige
registrar aprovador, ambiente, janela de rollout e responsavel pelo rollback.
O registro preenchivel e os criterios de adiamento ficam em
`backend/docs/revoke-session-rollout-approval.md`.

Use somente para sessao identificada em atendimento ou incidente de seguranca.
Antes de executar:

1. Confirme que a feature flag esta habilitada no ambiente autorizado.
2. Confirme empresa, usuario e sessao alvo.
3. Gere dry-run e revise impacto, riscos e janela de 15 minutos.
4. Registre motivo e ticket.
5. Confirme com o cliente que o usuario sera desconectado e precisara
   autenticar novamente.
6. Execute com uma `idempotencyKey` unica e estavel do atendimento.
7. Verifique `execute_requested`, `execute_succeeded` e estado revogado da
   sessao.
8. Consulte o recibo `SupportActionExecution` durante auditoria posterior.

Nao use para alvo ambiguo, revogacao em massa, desconexao preventiva sem
evidencia ou substituicao de investigacao.

Ao interpretar o dry-run:

- confirme empresa, sessao, usuario e entidades afetadas;
- revise riscos e a exigencia de confirmacao;
- gere um novo dry-run quando a janela de 15 minutos expirar;
- interrompa o fluxo se o alvo, motivo ou ator divergirem.

Em caso de erro:

- nao gere chaves diferentes em sequencia sem revisar auditoria;
- repita a mesma `idempotencyKey` quando a requisicao original precisar ser
  consultada novamente;
- trate `SUPPORT_ACTION_IDEMPOTENT_REPLAY` como resultado consistente;
- em `execute_failed`, revise auditoria e estado atual da sessao antes de nova
  tentativa.

Para repetir com seguranca:

- reutilize a mesma `idempotencyKey` quando estiver consultando o mesmo pedido;
- use uma nova chave somente para uma nova decisao operacional;
- trate conflito de chave como sinal para revisar ticket, alvo e auditoria.

Para investigar incidente:

1. Correlacione ticket, `dryRunAuditEventId`, hash da `idempotencyKey` e recibo.
2. Verifique logs `requested`, `succeeded`, `failed`, `disabled`,
   `permission_denied`, `idempotent_replay` e `idempotency_conflict`.
3. Confirme o estado atual da sessao e a empresa alvo.
4. Nao exponha motivo, token, cookie, authorization ou payload bruto em logs.
5. Desligue a feature flag se houver comportamento inesperado.

Rollback operacional:

- para interromper novas execucoes, defina
  `SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=false` e reinicie o processo
  conforme o runbook do ambiente;
- uma sessao revogada nao e restaurada; a mitigacao e orientar novo login;
- desligar a flag nao remove recibos nem auditoria existentes.

## Monitoramento seguro

O servico emite logs estruturados:

```text
support.revoke_session.execution.actor_required
support.revoke_session.execution.unsupported
support.revoke_session.execution.payload_invalid
support.revoke_session.execution.disabled
support.revoke_session.execution.permission_denied
support.revoke_session.execution.dry_run_rejected
support.revoke_session.execution.target_not_found
support.revoke_session.execution.state_conflict
support.revoke_session.execution.requested
support.revoke_session.execution.succeeded
support.revoke_session.execution.failed
support.revoke_session.execution.idempotent_replay
support.revoke_session.execution.idempotency_pending
support.revoke_session.execution.idempotency_conflict
```

Os logs incluem apenas identificadores operacionais sanitizados, hash da
`idempotencyKey` e IDs de auditoria quando aplicavel. Eles nao incluem motivo,
metadata, token, cookie, senha, authorization, secret ou payload bruto.

## Rota legada revisada

A rota administrativa anterior continua existente por compatibilidade:

```http
POST /api/admin/sessions/:sessionId/revoke
```

Ela herda `requirePlatformAdmin` e grava `SessionAuditLog` pelo servico de
sessoes, mas nao exige motivo, `support.session.revoke`, dry-run correlacionado,
confirmacao textual ou `idempotencyKey`. Seu uso agora gera log seguro e
persiste em `AdminAuditLog`:

```text
admin.sessions.legacy_revoke.used
```

Os registros persistidos usam `actorType=USER`, `actorUserId` real,
`targetCompanyId` quando a sessao puder ser resolvida e detalhes sanitizados.
O campo `details.result` diferencia `requested`, `succeeded` e `failed`. A
rota continua emitindo:

```text
admin.sessions.legacy_revoke.audit_persistence_failed
admin.sessions.legacy_revoke.company_resolution_failed
```

Esses sinais complementares devem manter o gate pendente quando aparecerem.
Como a rota nao possui body e so entra no handler com `sessionId` de path,
nao foi criado evento separado de payload invalido.

Recomendacao: depreciar a rota legada em etapa propria depois de mapear
consumidores existentes. Ela nao deve ser usada como atalho para o rollout do
novo contrato.

O inventario estatico e o plano de deprecacao ficam em
`backend/docs/revoke-session-legacy-route-migration.md`. A busca encontrou um
metodo cliente disponivel no Admin Web, sem call site de UI no repositorio.
Chamadas manuais ou externas precisam ser verificadas pelo evento persistido
`admin.sessions.legacy_revoke.used` antes de qualquer bloqueio.

A rota autenticada de autoatendimento
`POST /api/auth/sessions/:sessionId/revoke` e distinta e fica fora do plano de
depreciacao administrativo.

## Checklist antes da UX

Nao criar botao real no Admin Web antes de confirmar:

- schema de `AdminAuditLog` atualizado no ambiente alvo;
- observacao valida executada em ambiente real/controlado;
- feature flag definida por ambiente;
- rota legada mapeada e plano de depreciacao aprovado;
- janela de observacao do evento `admin.sessions.legacy_revoke.used` concluida;
- runbook operacional aprovado com responsavel e data;
- auditoria before/after/denied validada;
- E2E isolado passando;
- mensagem de risco aprovada para o operador;
- texto `REVOGAR_SESSAO` mantido;
- `support.session.revoke` concedida somente a operadores autorizados;
- lista de operadores autorizados definida;
- monitoramento de logs seguro ativo e verificado.

O gate completo, incluindo janela de 7 ou 14 dias, consultas sugeridas e
registro de aprovacao humana, fica em
`backend/docs/revoke-session-rollout-approval.md`.
O runbook para aplicar migrations necessarias antes da observacao real fica em
`backend/docs/revoke-session-controlled-migration-runbook.md`.

## Fronteiras

Rotas administrativas legadas de mutacao continuam existindo por
compatibilidade, mas ficam fora deste novo contrato. O piloto nao conecta
`block_user`, `unblock_user`, sync, billing, licenca, Android ou FCM.

Nao existe UX de execucao no Admin Web nesta etapa.

## Validacao

```powershell
npx prisma generate
npx prisma validate
npx tsx --test src/modules/support-actions/*.test.ts
npm run test:integration
npm run test:integration:http
npm run build
```

As suites de integracao exigem opt-in e banco/schema isolado conforme
`backend/docs/integration-tests.md`.
