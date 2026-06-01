# Revoke Session Controlled Migration Runbook

Data: 2026-06-01

Este runbook prepara a aplicacao controlada de migrations necessarias para uma
janela valida de observacao de `revoke_session`. Ele nao aplica migration por
si so, nao habilita feature flag e nao autoriza UX real no Admin Web.

## Objetivo

Atualizar um ambiente real/controlado para que a observacao da rota legada e do
piloto seguro de `revoke_session` seja consultavel por `AdminAuditLog` e
`SupportActionExecution`, preservando compatibilidade e mantendo a execucao real
bloqueada por padrao.

## Ambiente alvo

Preencher antes de qualquer comando operacional:

| Campo | Valor |
| --- | --- |
| Ambiente | Pendente |
| Banco/schema | Pendente |
| Janela operacional | Pendente |
| Responsavel tecnico | Pendente |
| Responsavel operacional | Pendente |
| Responsavel por rollback | Pendente |
| Backup ou snapshot | Pendente |
| Ticket/mudanca | Pendente |

## Migrations relevantes

| Migration | Finalidade | Obrigatoria para o rollout |
| --- | --- | --- |
| `20260402163000_phase17_admin_license_cloud` | Cria a base de `AdminAuditLog` usada pelo admin. | Baseline esperado em ambientes com Admin Web. |
| `20260531170000_support_actions_rbac` | Cria `AdminUserPermission` para RBAC persistido. | Sim. |
| `20260531183000_admin_audit_actor_model` | Adiciona `actorType`, `actorLabel` e torna `actorUserId` nullable em `AdminAuditLog`. | Sim. |
| `20260531223000_support_action_revoke_session_execution` | Cria `SupportActionExecution` e recibos idempotentes do piloto. | Sim. |

A migration de ator de auditoria e aditiva, mas altera nulabilidade de
`actorUserId`. Revisar a politica do ambiente antes da aplicacao.

## Pre-check antes da migration

Executar apenas com credenciais aprovadas para o ambiente alvo. Nao imprimir
secrets nem URLs completas em logs compartilhados.

1. Confirmar repositorio e versao do codigo:

```powershell
git status --short
git rev-parse --short HEAD
npx prisma validate
```

2. Confirmar que a conexao aponta para o ambiente correto sem expor segredo:

```sql
SELECT
  current_database() AS database_name,
  current_schema() AS schema_name,
  inet_server_addr() AS server_addr,
  inet_server_port() AS server_port;
```

3. Verificar status de migrations:

```powershell
npx prisma migrate status --schema prisma/schema.prisma
```

4. Verificar migrations relevantes ja aplicadas:

```sql
SELECT
  migration_name,
  finished_at,
  rolled_back_at
FROM "_prisma_migrations"
WHERE migration_name IN (
  '20260402163000_phase17_admin_license_cloud',
  '20260531170000_support_actions_rbac',
  '20260531183000_admin_audit_actor_model',
  '20260531223000_support_action_revoke_session_execution'
)
ORDER BY migration_name ASC;
```

5. Verificar schema atual de `AdminAuditLog`:

```sql
SELECT
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_name = 'AdminAuditLog'
  AND column_name IN (
    'id',
    'actorType',
    'actorUserId',
    'actorLabel',
    'targetCompanyId',
    'action',
    'details',
    'createdAt'
  )
ORDER BY ordinal_position;
```

6. Verificar se `AdminUserPermission` e `SupportActionExecution` existem:

```sql
SELECT
  table_name
FROM information_schema.tables
WHERE table_name IN ('AdminUserPermission', 'SupportActionExecution')
ORDER BY table_name ASC;
```

7. Confirmar backup ou snapshot:

```text
Backup/snapshot: PENDENTE
Responsavel: PENDENTE
Retencao esperada: PENDENTE
Procedimento de restore testado: PENDENTE
```

Abortar antes da migration se o banco/schema nao for o ambiente esperado, se
backup/snapshot aplicavel nao estiver confirmado, se `npx prisma validate`
falhar ou se houver migrations desconhecidas pendentes.

## Aplicacao controlada

Executar somente durante janela aprovada e por operador autorizado:

```powershell
npx prisma migrate deploy --schema prisma/schema.prisma
```

Nao usar `prisma migrate dev` em ambiente real/controlado. Nao executar seed,
reset, scripts destrutivos ou comandos de reparo fora do runbook do ambiente.

A feature flag deve permanecer desligada:

```text
SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=false
```

## Post-check depois da migration

1. Confirmar que Prisma reconhece o schema:

```powershell
npx prisma validate
npx prisma migrate status --schema prisma/schema.prisma
```

2. Confirmar colunas de `AdminAuditLog`:

```sql
SELECT
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_name = 'AdminAuditLog'
  AND column_name IN ('actorType', 'actorLabel', 'actorUserId')
ORDER BY column_name ASC;
```

Resultado esperado:

| Coluna | Esperado |
| --- | --- |
| `actorType` | Existe, default `USER` no modelo/migration |
| `actorLabel` | Existe, nullable |
| `actorUserId` | Existe e aceita `NULL` |

3. Confirmar tabela de recibos idempotentes:

```sql
SELECT
  table_name
FROM information_schema.tables
WHERE table_name = 'SupportActionExecution';
```

4. Confirmar indices principais:

```sql
SELECT
  indexname
FROM pg_indexes
WHERE tablename IN ('AdminAuditLog', 'AdminUserPermission', 'SupportActionExecution')
  AND indexname IN (
    'AdminAuditLog_actorType_idx',
    'AdminAuditLog_actorUserId_idx',
    'AdminUserPermission_actorUserId_isActive_idx',
    'SupportActionExecution_idempotencyKey_key'
  )
ORDER BY indexname ASC;
```

5. Confirmar que a aplicacao sobe no ambiente alvo pelo procedimento oficial do
ambiente. Nao executar deploy automatico a partir deste runbook.

6. Confirmar que dry-run continua disponivel com teste controlado e nao
destrutivo:

```text
POST /api/admin/support-actions/dry-run
```

Usar somente credencial autorizada, motivo de teste e alvo de teste. O dry-run
nao altera estado real.

7. Confirmar que a rota legada continua preservada sem executar revogacao real
em sessao de usuario. Opcoes seguras:

- usar teste E2E em banco isolado;
- usar sessao descartavel em ambiente controlado com aprovacao explicita;
- ou validar apenas que a rota continua registrada e monitorada.

8. Confirmar que a feature flag segue `false` e que nenhuma UX real foi
habilitada.

## Janela de observacao apos migration

Somente depois dos post-checks, iniciar a janela documentada em
`backend/docs/revoke-session-rollout-approval.md`:

- 7 dias para ambiente interno com operadores conhecidos;
- 14 dias quando houver operadores externos ou chamadas manuais;
- janela maior se a origem for incerta.

Consultar:

```text
admin.sessions.legacy_revoke.used
support.revoke_session.execute_requested
support.revoke_session.execute_succeeded
support.revoke_session.execute_failed
support.revoke_session.execute_denied
```

## Rollback e mitigacao

Se a migration falhar antes de concluir:

1. Parar a execucao.
2. Registrar erro, horario, operador e ambiente.
3. Nao habilitar feature flag.
4. Nao criar UX.
5. Manter a rota legada preservada.
6. Acionar o procedimento oficial de rollback do ambiente.

Se a migration concluir mas a aplicacao falhar:

1. Manter `SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED=false`.
2. Remover trafego ou restaurar versao anterior conforme runbook do ambiente.
3. Restaurar backup/snapshot se a politica operacional exigir.
4. Registrar incidente com detalhes sanitizados.
5. Reexecutar post-checks antes de qualquer nova tentativa.

Rollback de banco deve ser feito por restore/snapshot ou runbook aprovado. Nao
criar migration reversa emergencial sem revisao.

## Criterios de sucesso

- Migrations relevantes aparecem aplicadas em `_prisma_migrations`.
- `AdminAuditLog.actorType` existe.
- `AdminAuditLog.actorLabel` existe.
- `AdminAuditLog.actorUserId` aceita `NULL`.
- `AdminUserPermission` existe.
- `SupportActionExecution` existe.
- `npx prisma validate` passa.
- Aplicacao sobe pelo procedimento oficial.
- Dry-run continua sem efeito real.
- Rota legada continua preservada.
- Feature flag permanece `false`.
- Gate permanece `PENDENTE` ate a janela de observacao terminar.

## Criterios de abortar

- Ambiente ou schema nao conferem.
- Backup/snapshot aplicavel nao esta confirmado.
- `npx prisma validate` falha.
- `prisma migrate status` indica estado inconsistente.
- Existem migrations desconhecidas pendentes.
- Janela operacional nao foi aprovada.
- Responsavel tecnico ou operacional nao foi definido.
- Nao ha criterio de rollback documentado.
- Feature flag seria habilitada junto com a migration.

## Confirmacoes de escopo

- Este runbook nao aplica migration automaticamente.
- Este runbook nao habilita `SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED`.
- Este runbook nao remove nem bloqueia a rota legada.
- Este runbook nao cria UX real no Admin Web.
- Este runbook nao cria execucao real para outras support-actions.
