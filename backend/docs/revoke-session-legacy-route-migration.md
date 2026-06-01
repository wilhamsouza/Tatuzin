# Revoke Session Legacy Route Migration

Data: 2026-05-31

Este documento registra o inventario da rota administrativa legada de
revogacao de sessao e o plano de depreciacao controlada. Ele nao remove,
bloqueia ou altera a rota existente.

## Rotas separadas

| Rota | Papel atual | Entra neste plano |
| --- | --- | --- |
| `POST /api/admin/support-actions/revoke-session/execute` | Piloto seguro de execucao real, bloqueado por padrao pela feature flag | Destino da migracao |
| `POST /api/admin/sessions/:sessionId/revoke` | Rota administrativa legada preservada por compatibilidade | Sim |
| `POST /api/auth/sessions/:sessionId/revoke` | Autoatendimento autenticado para revogar uma sessao propria | Nao |

A rota em `/api/auth/sessions/:sessionId/revoke` possui caminho parecido, mas
nao e um bypass administrativo e nao deve ser removida ou migrada junto com a
rota legada.

## Metodo da busca

Foi feita busca estatica no repositorio por:

```text
POST /api/admin/sessions/:sessionId/revoke
/admin/sessions
sessions/:sessionId/revoke
legacy_revoke
revoke session
revokeSession
revokeSessionAsPlatformAdmin
```

A busca estatica identifica codigo, testes e documentacao versionados. Ela nao
prova ausencia de chamadas manuais, clientes externos, ferramentas locais nao
versionadas ou integracoes fora deste repositorio. Antes de bloquear ou remover
a rota, e obrigatorio consultar em `AdminAuditLog` o evento:

```text
admin.sessions.legacy_revoke.used
```

## Consumidores mapeados

| Arquivo | Tipo de consumidor | Ambiente provavel | Pode migrar | Risco de remocao | Acao recomendada |
| --- | --- | --- | --- | --- | --- |
| `backend/src/modules/admin/admin.routes.ts` | Definicao HTTP da rota legada | Todos | Sim, depois da janela de observacao | Alto | Manter auditada nesta fase. Nao remover nem bloquear ainda. |
| `backend/src/modules/admin/admin.service.ts` | Wrapper interno chamado pela rota legada | Todos | Sim | Medio | Manter isolado como legado ate retirar a rota. Nao reutilizar em UX nova. |
| `backend/src/modules/auth/auth-session.service.ts` | Implementacao `revokeSessionAsPlatformAdmin()` usada pelo wrapper legado | Todos | Sim | Medio | Manter enquanto a compatibilidade existir. A rota nova ja usa a variante com empresa validada. |
| `admin_web/lib/src/core/network/admin_api_service.dart` | Metodo cliente `revokeSession()` disponivel no SDK web | Admin Web | Sim, com o contrato seguro da rota nova | Medio | Nao ha call site encontrado na UI. Marcar para migracao apenas quando uma UX real for aprovada. |
| `admin_web/docs/api-contracts.md` | Referencia documental ao metodo cliente | Desenvolvimento | Sim | Baixo | Atualizar quando a migracao da UX for aprovada. |
| `backend/docs/support-actions-revoke-session-execution.md` | Referencia documental | Desenvolvimento e operacao | Sim | Baixo | Manter apontando para este inventario e para o runbook. |
| `backend/docs/support-actions-execution-readiness.md` | Referencia documental | Desenvolvimento e operacao | Sim | Baixo | Manter checklist de decisao antes da UX. |
| `backend/README.md` | Referencia documental | Desenvolvimento | Sim | Baixo | Manter link para este inventario. |

## Consumidores nao encontrados na busca estatica

Nao foram encontrados call sites internos ativos para o metodo
`AdminApiService.revokeSession()`. Tambem nao foram encontradas referencias
diretas a rota administrativa legada em:

- `owner_web`;
- Android;
- scripts versionados;
- testes automatizados;
- integracoes internas versionadas.

Chamadas manuais ou externas permanecem classificadas como desconhecidas ate
que a observacao de runtime seja concluida.

## Comparacao de seguranca

| Controle | Rota legada | Rota segura |
| --- | --- | --- |
| `requirePlatformAdmin` | Sim | Sim |
| Permissao persistida `support.session.revoke` | Nao | Sim |
| Motivo obrigatorio | Nao | Sim |
| Dry-run persistido e recente | Nao | Sim |
| Confirmacao explicita | Nao | Sim |
| Texto `REVOGAR_SESSAO` | Nao | Sim |
| `idempotencyKey` | Nao | Sim |
| Recibo `SupportActionExecution` | Nao | Sim |
| Auditoria persistida | `admin.sessions.legacy_revoke.used` com resultado em `details` | Eventos before/after/denied |
| Log seguro de uso | `admin.sessions.legacy_revoke.used` e falhas de persistencia | Logs estruturados do piloto |

A rota legada nao deve ser usada como atalho para a UX futura.

## Plano de depreciacao

### Fase 1: manter auditada

- Preservar a rota legada.
- Manter `admin.sessions.legacy_revoke.used`.
- Consultar registros persistidos em `AdminAuditLog`.
- Monitorar `admin.sessions.legacy_revoke.audit_persistence_failed`.
- Nao criar novos consumidores.
- Direcionar qualquer integracao nova para a rota segura.

### Fase 2: observar e alertar consumidores

- Definir janela de observacao por ambiente.
- Contabilizar ocorrencias do evento legado por ator, ambiente e periodo.
- Identificar proprietario de cada consumidor observado.
- Comunicar a deprecacao e o contrato de substituicao.

### Fase 3: migrar consumidores

- Migrar somente consumidores identificados.
- Exigir o fluxo `dry-run -> confirmacao -> execute`.
- Exigir `support.session.revoke`, motivo, `REVOGAR_SESSAO` e
  `idempotencyKey`.
- Validar E2E em banco isolado antes de habilitar cada consumidor.

### Fase 4: bloquear em ambiente controlado

- Bloquear primeiro em ambiente nao produtivo.
- Verificar ausencia de regressao e de novos eventos legados.
- Definir rollback operacional antes de ampliar o bloqueio.
- Nao bloquear producao sem decisao operacional registrada.

### Fase 5: remover ou manter atras de flag

- Remover a rota somente com evidencia de ausencia de consumidores.
- Como alternativa temporaria, mante-la atras de flag deny-by-default.
- Registrar decisao, responsavel, data e plano de rollback.

## Evidencia necessaria antes do bloqueio

Registrar por ambiente:

| Campo | Preenchimento esperado |
| --- | --- |
| Janela observada | Data inicial e final |
| Quantidade de eventos legados | Total por ambiente |
| Atores identificados | IDs sanitizados ou classificacao do consumidor |
| Chamadas externas ou manuais | Proprietario e fluxo de migracao |
| Decisao | Manter, migrar, bloquear ou remover |
| Aprovador | Responsavel operacional |
| Rollback | Flag ou restauracao da rota |

## Janela de observacao e gate

A janela recomendada e:

- 7 dias corridos em ambiente interno com operadores conhecidos;
- 14 dias corridos quando houver operadores externos ou chamadas manuais;
- janela maior quando a origem for incerta ou os logs estiverem incompletos.

Antes de iniciar uma janela valida em ambiente real/controlado, confirmar que
`AdminAuditLog` possui `actorType`, `actorLabel` e `actorUserId` nullable
quando aplicavel. A observacao local de desenvolvimento executada em
`2026-06-01` nao aprova UX real porque o schema local ainda nao continha as
colunas aditivas de ator. A aplicacao controlada dessas migrations deve seguir
`backend/docs/revoke-session-controlled-migration-runbook.md`.

O checklist preenchivel, as consultas sugeridas e o registro de aprovacao
operacional ficam em
`backend/docs/revoke-session-rollout-approval.md`.

## Estado da decisao

O inventario estatico esta concluido. A rota legada permanece preservada e
auditada. Bloqueio ou remocao dependem da observacao de runtime e de aprovacao
operacional explicita.
