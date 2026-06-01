# Support Actions Execution Readiness

Data: 2026-05-31

Este documento registra a avaliacao de prontidao tecnica de `support-actions`.
Desde a analise inicial, um unico piloto gated foi implementado para
`revoke_session`. O documento nao libera novas acoes, nao adiciona
`dryRun=false` generico e nao substitui revisao de seguranca, testes isolados
ou runbooks aprovados.

## Estado atual

O contrato de simulacao amplo continua sendo:

```http
POST /api/admin/support-actions/dry-run
```

O dry-run exige ator autenticado, motivo, RBAC persistido por
`AdminUserPermission`, sanitizacao e auditoria em `AdminAuditLog`. O Admin Web
exibe somente simulacoes. Nao existe rota unificada de execucao real.

O unico piloto executavel e explicito:

```http
POST /api/admin/support-actions/revoke-session/execute
```

Ele exige dry-run persistido e recente, permissao `support.session.revoke`,
motivo coincidente, `explicitConfirmation=true`, confirmacao textual
`REVOGAR_SESSAO`, idempotency key,
validacao atual da sessao, auditoria before/after e a feature flag deny-by-default
`SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=true`. Consulte
`backend/docs/support-actions-revoke-session-execution.md`.

Existem rotas administrativas legadas com mutacoes reais para sessoes, acesso,
licencas e partes do Sync Center. Elas sao evidencias de servicos
reutilizaveis, nao autorizacao para conectar o novo contrato diretamente.

## Matriz de prontidao

| actionType | Permissao | Risco | Classificacao | Servico real reutilizavel | Dependencias principais | Primeira candidata |
| --- | --- | --- | --- | --- | --- | --- |
| `revoke_session` | `support.session.revoke` | high | Gated execution pilot deny-by-default | `AuthSessionService.revokeCompanySession()` | Feature flag, runbook aprovado, deprecacao da rota legada e monitoramento | piloto disponivel sob flag |
| `block_user` | `support.user.block` | critical | Ready for gated execution design | `AdminService.dryRunAccessBlock()` e `applyAccessBlock()` | Definir alvo como perfil operacional, proteger OWNER e aplicar RBAC granular | sim, depois de sessao |
| `unblock_user` | `support.user.unblock` | critical | Ready for gated execution design | `AdminService.dryRunAccessReactivate()` e `applyAccessReactivate()` | Mesmas regras de alvo, licenca, membership e RBAC granular | sim, junto de `block_user` |
| `force_sync` | `support.sync.force` | high | Needs engine integration | `SyncSupportService.adminDryRun()` e `createAdminCommand()` existem para comandos especificos | Contrato de comando, deduplicacao, TTL, consumo Android e resultado assincrono | nao |
| `resolve_conflict` | `support.sync.conflict.resolve` | critical | Too risky for now | Ha rotas de archive/reprocess e resolucao em sync, mas sem politica unificada por entidade | Politica de conciliacao, engine integration, compensacao e revisao por entidade | nao |
| `update_license` | `support.license.update` | critical | Needs backend contract | Ha `AdminService.updateLicense()` e fluxos auditados de extensao, suspensao e reativacao | Separar operacoes permitidas, integrar billing/entitlement e definir compensacao | nao |
| `update_android_version_policy` | `support.androidVersionPolicy.update` | high | Needs Android integration | Nao existe politica real no backend | Contrato, persistencia aditiva futura, bootstrap app e enforcement Android | nao |
| `send_push_notification` | `support.push.send` | high | Needs FCM integration | Nao existe FCM real | Firebase/FCM, token, preferencias, templates, privacidade e resultado assincrono | nao |

## Analise por actionType

### `revoke_session`

- Objetivo: revogar uma sessao administrativa ou operacional especifica.
- Recurso afetado: sessao autenticada.
- Servico reutilizavel: `AuthSessionService.revokeCompanySession()`.
- Migration: aditiva para `SupportActionExecution`, criada e nao aplicada em
  banco real.
- Android, FCM, billing e sync engine: sem dependencia direta.
- Reversibilidade: nao reversivel; mitigacao e novo login.
- Runbook: obrigatorio.
- Dupla confirmacao: recomendada.
- Idempotency key: obrigatoria; revogar sessao ja revogada deve retornar sucesso
  idempotente.
- Auditoria: obrigatoria antes e depois.
- Rollout: bloqueado por padrao; exige
  `SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=true`.
- Rota legada: `POST /api/admin/sessions/:sessionId/revoke` preservada por
  compatibilidade, logada e recomendada para depreciacao controlada. O
  inventario estatico e o plano por fases ficam em
  `backend/docs/revoke-session-legacy-route-migration.md`.
- Rota de autoatendimento: `POST /api/auth/sessions/:sessionId/revoke` e
  distinta e fica fora da depreciacao administrativa.
- Resultado assincrono: nao necessario na primeira versao.
- Decisao: piloto gated implementado somente no backend, sem UX de execucao.

### `block_user`

- Objetivo: bloquear acesso operacional sem apagar historico.
- Recurso afetado: perfil operacional de acesso, nao usuario global ambiguo.
- Servico reutilizavel: `AdminService.applyAccessBlock()`.
- Migration: nao identificada para o adapter inicial.
- Android, FCM, billing e sync engine: sem dependencia direta.
- Reversibilidade: reversivel por `unblock_user`.
- Runbook: obrigatorio.
- Dupla confirmacao: obrigatoria.
- Idempotency key: obrigatoria.
- Auditoria: obrigatoria antes e depois.
- Resultado assincrono: nao necessario.
- Guardrail adicional: OWNER protegido e isolamento por empresa.
- Decisao: segunda candidata, somente apos fixar semantica do alvo.

### `unblock_user`

- Objetivo: reativar acesso operacional previamente bloqueado.
- Recurso afetado: perfil operacional.
- Servico reutilizavel: `AdminService.applyAccessReactivate()`.
- Migration: nao identificada para o adapter inicial.
- Android, FCM, billing e sync engine: sem dependencia direta.
- Reversibilidade: reversivel por novo bloqueio.
- Runbook, dupla confirmacao, idempotencia e auditoria before/after:
  obrigatorios.
- Guardrail adicional: validar licenca, membership e status efetivo.
- Decisao: deve evoluir junto de `block_user`.

### `force_sync`

- Objetivo: solicitar sincronizacao controlada para dispositivo ou contexto de
  sync.
- Recurso afetado: dispositivo, fila de comandos e processamento Android.
- Servico reutilizavel: `SyncSupportService.createAdminCommand()` pode inspirar
  o adapter; nao e ainda o contrato unificado.
- Migration: possivelmente nao, se a fila atual for suficiente; validar antes.
- Android: necessario para consumo e confirmacao do comando.
- Sync engine: necessario.
- Reversibilidade: limitada; comando ainda nao consumido pode expirar.
- Runbook, dupla confirmacao, idempotencia e auditoria before/after:
  obrigatorios.
- Resultado assincrono: obrigatorio, com estado enfileirado, consumido, concluido,
  expirado ou falhou.
- Decisao: adiar ate contrato de fila, TTL e resultado assincrono.

### `resolve_conflict`

- Objetivo: resolver conflito especifico com politica por entidade.
- Recurso afetado: conflito e leitura operacional potencialmente financeira.
- Servico reutilizavel: existem fluxos de archive/reprocess e
  `SyncConflictService.resolve()`, mas nao ha politica unificada segura.
- Migration: avaliar apos desenhar historico de resolucao e compensacao.
- Sync engine: dependencia forte.
- Reversibilidade: nao garantida; exige compensacao por entidade.
- Runbook e dupla confirmacao: obrigatorios, com revisao humana adicional.
- Idempotency key e auditoria before/after: obrigatorias.
- Resultado assincrono: recomendado.
- Decisao: Too risky for now. Manter apenas dry-run e documentacao.

### `update_license`

- Objetivo: alterar licenca ou politica de acesso com escopo explicito.
- Recurso afetado: licenca, entitlement e potencialmente billing.
- Servicos reutilizaveis: patch legado e fluxos auditados de extensao,
  suspensao e reativacao em `BillingAdminService`.
- Migration: nao necessariamente, mas o novo contrato deve ser definido antes.
- Billing engine: dependencia obrigatoria quando houver reflexo financeiro.
- Reversibilidade: depende da operacao; suspensao e reativacao sao
  compensaveis, alteracao de plano pode exigir reconciliacao.
- Runbook, dupla confirmacao, idempotencia e auditoria before/after:
  obrigatorios.
- Decisao: nao expor acao generica. Criar subacoes permitidas em epico proprio.

### `update_android_version_policy`

- Objetivo: configurar versao minima, recomendada e politica de enforcement.
- Recurso afetado: politica de plataforma ou empresa.
- Servico reutilizavel: nao identificado.
- Migration: provavelmente aditiva, apos aprovar contrato.
- Android: dependencia obrigatoria para reportar versao, exibir mensagem e
  aplicar enforcement.
- Reversibilidade: sim, por nova politica.
- Runbook, dupla confirmacao, idempotencia e auditoria before/after:
  obrigatorios.
- Resultado assincrono: recomendado para medir adocao.
- Decisao: Needs Android integration.

### `send_push_notification`

- Objetivo: enviar comunicacao operacional para dispositivo, usuario ou
  empresa.
- Recurso afetado: audiencia, template, token e provedor FCM.
- Servico reutilizavel: nao identificado.
- Migration: possivelmente aditiva para tokens, preferencias e historico.
- Android e Firebase/FCM: dependencias obrigatorias.
- Reversibilidade: nao; mensagem enviada nao pode ser recolhida.
- Runbook e dupla confirmacao: obrigatorios.
- Idempotency key e auditoria before/after: obrigatorias.
- Resultado assincrono: obrigatorio, incluindo aceito, entregue quando
  disponivel, falhou e token invalido.
- Decisao: Needs FCM integration.

## Ordem recomendada

1. `revoke_session`
2. `block_user` e `unblock_user`
3. `force_sync`, somente depois do contrato Android de comandos e resultado
   assincrono
4. `update_android_version_policy`, depois do contrato backend + Android
5. `update_license`, dividido em subacoes explicitas e revisado com billing
6. `send_push_notification`, depois da integracao FCM completa
7. `resolve_conflict`, mantido por ultimo devido ao risco operacional

Essa ordem difere da hipotese inicial porque politica Android ainda nao possui
servico real, enquanto existe uma fundacao parcial de comandos de sync. Mesmo
assim, `force_sync` nao deve ser liberado antes da integracao Android.

## Contrato obrigatorio de execucao

O piloto de `revoke_session` aplica este contrato. Qualquer rota futura de
execucao real tambem deve exigir:

- dry-run previo persistido;
- `dryRunId` ou `correlationId` emitido pelo backend;
- `idempotencyKey`;
- `reason` obrigatorio;
- `explicitConfirmation` por actionType;
- permissao persistida correspondente;
- `actorAdminId` extraido do token, nunca do cliente;
- validacao de empresa e alvo novamente no momento da execucao;
- auditoria before com payload sanitizado;
- auditoria after com resultado padronizado;
- erro seguro sem stack trace ou payload bruto;
- rollback ou compensacao quando aplicavel;
- feature flag para rollout inicial;
- expiracao do dry-run para impedir confirmacao tardia.

Resposta minima futura:

```json
{
  "ok": true,
  "code": "OPERATIONAL_ACTION_EXECUTED",
  "correlationId": "support-action-id",
  "idempotencyKey": "request-id",
  "auditBeforeEventId": "audit-before",
  "auditAfterEventId": "audit-after",
  "result": {
    "status": "completed",
    "message": "Resultado seguro."
  }
}
```

## Runbooks iniciais

| Acao | Quando usar | Quando nao usar | Validacoes antes | Confirmacao com cliente | Verificar resultado | Reverter ou mitigar |
| --- | --- | --- | --- | --- | --- | --- |
| `revoke_session` | Sessao suspeita ou dispositivo perdido | Sessao nao identificada | Empresa, sessao ativa, usuario e impacto | Confirmar interrupcao e novo login | Sessao revogada e novo acesso exige login | Orientar novo login |
| `block_user` | Comprometimento ou desligamento operacional | OWNER ou alvo ambiguo | Perfil, empresa, papel, status e sessoes | Confirmar bloqueio de acesso | Perfil desativado sem apagar historico | `unblock_user` |
| `unblock_user` | Reativacao aprovada | Licenca ou membership invalida | Motivo anterior, papel e status | Confirmar restauracao de acesso | Perfil ativo com papel preservado | `block_user` |
| `force_sync` | Fila parada confirmada | Uso em massa ou conflito nao entendido | Dispositivo, diagnostico, TTL e fila | Confirmar janela operacional | Comando consumido e resultado final | Expirar comando e investigar |
| `resolve_conflict` | Politica por entidade aprovada | Venda, caixa ou estoque sem conciliacao | Payload sanitizado, entidade e evidencia | Confirmacao formal | Conflito resolvido e materializacao coerente | Compensacao manual aprovada |
| `update_license` | Ajuste explicitamente permitido | Alteracao financeira generica | Plano, entitlement, billing e vigencia | Confirmar impacto comercial | Licenca e billing reconciliados | Subacao compensatoria |
| `update_android_version_policy` | Rollout planejado | Sem cobertura Android medida | Versoes, mensagem, janela e rollback | Confirmar impacto nos dispositivos | Bootstrap/app aplica politica | Publicar politica menos restritiva |
| `send_push_notification` | Template aprovado e audiencia valida | Conteudo sensivel ou audiencia ampla sem revisao | Template, audiencia, preferencias e tokens | Aprovar mensagem final | Resultado por provedor e falhas | Mensagem corretiva, se necessario |

## Criterios minimos antes da UI de execucao

Nenhum botao real deve entrar no Admin Web antes de:

- rota backend de execucao protegida;
- adapter especifico por `actionType`;
- dry-run persistido e expiravel;
- auditoria persistida before/after;
- idempotencia testada;
- permissao granular persistida;
- motivo obrigatorio;
- confirmacao explicita;
- mensagem de risco;
- rota legada mapeada;
- janela de observacao de `admin.sessions.legacy_revoke.used`;
- runbook aprovado com responsavel e data;
- operadores com `support.session.revoke` definidos;
- logs seguros verificados;
- feature flag quando aplicavel;
- testes unitarios;
- testes Prisma em banco isolado;
- E2E HTTP com autenticacao real;
- teste de repeticao da mesma `idempotencyKey`;
- teste provando que `permissionKeys` e `actorAdminId` do cliente nao autorizam.

Para `revoke_session`, o gate preenchivel de observacao e aprovacao fica em
`backend/docs/revoke-session-rollout-approval.md`.

## Proximos epicos recomendados

1. Rollout controlado e monitoramento do piloto `revoke_session`.
2. Access block/unblock adapter with OWNER protection.
3. Feature flag e politica operacional para futuros adapters.
4. Android command consumption contract for `force_sync`.
5. Android version policy backend + Android integration.
6. License support-actions decomposition with billing review.
7. FCM backend + Android integration.
8. Conflict-resolution policy by entity.

## Confirmacoes de escopo

- Somente a rota explicita
  `POST /api/admin/support-actions/revoke-session/execute` foi criada.
- Nenhuma rota generica de execucao e nenhum suporte a `dryRun=false` foram
  criados.
- Nenhum botao de execucao foi criado no Admin Web.
- A migration aditiva do recibo idempotente foi criada, mas nao aplicada em
  banco real.
- Nenhuma acao destrutiva foi executada durante a implementacao.
- Nenhum Android, Firebase/FCM, billing engine ou sync engine foi alterado.
