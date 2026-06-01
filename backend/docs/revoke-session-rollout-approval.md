# Revoke Session Rollout Observation & Approval Gate

Data: 2026-05-31

Este documento define a etapa obrigatoria de observacao e aprovacao operacional
antes de criar qualquer UX real de execucao de `revoke_session` no Admin Web.
Ele nao habilita feature flag, nao altera rotas e nao substitui o runbook.

## Estado atual

Status do gate: `EM OBSERVACAO`.

Migrations necessarias aplicadas em `2026-06-01T03:19:35Z` no banco
local/controlado de observacao (`localhost:5432/simples_erp_dev`, schema
`public`). O schema foi validado com `actorType`, `actorLabel`,
`actorUserId` nullable, `AdminUserPermission` e `SupportActionExecution`.

Janela valida em andamento: de `2026-06-01T00:19:35-03:00` a
`2026-06-08T00:19:35-03:00`. A UX real continua bloqueada ate a janela
completa terminar e os demais criterios operacionais serem aprovados.

Ultima observacao executada: `2026-06-01`, em leitura somente, contra
`DATABASE_URL` local/controlado de observacao (`localhost`, banco
`simples_erp_dev`, schema `public`). A linha de base pos-migration encontrou
zero eventos legados e zero eventos modernos, mas ainda nao conclui a janela de
7 dias.

Proxima etapa obrigatoria: executar observacao em ambiente real/controlado
durante a janela completa, confirmar retencao consultavel, responsaveis e
politica da feature flag. A aplicacao de migrations seguiu
`backend/docs/revoke-session-controlled-migration-runbook.md`.

A rota segura continua bloqueada por padrao:

```http
POST /api/admin/support-actions/revoke-session/execute
```

A rota administrativa legada permanece preservada:

```http
POST /api/admin/sessions/:sessionId/revoke
```

A rota autenticada de autoatendimento abaixo e distinta e fica fora deste
gate:

```http
POST /api/auth/sessions/:sessionId/revoke
```

## Janela recomendada de observacao

Use uma janela continua por ambiente:

| Cenario | Janela minima recomendada | Observacao |
| --- | --- | --- |
| Ambiente interno com operadores conhecidos | 7 dias corridos | Suficiente somente quando os fluxos manuais estiverem inventariados. |
| Operadores externos, suporte terceirizado ou chamadas manuais | 14 dias corridos | Preferir uma janela que inclua dias uteis e fim de semana. |
| Origem incerta, log incompleto ou uso esporadico | Maior que 14 dias | Manter o gate pendente ate obter evidencia confiavel. |

A janela deve observar:

```text
admin.sessions.legacy_revoke.used
```

O evento legado agora e persistido em `AdminAuditLog`. O campo
`details.result` diferencia `requested`, `succeeded` e `failed`.

Para validar o piloto novo em ambiente controlado, observar tambem:

```text
support.revoke_session.execute_requested
support.revoke_session.execute_succeeded
support.revoke_session.execute_failed
support.revoke_session.execute_denied
```

## Checklist de observacao

Preencher por ambiente:

| Pergunta | Resultado | Evidencia ou observacao |
| --- | --- | --- |
| Houve uso da rota legada? | Pendente | Total de `admin.sessions.legacy_revoke.used`. |
| Qual ator ou admin chamou? | Pendente | IDs sanitizados e responsavel identificado. |
| Qual foi a origem provavel? | Pendente | UI, chamada manual, script, integracao externa ou desconhecida. |
| Houve erro associado? | Pendente | Correlacionar timestamp, ator e sessao sem expor dados sensiveis. |
| Houve uso manual? | Pendente | Registrar ferramenta, responsavel e procedimento. |
| Houve uso por script? | Pendente | Registrar proprietario e caminho de migracao. |
| O metodo dormente do Admin Web foi utilizado? | Pendente | A busca estatica nao encontrou call site; validar runtime. |
| A rota nova foi testada com flag ligada em ambiente controlado? | Pendente | Registrar ambiente, data e resultado E2E. |
| A auditoria before/after/denied da rota nova foi consultada? | Pendente | Registrar IDs de auditoria sanitizados. |
| Os logs seguros foram verificados? | Pendente | Confirmar ausencia de token, cookie, authorization, senha e secret. |

## Prontidao para observacao real/controlada

Esta secao define as pre-condicoes antes de iniciar uma janela valida de
observacao em ambiente real ou controlado. Ela nao autoriza deploy, nao aplica
migration e nao habilita execucao real.

### Pre-condicao de schema

O ambiente alvo deve estar alinhado ao modelo atual de `AdminAuditLog`:

| Campo | Obrigatorio para observacao valida | Observacao |
| --- | --- | --- |
| `AdminAuditLog.actorType` | Sim | Deve existir para diferenciar `USER`, `SYSTEM`, `BOOTSTRAP` e `SERVICE`. |
| `AdminAuditLog.actorLabel` | Sim | Necessario para atores nao humanos e compatibilidade operacional. |
| `AdminAuditLog.actorUserId` nullable | Sim, quando a migration aditiva permitir | Necessario para logs de sistema sem ancora tecnica enganosa. |
| `AdminAuditLog.action` | Sim | Deve permitir filtrar `admin.sessions.legacy_revoke.used` e eventos `support.revoke_session.execute_*`. |
| `AdminAuditLog.details` | Sim | Deve conter payload sanitizado com `details.result`, alvo e origem. |

Validacao read-only sugerida para o ambiente alvo:

```sql
SELECT
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_name = 'AdminAuditLog'
  AND column_name IN (
    'actorType',
    'actorLabel',
    'actorUserId',
    'action',
    'details',
    'createdAt'
  )
ORDER BY ordinal_position;
```

O gate permanece `PENDENTE` se `actorType` ou `actorLabel` estiverem ausentes,
ou se `actorUserId` ainda for obrigatorio em um ambiente que precise registrar
atores nao humanos.

### Checklist antes da observacao real

Preencher antes de abrir a janela:

| Item | Status | Evidencia exigida |
| --- | --- | --- |
| Migration aditiva aplicada no ambiente alvo | Pendente | Registro operacional ou saida de status de migration. |
| Backup ou snapshot revisado, quando aplicavel | Pendente | Referencia do snapshot, janela e responsavel. |
| `npx prisma validate` executado contra o schema do codigo | Pendente | Comando e resultado. |
| `AdminAuditLog` recebe novos eventos | Pendente | Evento controlado nao destrutivo ou evidencia recente. |
| Retencao consultavel confirmada | Pendente | Periodo de retencao e ferramenta de consulta. |
| Janela definida | Pendente | 7, 14 ou mais dias, com timezone e ambiente. |
| Responsavel tecnico definido | Pendente | Nome ou identificador interno. |
| Responsavel operacional definido | Pendente | Nome ou identificador interno. |
| Politica da feature flag definida | Pendente | Quem pode habilitar, onde, quando e como reverter. |
| Operadores autorizados revisados | Pendente | Lista de operadores com `support.session.revoke`. |
| Runbook aprovado | Pendente | Data, responsaveis e criterio de rollback. |

### Plano de migration em ambiente controlado

Antes de uma observacao valida, aplicar migrations apenas pelo runbook oficial
do ambiente alvo:

1. Confirmar que a migration e aditiva e ja passou por validacao tecnica.
2. Confirmar backup ou snapshot quando a politica do ambiente exigir.
3. Executar status de migrations com credenciais operacionais aprovadas.
4. Aplicar migration somente durante janela autorizada.
5. Validar as colunas de `AdminAuditLog` com consulta read-only.
6. Confirmar que eventos novos podem ser consultados.
7. Registrar responsavel tecnico, responsavel operacional, data e ambiente.

Nao aplicar migration a partir deste documento. Este plano apenas define a
pre-condicao para a janela real. O runbook detalhado fica em
`backend/docs/revoke-session-controlled-migration-runbook.md`.

## Migration controlada e baseline em 2026-06-01

### Ambiente

| Campo | Valor |
| --- | --- |
| Banco/schema | `localhost:5432/simples_erp_dev?schema=public` |
| Tipo de ambiente | Local/controlado de observacao |
| Migration aplicada automaticamente em producao | Nao |
| Feature flag habilitada | Nao |
| UX real criada | Nao |

### Migrations aplicadas

| Migration | `finished_at` | Resultado |
| --- | --- | --- |
| `20260531170000_support_actions_rbac` | `2026-06-01T03:19:35.570Z` | Aplicada |
| `20260531183000_admin_audit_actor_model` | `2026-06-01T03:19:35.598Z` | Aplicada |
| `20260531223000_support_action_revoke_session_execution` | `2026-06-01T03:19:35.630Z` | Aplicada |

### Schema validado

| Item | Resultado |
| --- | --- |
| `AdminAuditLog.actorType` | Existe, `NOT NULL`, default `USER` |
| `AdminAuditLog.actorLabel` | Existe, nullable |
| `AdminAuditLog.actorUserId` | Existe, nullable |
| `AdminUserPermission` | Existe |
| `SupportActionExecution` | Existe |
| `npx prisma migrate status` | Database schema is up to date |
| `npx prisma validate` | Passou |
| `npx prisma generate` | Passou |
| `npm run build` | Passou |
| Testes focados | 17 testes passaram |

### Baseline pos-migration

Consulta read-only executada de `2026-06-01T03:19:35.630Z` a
`2026-06-01T03:22:26.320Z`.

Eventos legados encontrados em `AdminAuditLog`:

| `details.result` | Total |
| --- | ---: |
| `requested` | 0 |
| `succeeded` | 0 |
| `failed` | 0 |
| `denied` | 0 |
| outro ou ausente | 0 |

Eventos da rota moderna encontrados em `AdminAuditLog`:

| Evento | Total |
| --- | ---: |
| `support.revoke_session.execute_requested` | 0 |
| `support.revoke_session.execute_succeeded` | 0 |
| `support.revoke_session.execute_failed` | 0 |
| `support.revoke_session.execute_denied` | 0 |

Outros achados:

- `SupportActionExecution`: 0 recibos.
- atores observados: nenhum;
- empresas observadas: nenhuma;
- sessoes afetadas: nenhuma;
- consumidor inesperado: nenhum observado no baseline pos-migration.

### Decisao atual

Decisao do gate: `EM OBSERVACAO`.

Motivo: schema corrigido e baseline limpo no ambiente local/controlado, mas a
janela valida de 7 dias ainda nao terminou. A UX real no Admin Web continua
bloqueada ate a conclusao da janela, aprovacao do runbook, politica da feature
flag e operadores autorizados.

## Observacao local anterior em 2026-06-01

### Janela

| Campo | Valor |
| --- | --- |
| Tipo de janela | 7 dias corridos |
| Timezone operacional | `America/Sao_Paulo` |
| Inicio local | `2026-05-25T00:00:00-03:00` |
| Fim local | `2026-06-01T00:00:00-03:00` |
| Inicio UTC consultado | `2026-05-25T03:00:00.000Z` |
| Fim UTC consultado | `2026-06-01T03:00:00.000Z` |
| Fonte consultada | `DATABASE_URL` local de desenvolvimento |
| Banco/schema | `localhost:5432/simples_erp_dev?schema=public` |
| Tipo de acesso | Consulta read-only |

### Resultado da consulta

Eventos legados encontrados em `AdminAuditLog`:

| `details.result` | Total |
| --- | ---: |
| `requested` | 0 |
| `succeeded` | 0 |
| `failed` | 0 |
| outro ou ausente | 0 |

Eventos da rota moderna encontrados em `AdminAuditLog`:

| Evento | Total |
| --- | ---: |
| `support.revoke_session.execute_requested` | 0 |
| `support.revoke_session.execute_succeeded` | 0 |
| `support.revoke_session.execute_failed` | 0 |
| `support.revoke_session.execute_denied` | 0 |

### Consumidores observados

Nenhum consumidor foi observado nesta janela local:

- atores/admins: nenhum;
- empresas: nenhuma;
- sessoes: nenhuma;
- origem provavel: sem eventos;
- consumidor inesperado: nao observado nesta fonte.

### Lacunas da observacao

- A fonte disponivel foi banco local de desenvolvimento, nao ambiente
  operacional aprovado.
- `AdminAuditLog` nessa fonte possui apenas `id`, `actorUserId`,
  `targetCompanyId`, `action`, `details` e `createdAt`.
- As colunas aditivas `actorType` e `actorLabel` ainda nao estao aplicadas
  nesse banco local.
- A ausencia de eventos em banco local nao prova ausencia de chamadas manuais,
  externas ou de outro ambiente.

### Conclusao da observacao local anterior

Decisao anterior do gate: `PENDENTE`.

Motivo: nao houve uso legado observado na fonte local consultada, mas a janela
nao cobre um ambiente operacional aprovado e o schema local nao esta alinhado
com o modelo atual de auditoria. A UX real no Admin Web continua bloqueada ate
que uma janela seja executada em ambiente controlado com migrations aditivas
aplicadas e auditoria consultavel.

## Consultas operacionais sugeridas

### Rota legada: Prisma sobre AdminAuditLog

O uso da rota legada e persistido em `AdminAuditLog`. Exemplo Prisma-style
para relatorio controlado:

```ts
const legacyEvents = await prisma.adminAuditLog.findMany({
  where: {
    action: "admin.sessions.legacy_revoke.used",
    createdAt: { gte: observationStart, lt: observationEnd },
  },
  select: {
    id: true,
    actorType: true,
    actorUserId: true,
    targetCompanyId: true,
    details: true,
    createdAt: true,
  },
  orderBy: { createdAt: "asc" },
});
```

Exemplo pseudo-SQL equivalente:

```sql
SELECT
  "id",
  "actorType",
  "actorUserId",
  "targetCompanyId",
  "details",
  "createdAt"
FROM "AdminAuditLog"
WHERE "action" = 'admin.sessions.legacy_revoke.used'
  AND "createdAt" >= :observation_start
  AND "createdAt" < :observation_end
ORDER BY "createdAt" ASC;
```

Para separar por resultado:

```sql
SELECT
  COALESCE("details"->>'result', 'other') AS result,
  COUNT(*) AS total
FROM "AdminAuditLog"
WHERE "action" = 'admin.sessions.legacy_revoke.used'
  AND "createdAt" >= :observation_start
  AND "createdAt" < :observation_end
GROUP BY COALESCE("details"->>'result', 'other')
ORDER BY result ASC;
```

Os detalhes persistidos incluem apenas alvo sanitizado, origem
`legacy_route`, recomendacao de migracao, timestamp e resultado seguro. O
`targetCompanyId` e preenchido quando a sessao puder ser resolvida.

### Rota legada: logs estruturados complementares

O log estruturado `admin.sessions.legacy_revoke.used` continua sendo emitido.
Consultar tambem:

```text
admin.sessions.legacy_revoke.audit_persistence_failed
admin.sessions.legacy_revoke.company_resolution_failed
```

Se houver falha de persistencia ou se `AdminAuditLog` nao puder ser consultado,
o gate deve permanecer pendente ate investigar a lacuna.

### Rota nova: Prisma sobre AdminAuditLog

Os eventos da rota nova sao persistidos em `AdminAuditLog`. Exemplo
Prisma-style para relatorio controlado:

```ts
const actions = [
  "support.revoke_session.execute_requested",
  "support.revoke_session.execute_succeeded",
  "support.revoke_session.execute_failed",
  "support.revoke_session.execute_denied",
];

const events = await prisma.adminAuditLog.findMany({
  where: {
    action: { in: actions },
    createdAt: { gte: observationStart, lt: observationEnd },
  },
  select: {
    id: true,
    action: true,
    actorType: true,
    actorUserId: true,
    targetCompanyId: true,
    details: true,
    createdAt: true,
  },
  orderBy: { createdAt: "asc" },
});
```

Exemplo pseudo-SQL equivalente:

```sql
SELECT
  "id",
  "action",
  "actorType",
  "actorUserId",
  "targetCompanyId",
  "createdAt"
FROM "AdminAuditLog"
WHERE "action" IN (
  'support.revoke_session.execute_requested',
  'support.revoke_session.execute_succeeded',
  'support.revoke_session.execute_failed',
  'support.revoke_session.execute_denied'
)
  AND "createdAt" >= :observation_start
  AND "createdAt" < :observation_end
ORDER BY "createdAt" ASC;
```

Para comparar contagem da rota moderna por evento:

```sql
SELECT
  "action",
  COUNT(*) AS total
FROM "AdminAuditLog"
WHERE "action" IN (
  'support.revoke_session.execute_requested',
  'support.revoke_session.execute_succeeded',
  'support.revoke_session.execute_failed',
  'support.revoke_session.execute_denied'
)
  AND "createdAt" >= :observation_start
  AND "createdAt" < :observation_end
GROUP BY "action"
ORDER BY "action" ASC;
```

Consultar `details` somente em ambiente controlado. Nao exportar motivo,
payload bruto ou identificadores alem do necessario para a investigacao.

### Recibos idempotentes

Quando necessario, correlacionar a auditoria da rota nova com
`SupportActionExecution` usando `dryRunAuditEventId`, `beforeAuditEventId` e
`afterAuditEventId`. Nao usar a `idempotencyKey` bruta em logs externos;
preferir o hash sanitizado registrado nos eventos operacionais.

## Registro de aprovacao operacional

Preencher antes de liberar UX real:

| Campo | Valor |
| --- | --- |
| Status | `PENDENTE` |
| Responsavel tecnico | Pendente |
| Responsavel de suporte ou operacao | Pendente |
| Data da aprovacao | Pendente |
| Ambiente aprovado | Pendente |
| Janela de observacao concluida | Pendente |
| Feature flag prevista | `SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=true` somente no ambiente aprovado |
| Operadores autorizados | Pendente |
| Concessoes de `support.session.revoke` verificadas | Pendente |
| Mensagem de risco aprovada | Pendente |
| Criterio de rollback | Definir flag como `false`, reiniciar conforme runbook do ambiente e interromper novas execucoes |
| Evidencia E2E isolada | Pendente |
| Evidencia de auditoria | Pendente |
| Plano para rota legada | Pendente |

O preenchimento do registro exige decisao humana. Criar ou atualizar este
documento nao equivale a aprovacao operacional.

## Gate para UX real no Admin Web

A UX real so pode ser criada quando todos os itens abaixo estiverem atendidos:

- observacao feita no ambiente real/controlado correto;
- schema de `AdminAuditLog` atualizado e validado;
- janela de observacao concluida;
- consumidores legados inexistentes ou mapeados com proprietario e plano;
- runbook aprovado;
- feature flag documentada por ambiente;
- operadores autorizados definidos;
- `support.session.revoke` concedida somente aos operadores autorizados;
- E2E de `revoke_session` passando em banco isolado;
- auditoria before/after/denied verificada;
- logs seguros consultaveis e verificados;
- mensagem de risco aprovada;
- confirmacao textual `REVOGAR_SESSAO` mantida;
- `idempotencyKey` mantida;
- plano de migracao da rota legada definido.

## Criterios de adiamento

Adiar a UX real se qualquer item abaixo ocorrer:

- observacao feita apenas em banco local/dev;
- schema sem `actorType`, `actorLabel` ou `actorUserId` nullable quando aplicavel;
- rota legada com uso desconhecido;
- logs ausentes, incompletos ou sem retencao adequada;
- falhas de persistencia `admin.sessions.legacy_revoke.audit_persistence_failed`;
- runbook sem responsavel tecnico ou operacional;
- operadores autorizados nao definidos;
- concessoes de `support.session.revoke` nao revisadas;
- feature flag sem politica por ambiente;
- auditoria da rota nova indisponivel para consulta;
- E2E isolado falhando;
- mensagem de risco ainda nao aprovada;
- plano da rota legada ainda indefinido.

## Resultado esperado da observacao

Ao final da janela, registrar:

1. periodo e ambientes observados;
2. total de eventos legados;
3. consumidores identificados e respectivos proprietarios;
4. evidencias do piloto novo em ambiente controlado;
5. decisao de aprovar, adiar ou ampliar a observacao;
6. aprovadores e criterio de rollback.
