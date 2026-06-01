# Backend Integration Tests

Data: 2026-05-31

Este documento descreve a fundacao de testes de integracao com Prisma real e
testes HTTP/E2E protegidos para o backend Tatuzin.

Os testes de integracao sao opt-in. Eles nao usam `DATABASE_URL` e nao devem
rodar contra banco local/dev/staging/producao.

## Objetivo

Validar contratos persistidos com Prisma real e fluxo HTTP autenticado para:

- `AdminAuditLog`
- `AdminUserPermission`
- bootstrap inicial de `admin-permissions.manage`
- API `/api/admin/permissions/*`
- API `POST /api/admin/support-actions/dry-run`
- piloto `POST /api/admin/support-actions/revoke-session/execute`

Sem UX de execucao e sem rota generica de execucao de support-actions.

## Arquivos

- `backend/src/shared/testing/integration-prisma.ts`
- `backend/src/shared/testing/integration-prisma.test.ts`
- `backend/src/modules/admin-permissions/admin-permissions.integration.test.ts`
- `backend/src/modules/admin-permissions/admin-permissions.http.integration.test.ts`
- `backend/src/modules/support-actions/support-actions.execution.integration.test.ts`
- `backend/scripts/migrate-integration-test-db.ts`

## Opt-in obrigatorio

Variaveis obrigatorias:

```powershell
$env:RUN_INTEGRATION_TESTS='true'
$env:INTEGRATION_TEST_DATABASE_URL='postgresql://postgres:postgres@localhost:5432/simples_erp_integration_test?schema=integration_test'
$env:SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED='true'
```

`DATABASE_URL` nunca e usado pelos testes de integracao.

Se `RUN_INTEGRATION_TESTS` ou `INTEGRATION_TEST_DATABASE_URL` nao forem
definidas, os testes pulam com mensagem clara.

## Guardrails de seguranca

Antes de qualquer conexao, o helper valida:

- `RUN_INTEGRATION_TESTS=true`;
- `INTEGRATION_TEST_DATABASE_URL` definida;
- `INTEGRATION_TEST_DATABASE_URL` diferente de `DATABASE_URL`;
- protocolo `postgres://` ou `postgresql://`;
- URL, banco, schema, host ou usuario contendo marcador claro como `test`,
  `integration`, `isolated` ou `ci`;
- bloqueio de nomes obvios como `postgres`, `simples_erp`,
  `simples_erp_dev`, `tatuzin` e equivalentes de producao;
- bloqueio de fragmentos suspeitos como `prod`, `production`, `staging`,
  `supabase.co`, `neon.tech`, `amazonaws.com`, `oraclecloud.com` e dominios
  reais do Tatuzin.

## Preparacao do banco isolado

Crie um banco/schema exclusivamente para testes. Exemplo local:

```powershell
createdb simples_erp_integration_test
```

Configure apenas as variaveis de integracao e aplique migrations pelo script
guardado. O script valida `INTEGRATION_TEST_DATABASE_URL` antes de repassar o
valor como `DATABASE_URL` para o Prisma CLI:

```powershell
$env:RUN_INTEGRATION_TESTS='true'
$env:INTEGRATION_TEST_DATABASE_URL='postgresql://postgres:postgres@localhost:5432/simples_erp_integration_test?schema=integration_test'
npm run prisma:migrate:integration
```

Depois rode os testes:

```powershell
npm run test:integration
```

`npm run test:integration` e deliberadamente limitado aos testes protegidos por
`integration-prisma`, `admin-permissions` e ao piloto `revoke_session`. Ele roda com
`--test-concurrency=1` para evitar interferencia entre cenarios de bootstrap e
permissoes persistidas. Ele nao executa suites legadas que dependem diretamente
de `DATABASE_URL`.

Nao aponte `INTEGRATION_TEST_DATABASE_URL` para banco local/dev que contenha
dados reais.

## Escopo dos testes atuais

`AdminAuditLog`:

- cria log `BOOTSTRAP` com `actorUserId=null` e
  `actorLabel=SYSTEM_BOOTSTRAP`;
- cria log `USER` com `actorUserId` real;
- cria log omitindo `actorType` para validar default legado `USER`;
- valida sanitizacao de tokens, secrets e senhas.

`AdminUserPermission`:

- cria `admin-permissions.manage` para um AdminUser;
- lista permissoes persistidas;
- concede e revoga permissao de support-action;
- valida que permissao revogada nao autoriza;
- valida constraint de duplicidade.
- valida dry-run de support-actions usando permissao persistida real e negando
  depois do soft revoke.

Bootstrap:

- permite primeira concessao em banco limpo de managers;
- nega segunda tentativa quando ja existe manager ativo;
- valida auditoria `BOOTSTRAP` persistida.

HTTP/E2E com autenticacao real:

- cria usuarios e memberships em banco isolado;
- faz login real em `/api/auth/login`;
- valida `requirePlatformAdmin` nas rotas administrativas;
- valida catalogo, listagem, grant e revoke por HTTP;
- valida motivo obrigatorio e permissionKey desconhecida;
- valida auditoria persistida de grant, revoke e negacoes;
- valida que `permissionKeys` enviados pelo cliente nao autorizam dry-run;
- valida que `actorAdminId` vem do contexto autenticado, nao do payload;
- valida que `isPlatformAdmin` sozinho nao libera support-action sensivel;
- valida que admin com permissao persistida consegue dry-run;
- valida recibo Prisma idempotente e auditoria before/after do piloto
  `revoke_session`;
- valida execucao HTTP autenticada e replay da mesma `idempotencyKey`;
- valida que `dryRun=false` e rejeitado;
- valida sanitizacao de `token`, `authorization`, `password`, `secret`,
  `cookie`, `jwt`, `credential` e `webhook`.

## Cleanup

Os testes Prisma rastreiam os IDs que criam e removem apenas esses registros no
final. O cleanup ocorre na ordem:

1. `SupportActionExecution`
2. `AdminAuditLog`
3. `AdminUserPermission`
4. `Company`
5. `User`

Isso evita remover dados fora do escopo do teste.

Os testes HTTP/E2E usam e-mails e slugs prefixados por `runId` e limpam apenas
usuarios, empresas, sessoes, devices e auditorias ligados a esse prefixo no
banco isolado.

## Comandos seguros

Sem banco configurado, apenas confirma skip:

```powershell
npx tsx --test src/modules/admin-permissions/admin-permissions.integration.test.ts
```

Com banco isolado configurado:

```powershell
npm run prisma:migrate:integration
npm run test:integration
```

Somente HTTP/E2E:

```powershell
npm run test:integration:http
```
