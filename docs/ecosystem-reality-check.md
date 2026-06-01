# Tatuzin Ecosystem Reality Check

Data: 2026-05-31

Este documento registra uma leitura realista do ecossistema Tatuzin no
repositorio `C:\Simples`. O objetivo e separar o que ja existe de fato, o que
esta apenas preparado em UI/documentacao, o que depende de backend, Android,
infraestrutura, seguranca, auditoria e o que deve entrar em roadmaps futuros.

## Resumo executivo

O Tatuzin esta organizado como um ecossistema com quatro blocos principais:

- App Flutter principal em `lib/` e `android/`.
- Backend Node.js/Express/TypeScript/Prisma/PostgreSQL em `backend/`.
- Admin Web Flutter Web em `admin_web/`.
- Owner Web Flutter Web em `owner_web/`.

O produto ja tem fundacoes reais importantes: autenticacao com JWT e refresh
token, sessoes por dispositivo, app context, licencas/entitlements, billing com
Mercado Pago, sync operacional para PDV, auditoria administrativa, healthchecks,
rate limit persistido e paineis web separados para plataforma e owner.

O ponto principal do reality check e que nem todos os blocos tem o mesmo nivel
de maturidade. O backend e o app principal possuem bastante logica operacional
real; o Admin Web evoluiu para console interno, mas varias areas continuam
read-only por design; FCM/push e parte de observabilidade/CI/CD continuam em
preparacao documental; o Owner Web existe e e separado, mas deve continuar sendo
tratado como painel de consulta ate que contratos e fluxos de producao sejam
formalizados.

## Escopo analisado

- `README.md`
- `pubspec.yaml`
- `lib/`
- `test/`
- `android/`
- `backend/`
- `admin_web/`
- `owner_web/`
- `docs/`
- configuracoes Docker, Prisma, roteadores, documentacao e testes existentes

Nenhum backend, migration, Android, owner_web, billing engine, sync engine,
Firebase real, segredo, endpoint, contrato de API ou acao operacional real foi
alterado para gerar este documento.

## Mapa de componentes

| Componente | Stack | Estado real |
| --- | --- | --- |
| App Flutter | Flutter, Riverpod, GoRouter, SQLite, http | Aplicacao operacional principal com PDV local-first via `OperationalSyncEvent` e ERP/CRM server-first/cache. |
| Android shell | Gradle/Kotlin + Flutter | Shell Android padrao do app Flutter, sem integracao Firebase/FCM real detectada. |
| Backend | Node 24, Express, TypeScript, Prisma, PostgreSQL | API real com auth, app context, billing, sync, admin, owner, employees, analytics e modulos de negocio. |
| Admin Web | Flutter Web, Riverpod, GoRouter | Painel interno de plataforma, com suporte operacional visual e varias areas read-only. |
| Owner Web | Flutter Web, Riverpod, GoRouter | Painel separado para owner/gestor, em modo consulta, sem consumir `/api/admin/*`. |
| Docs | Markdown, OpenAPI draft | Boa base documental, especialmente para Admin Web, seguranca, observabilidade, CI/CD, Android version e FCM futuro. |

## Arquitetura real

### App principal

O app principal e o Tatuzin operacional. Ele usa:

- SQLite local tenant-bound para operacao local.
- Riverpod e GoRouter.
- `http` para API real.
- `shared_preferences` para sessao/configuracao.
- Sync operacional em `lib/app/core/sync`.

O README raiz define a separacao correta:

- PDV local-first via `OperationalSyncEvent`.
- ERP server-first/cache.
- CRM server-first/cache.

Essa distincao e importante: produtos, categorias, clientes, fornecedores,
compras, insumos, custos, relatorios e fiado gerencial nao devem virar CRUD
local-first via sync operacional sem uma decisao de arquitetura explicita.

### Backend

O backend e uma API Express com Prisma/PostgreSQL. Modulos reais encontrados em
`backend/src/modules` incluem:

- `auth`
- `app`
- `admin`
- `billing`
- `companies`
- `users`
- `employees`
- `plans`
- `sync`
- `cash`
- `operational-orders`
- `sales`
- `inventory`
- `categories`
- `products`
- `product-recipes`
- `customers`
- `crm`
- `suppliers`
- `supplies`
- `purchases`
- `costs`
- `financial-events`
- `fiado`
- `analytics`
- `hybrid-governance`
- `owner`

O backend possui healthchecks em `/api/health` e `/api/readiness`, app context,
validacao de sessao por `sessionId`, rate limit persistido, jobs de manutencao
e headers basicos de seguranca.

### Admin Web

O Admin Web e o painel interno da plataforma Tatuzin. Ele esta separado do
Owner Web e consome contratos administrativos. O roadmap de 12 fases do
Admin Web foi documentado em:

- `admin_web/docs/admin-web-roadmap-closure.md`

Estado real: existe uma base forte de navegacao, suporte, sync center,
auditoria, billing, licencas, dispositivos, sessoes, versao Android e FCM
futuro. A maior parte das telas sensiveis permanece read-only ou com exposicao
controlada.

### Owner Web

O Owner Web existe em `owner_web/`, com rotas para dashboard, vendas, clientes,
financeiro, produtos, relatorios, empresa, billing, funcionarios, dispositivos e
settings. A documentacao dele afirma corretamente que:

- e separado do `admin_web`;
- nao consome `/api/admin/*`;
- nao implementa acoes de escrita nesta fase;
- nao usa local-first;
- mostra estados vazios honestos quando nao ha endpoint real.

## Auth, sessoes e permissoes

Estado real:

- Auth backend usa JWT Bearer e refresh token.
- `requireAuth` valida token e, quando existe `sessionId`, valida a sessao.
- `requireAppContext` monta contexto de empresa, usuario, device, licenca e
  permissoes.
- `requirePlatformAdmin` protege rotas administrativas via usuario ativo com
  `isPlatformAdmin`.
- `requireCloudLicense` bloqueia licencas suspensas, expiradas, trial ou sem
  sync habilitado.
- Existem sessoes por dispositivo e logs de sessao.

Lacunas/proximos passos:

- Permissoes administrativas granulares por acao ainda devem ser formalizadas.
- O Admin Web ainda documenta a necessidade futura de Cookie HttpOnly/BFF, MFA,
  CSP e enforcement mais forte de seguranca.
- A exposicao de acoes reais no Admin Web deve depender de motivo obrigatorio,
  confirmacao explicita, ator/admin, permissao por acao e trilha auditavel.

## Billing e licencas

Estado real:

- Billing backend existe e usa Mercado Pago Subscriptions/Preapproval.
- `license.plan` e a fonte de verdade.
- O app nao deve promover plano localmente.
- Webhook Mercado Pago existe em `/api/webhooks/mercadopago`.
- Existem endpoints publicos de billing e endpoints administrativos protegidos
  por platform admin.
- Existem logs de auditoria especificos para billing administrativo.
- Existem acoes administrativas reais, como refresh, force-plan, cancel-local,
  reconciliacao, extensao emergencial, suspensao e reativacao de licenca.

Ponto de atencao:

O Admin Web documenta varias areas como read-only por design, mas o backend ja
possui algumas acoes administrativas reais. A decisao correta e nao expor essas
acoes de forma ampla no front-end ate que permissoes, auditoria, motivo,
confirmacao e operacao de suporte estejam endurecidos.

## Sync operacional

Estado real:

- Sync backend existe em `/api/sync/*`.
- App principal possui engine local, fila, recover de eventos, push/pull,
  diagnosticos e testes extensos.
- Backend possui `SyncEvent`, `SyncConflict`, `SyncIncident`,
  `SyncSupportCommand`, `DeviceSyncDiagnostic`, checkpoints e materializadores.
- Existem comandos de suporte de sync com dry-run, motivo e confirmacao no
  backend.
- Admin Web possui Sync Center visual/read-only para triagem, eventos,
  conflitos, incidentes, dispositivos e diagnostico.

Lacunas/proximos passos:

- O Admin Web ainda deve expor comandos reais somente apos desenho operacional
  completo.
- E preciso separar claramente operacao local-first de PDV de dados
  server-first/cache.
- Observabilidade de fila local, retries e falhas do app ainda depende de
  diagnosticos enviados pelo cliente.

## Auditoria

Estado real:

- Existem modelos de auditoria no Prisma, incluindo `AdminAuditLog`,
  `BillingAdminAuditLog` e `SessionAuditLog`.
- O Admin Web possui pagina de Auditoria e normalizacao visual de eventos.
- Algumas acoes administrativas reais ja registram motivo e before/after.

Lacunas/proximos passos:

- Padronizar auditoria para toda acao operacional sensivel.
- Garantir motivo obrigatorio, confirmacao explicita, ator/admin, payload
  seguro, correlacao e permissao por acao.
- Evitar expor payloads sensiveis, tokens, provider IDs completos ou dados de
  terceiros.

## Observabilidade e infraestrutura

Estado real:

- Backend possui logger JSON simples.
- Healthcheck e readiness existem.
- Dockerfile, compose local e compose de producao existem.
- Caddy aparece no compose de producao para expor `api.tatuzin.com.br`.
- Rate limit persistido existe via `RateLimitBucket`.
- Admin Web documenta observabilidade futura.

Lacunas/proximos passos:

- Nao ha evidencia de pipeline CI oficial na raiz do repositorio.
- Nao ha Prometheus/Grafana/APM real configurado no repo.
- Alertas externos ainda nao aparecem como implementacao real.
- Deploy real, secrets reais e operacao de producao continuam fora do repo.
- CSP/security headers especificos para os frontends web ainda dependem da
  infraestrutura de publicacao.

## Android, versao e FCM

Estado real:

- Android usa o shell Flutter padrao com `applicationId`
  `br.com.tatuzin.gestao`.
- `versionCode` e `versionName` vem do Flutter.
- Nao foi detectada dependencia Firebase/FCM real no app Android, pubspecs,
  backend ou Gradle.
- Admin Web possui documentacao e UI read-only para controle futuro de versao
  Android e Push Notification / FCM.

Lacunas/proximos passos:

- App precisa reportar versao instalada de forma confiavel quando isso virar
  politica operacional.
- Enforcement de versao minima e atualizacao obrigatoria dependem de backend e
  Android.
- FCM real depende de token por dispositivo, preferencias, Firebase backend,
  Firebase Android, auditoria e politicas de envio.

## Testes e validacao existentes

Estado real observado:

- App principal possui uma suite Dart grande em `test/`.
- Admin Web possui testes Flutter em `admin_web/test/`.
- Owner Web possui testes em `owner_web/test/`.
- Backend possui testes Node em `backend/src/**/*.test.ts`.
- Testes backend usam Prisma e banco de dados, com criacao e limpeza de dados
  por suite; portanto devem rodar apenas contra banco local/teste isolado.

Comandos de validacao seguros para documentacao:

```powershell
flutter analyze
flutter test
cd admin_web
flutter analyze
flutter test
cd ..\owner_web
flutter analyze
flutter test
```

Validacoes backend recomendadas quando houver banco de teste isolado:

```powershell
cd backend
npx prisma validate
npm test
```

Validacao executada neste fechamento:

| Comando | Resultado |
| --- | --- |
| `flutter analyze` na raiz | Passou, sem issues. |
| `flutter test` na raiz | Passou. |
| `flutter analyze` em `admin_web` | Passou, sem issues. |
| `flutter test` em `admin_web` | Passou, 85 testes. |
| `flutter analyze` em `owner_web` | Passou, sem issues. |
| `flutter test` em `owner_web` | Passou, 27 testes. |
| `npx prisma validate` em `backend` | Passou, schema Prisma valido. |

`npm test` do backend nao foi executado neste fechamento porque a suite usa
Prisma para criar e apagar dados, devendo rodar somente contra banco
local/teste isolado confirmado.

## Estado read-only por design

As areas abaixo existem como base visual, documental ou de triagem, mas nao
devem ser tratadas como operacao completa de producao no front-end:

- Suporte operacional do Admin Web.
- Sync Center no Admin Web.
- Auditoria visual no Admin Web.
- Seguranca do Admin Web.
- Observabilidade do Admin Web.
- Controle de versao Android.
- Push Notification / FCM.
- Owner Web, enquanto painel de consulta.

Read-only aqui nao significa "sem backend". Em alguns casos, como billing,
licenca e sync, o backend ja possui acoes reais. Significa que a UI ainda deve
preservar uma postura conservadora ate que governanca, permissao, auditoria e
runbooks estejam maduros.

## Dependencias futuras

### Backend

- Contratos oficiais para cada tela operacional.
- Endpoints finais para acoes de suporte expostas no Admin Web.
- Permissoes administrativas granulares por acao.
- Auditoria backend obrigatoria e uniforme.
- Dry-run padronizado para toda acao sensivel.
- Healthchecks especificos por dominio.
- Metricas reais e exportaveis.
- Politica backend de versao Android.
- FCM real: tokens, preferencias, historico e envio.

### Android

- Envio confiavel da versao instalada.
- Enforcement de versao minima.
- Fluxo de atualizacao obrigatoria.
- Registro e rotacao de token FCM.
- Preferencias de push por usuario/dispositivo.
- Comportamento de mensagens operacionais.
- Diagnosticos locais suficientes para suporte remoto.

### Infraestrutura

- CI oficial na raiz do repositorio.
- Deploy real dos frontends e backend.
- Gestao real de secrets.
- CSP e security headers para web.
- Observabilidade real com metricas, traces e logs centralizados.
- Prometheus/Grafana/APM ou solucao equivalente.
- Alertas externos.
- Runbooks de incidente.

### Seguranca e auditoria

- Motivo obrigatorio para acoes sensiveis.
- Confirmacao explicita por tipo de acao.
- Ator/admin sempre registrado.
- Payload seguro e sanitizado.
- Trilha auditavel completa.
- Permissao por acao, nao apenas `isPlatformAdmin`.
- Politica para dados sensiveis em UI/logs.
- Revisao de sessao web: HttpOnly/BFF/MFA/CSP conforme decisao de arquitetura.

## Proximos epicos recomendados

1. Backend Support Actions Foundation
2. Admin Permissions & Audit Enforcement
3. Admin Web Controlled Actions UX
4. Android Version Policy Backend
5. Android Version Enforcement
6. FCM Backend + Android Integration
7. Observability Backend Metrics
8. Official CI/CD Workflow
9. Production Security Hardening
10. Owner Web Production Readiness

## Riscos principais

- Expor no Admin Web acoes backend reais antes de fechar permissao, auditoria e
  runbooks.
- Misturar owner web, admin web e app operacional em um unico contrato mental.
- Tratar FCM como pronto por existir UI/documentacao read-only.
- Usar sync operacional para entidades server-first/cache sem decisao
  arquitetural.
- Rodar testes backend contra banco nao isolado.
- Publicar frontends sem headers, CSP e estrategia de secrets/ambiente.

## Conclusao

O ecossistema Tatuzin esta em um estado mais maduro do que um prototipo: backend,
app principal, billing, sync, admin e owner possuem estruturas reais. Ao mesmo
tempo, a maturidade e desigual entre os blocos. O caminho recomendado e
preservar o Admin Web como console interno conservador enquanto os proximos
epicos fecham backend de acoes, permissao granular, auditoria obrigatoria,
Android version policy, FCM real, observabilidade, CI/CD e hardening de
producao.
