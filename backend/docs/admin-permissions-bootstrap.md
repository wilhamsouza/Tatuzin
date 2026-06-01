# Admin Permissions Bootstrap

Data: 2026-05-31

Este documento descreve o bootstrap excepcional para conceder a primeira
permissao `admin-permissions.manage` a um AdminUser existente.

Esta etapa nao cria rota HTTP, nao cria UX, nao aplica migration em banco real
e nao executa support-actions reais.

## Objetivo

Antes de existir uma tela ou rota operacional para gerenciar permissoes
administrativas, o backend precisa de um caminho controlado para criar o
primeiro administrador capaz de usar `AdminPermissionsService`.

O bootstrap existe apenas para esse primeiro passo.

## Script

Arquivo:

- `backend/scripts/bootstrap-admin-permission.ts`

Comando:

```powershell
cd backend
$env:ADMIN_PERMISSION_BOOTSTRAP_ENABLED='true'
npm run admin-permissions:bootstrap -- --adminUserId=<admin-user-id> --reason="Bootstrap inicial aprovado em runbook interno"
```

Tambem e possivel identificar o alvo por e-mail:

```powershell
cd backend
$env:ADMIN_PERMISSION_BOOTSTRAP_ENABLED='true'
npm run admin-permissions:bootstrap -- --email=admin@simples.local --reason="Bootstrap inicial aprovado em runbook interno"
```

Permissao padrao:

```text
admin-permissions.manage
```

## Controles obrigatorios

O bootstrap exige:

- `ADMIN_PERMISSION_BOOTSTRAP_ENABLED=true`;
- motivo com pelo menos 12 caracteres;
- alvo explicito por `adminUserId` ou `email`;
- alvo existente;
- alvo ativo;
- alvo com `isPlatformAdmin=true`;
- permissao dentro da allowlist;
- inexistencia previa de qualquer `admin-permissions.manage` ativo.

Allowlist inicial:

- `admin-permissions.manage`

## Sem --force por padrao

Se ja existir qualquer `AdminUserPermission` ativa com
`admin-permissions.manage`, o bootstrap e negado.

Nao existe `--force` nesta etapa. Uma excecao futura exigiria decisao
documentada, trilha de auditoria propria e validacao operacional fora deste
script.

## Autoelevacao

O bootstrap nao usa um admin humano como ator de permissao e nao aceita
`permissionKeys` do cliente como autorizacao. O ator logico e
`SYSTEM_BOOTSTRAP`.

Essa e a unica excecao documentada para criar a primeira permissao critica.
Ela so vale quando ainda nao existe nenhum manager ativo, com env explicita e
alvo existente.

## Auditoria

O script registra em `AdminAuditLog`:

- `admin_permissions.bootstrap.attempted`
- `admin_permissions.bootstrap.granted`
- `admin_permissions.bootstrap.denied`

O payload seguro inclui:

- `actorType: BOOTSTRAP`;
- `actorUserId: null`;
- `actorLabel: SYSTEM_BOOTSTRAP`;
- `systemActor: SYSTEM_BOOTSTRAP`;
- alvo;
- identificador informado;
- permissao;
- motivo;
- resultado;
- detalhes seguros da decisao.

Tokens, secrets, authorization, cookies, credentials e strings suspeitas sao
redigidos pelo sanitizador compartilhado de `support-actions`.

### Modelo de ator

`AdminAuditLog` agora possui campos explicitos para o ator:

- `actorType`
- `actorUserId`
- `actorLabel`

O bootstrap grava `actorType=BOOTSTRAP`, `actorUserId=null` e
`actorLabel=SYSTEM_BOOTSTRAP`. Isso remove a dependencia anterior de usar o
alvo como ancora tecnica do log.

A migration aditiva que prepara esse modelo e:

- `backend/prisma/migrations/20260531183000_admin_audit_actor_model/migration.sql`

Ela deve ser aplicada somente em ambiente controlado, junto com o runbook de
migrations do backend.

## O que nao existe

- Endpoint HTTP de bootstrap.
- UX no Admin Web.
- Rota de execucao real de support-actions.
- `--force`.
- Bypass por `isPlatformAdmin`.
- Uso de `permissionKeys` vindos do cliente como autorizacao.

## Validacao segura

Testes relacionados:

```powershell
cd backend
npx tsx --test src/modules/admin-permissions/admin-permissions.bootstrap.test.ts
```

Validacoes gerais esperadas:

```powershell
cd backend
npx prisma generate
npx prisma validate
npm run build
```

## Integracao com Prisma real

A validacao real do bootstrap com `AdminAuditLog` e `AdminUserPermission` vive
nos testes de integracao documentados em:

- `backend/docs/integration-tests.md`

Esses testes so rodam com `RUN_INTEGRATION_TESTS=true` e
`INTEGRATION_TEST_DATABASE_URL` apontando para banco/schema claramente isolado.
