# Tatuzin ERP

Tatuzin ERP e um app/SaaS para gestao de lojas de vestuario e moda. O produto cobre PDV, caixa, estoque, produtos, clientes, fiado, custos, compras, fornecedores, relatorios, assinatura e funcionarios PRO.

Este README descreve o estado real deste repositorio. Ele e do Tatuzin ERP, nao do TatuLog.

## Arquitetura

A arquitetura oficial do Tatuzin separa a operacao em tres blocos:

- PDV: local-first via `OperationalSyncEvent`.
- ERP: server-first/cache.
- CRM: server-first/cache.

O PDV pode operar localmente e registrar eventos operacionais para sincronizacao. O ERP e o CRM nao devem ser documentados nem evoluidos como local-first puro.

### Sync Operacional

O sync operacional passa por `/api/sync/*` e usa eventos `OperationalSyncEvent` no app. Essa camada e destinada a operacoes de PDV e caixa que precisam suportar uso local/offline.

Entidades local-first permitidas pela policy atual:

- `cashSession`
- `cashMovement`
- `operationalOrder`
- `operationalOrderItem`
- `sale`
- `saleItem`
- `payment`
- `receipt`
- `stockReservation`
- `stockDeduction`
- `offlineOperationLog`

Entidades server-first/cache:

- `product`
- `category`
- `customer`
- `supplier`
- `purchase`
- `supply`
- `cost`
- `report`
- `fiado` gerencial

Nao crie produto, cliente, fornecedor, compra, insumo, custo ou relatorio gerencial por `SyncEvent`. Essas areas sao server-first/cache. PDV escreve por `OperationalSyncEvent`; ERP/CRM consomem backend/cache.

## Stack

### Flutter App

- Flutter `>=3.38.0`
- Dart SDK `>=3.10.0 <4.0.0`
- Riverpod
- GoRouter
- SQLite local tenant-bound para operacao de PDV
- `http` como API client real
- `shared_preferences` para sessao/configuracao
- `url_launcher` para checkout externo
- sync operacional em `lib/app/core/sync`

### Backend

- Node.js `>=24.0.0`
- Express
- TypeScript
- Prisma
- PostgreSQL
- JWT, refresh token, sessao por dispositivo e app context
- Docker/container
- API publica configurada para `https://api.tatuzin.com.br/api`

### Admin Web

Existe um admin web em `admin_web`, feito em Flutter Web. Ele e o painel administrativo da plataforma Tatuzin, publicado para o contexto de `admin.tatuzin.com.br`.

O admin web cobre login administrativo, empresas, licencas, billing administrativo, saude de sync, auditoria e visoes gerenciais. Ele nao e painel owner do cliente e nao substitui o app operacional. O painel owner nao deve ser tratado como pronto neste README.

## Estrutura do Repositorio

```text
.
|-- lib/                 App Flutter principal do Tatuzin ERP
|-- test/                Testes do app Flutter principal
|-- backend/             API Node/Express/TypeScript + Prisma
|-- admin_web/           Painel web da plataforma Tatuzin
|-- android/             Shell Android do app Flutter
|-- assets/              Branding, fontes e assets do app
|-- docs/                Documentacao complementar
|-- pubspec.yaml         Dependencias do app principal
`-- README.md            Este arquivo
```

Arquivos de referencia:

- App Flutter: `pubspec.yaml`
- Backend: `backend/package.json`
- Prisma: `backend/prisma/schema.prisma`
- Compose local PostgreSQL: `backend/docker-compose.yml`
- Compose de producao com backend + Caddy: `backend/docker-compose.prod.yml`
- Env local backend: `backend/.env.example`
- Env producao backend: `backend/.env.production.example`
- Rotas Flutter: `lib/app/routes`
- Modulos Flutter: `lib/modules`
- Modulos backend: `backend/src/modules`

Observacao: no estado atual do repositorio nao ha `backend/docker-compose.vm.yml`; o compose equivalente de producao e `backend/docker-compose.prod.yml`.

## Modulos Principais

### App Flutter

Modulos reais em `lib/modules`:

- `auth`
- `account`
- `billing`
- `dashboard`
- `vendas`
- `carrinho`
- `checkout`
- `caixa`
- `pedidos`
- `historico_vendas`
- `comprovantes`
- `produtos`
- `categorias`
- `estoque`
- `clientes`
- `fiado`
- `compras`
- `fornecedores`
- `insumos`
- `custos`
- `relatorios`
- `funcionarios`
- `backup`
- `admin`
- `system`

Rotas principais ficam em `lib/app/routes`. A rota de funcionarios e `/funcionarios`; assinatura fica em `/conta/assinatura`.

### Backend

Modulos reais em `backend/src/modules`:

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

O backend e fonte de verdade para device, license, plan e entitlements. O app consome `/api/app/bootstrap` e app context para refletir plano, limites, dispositivos e permissoes efetivas.

### Admin Web

O admin web fica em `admin_web`. Features reais em `admin_web/lib/src/features`:

- `auth`
- `dashboard`
- `companies`
- `licenses`
- `sync_health`
- `audit`
- `management`

## Billing e Assinaturas

Billing e server-first com Mercado Pago Subscriptions/Preapproval.

Regras importantes:

- `license.plan` e a fonte de verdade do plano.
- O app Flutter nunca promove plano localmente.
- `POST /api/billing/subscribe` cria checkout/preapproval, mas nao muda `license.plan`.
- Plano pago so e ativado por webhook Mercado Pago, refresh backend seguro ou acao admin auditada.
- `GET /api/billing/status` le o banco local do backend e nao consulta Mercado Pago automaticamente.
- `POST /api/billing/refresh` e a reconciliacao explicita.
- `/api/billing/status` nao expoe `providerSubscriptionId` completo; retorna apenas flags e ID mascarado.
- Downgrade para FREE nunca apaga dados, faturas, eventos, sessoes ou funcionarios.

Endpoints publicos de billing no backend:

- `GET /api/billing/plans`
- `GET /api/billing/status`
- `POST /api/billing/subscribe`
- `POST /api/billing/refresh`
- `GET /api/billing/invoices`
- `GET /api/billing/invoices/:id`
- `GET /api/billing/payment-method`
- `POST /api/billing/cancel`
- `POST /api/billing/resume`
- `POST /api/billing/change-plan`
- `POST /api/webhooks/mercadopago`

Billing administrativo protegido por platform admin:

- `GET /api/admin/billing/companies`
- `GET /api/admin/companies/:companyId/billing/status`
- `GET /api/admin/companies/:companyId/billing/events`
- `GET /api/admin/companies/:companyId/billing/checkout-sessions`
- `POST /api/admin/companies/:companyId/billing/refresh`
- `POST /api/admin/companies/:companyId/billing/force-plan`
- `POST /api/admin/companies/:companyId/billing/cancel-local`

`cancel-local` administrativo nao cancela Mercado Pago; ele aplica ajuste local auditado.

Variaveis de billing suportadas pelo backend:

- `MERCADO_PAGO_ACCESS_TOKEN`
- `MERCADO_PAGO_WEBHOOK_SECRET`
- `API_PUBLIC_URL`
- `APP_PUBLIC_URL`
- `BILLING_BASIC_PRICE_CENTS` com default `3500`
- `BILLING_PRO_PRICE_CENTS` com default `8500`

Nao salve tokens reais no repositorio.

## Funcionarios PRO

Funcionarios e recurso PRO.

O backend possui `EmployeeProfile` e endpoints em `/api/employees`, todos protegidos por:

- `requireAppContext`
- `requireFeature('employees')`
- permissao efetiva `employees.manage`
- isolamento por `companyId`

Endpoints:

- `GET /api/employees`
- `GET /api/employees/:id`
- `POST /api/employees`
- `PATCH /api/employees/:id`
- `DELETE /api/employees/:id`
- `POST /api/employees/:id/invite`
- `POST /api/employees/:id/disable`
- `POST /api/employees/:id/enable`

Cargos oficiais:

- `OWNER`
- `MANAGER`
- `CASHIER`
- `SELLER`
- `STOCK_OPERATOR`
- `READ_ONLY`

Status oficiais:

- `ACTIVE`
- `INVITED`
- `DISABLED`

Protecoes:

- `OWNER` efetivo vem de `MembershipRole.OWNER`.
- `OWNER` sempre recebe permissoes efetivas completas.
- `OWNER` nao pode ser criado manualmente, promovido, removido, desabilitado, rebaixado ou perder `employees.manage`.
- `DELETE /api/employees/:id` e soft delete via `DISABLED`.
- Convite gera hash no backend, nao envia e-mail real nesta fase e nao retorna token/hash ao app.
- FREE/BASIC bloqueiam funcionarios.
- `pendingPlan=PRO` nao libera funcionarios.
- PRO libera conforme entitlement real (`license.plan=PRO`) e permissao efetiva.

No Flutter, `FeatureGate(FeatureKey.employees)` e a unica fonte para liberar a tela. `membership.permissions` e `employee.permissions` controlam apenas acoes internas depois que o entitlement ja liberou a feature.

## Planos e Entitlements

Catalogo real em `backend/src/modules/plans/plan-catalog.service.ts` e `lib/app/core/entitlements/plan_entitlements.dart`.

| Plano | Features principais | maxDevices | maxEmployees | reportPeriods |
| --- | --- | ---: | ---: | --- |
| FREE | vendas, caixa, produtos, categorias, clientes basico, venda fiado, relatorio diario, estoque basico | 1 | 0 | daily |
| BASIC | tudo do FREE, gestao de fiado, insumos, custos, fornecedores, compras, estoque avancado, relatorios basicos | 1 | 0 | daily, weekly, monthly |
| PRO | todas as features catalogadas, incluindo funcionarios, permissoes, multi-dispositivo, dispositivos e relatorios avancados | 100 | 100 | daily, weekly, monthly, yearly, custom |

Features catalogadas:

- `sales`
- `cash`
- `products`
- `categories`
- `customersBasic`
- `fiadoCreateSale`
- `fiadoManagement`
- `supplies`
- `costs`
- `suppliers`
- `purchases`
- `inventoryBasic`
- `inventoryAdvanced`
- `reportsDaily`
- `reportsBasic`
- `reportsAdvanced`
- `employees`
- `permissions`
- `multiDevice`
- `ownerWebPanel`
- `commissions`
- `devicesManagement`

Mesmo que `ownerWebPanel` exista no catalogo de entitlements, o painel owner nao esta documentado aqui como produto pronto.

## Requisitos

Use as versoes definidas no repositorio:

- Flutter SDK compativel com `pubspec.yaml`: Flutter `>=3.38.0`
- Dart SDK `>=3.10.0 <4.0.0`
- Node.js `>=24.0.0`
- PostgreSQL
- Docker/Docker Compose para banco local e runtime de producao do backend
- Prisma `^6.5.0`

## Configuracao Local

### App Flutter principal

Na raiz do repositorio:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

O endpoint remoto oficial e configurado no app para uso remoto. Para desenvolvimento local, veja `lib/app/core/config` e `lib/app/core/network/endpoint_config.dart`.

### Backend

```powershell
cd backend
npm install
Copy-Item .env.example .env
docker compose up -d
npm run prisma:generate
npm run prisma:migrate:dev
npm run seed
npm run dev
```

API local:

```text
http://localhost:4000/api
```

Comandos reais do `backend/package.json`:

```bash
npm run dev
npm run build
npm test
npm start
npm run start:prod
npm run prisma:generate
npm run prisma:migrate:dev
npm run prisma:deploy
npm run prisma:status
npm run seed
npm run reset:remote-business-data
```

Validacao backend comum:

```bash
cd backend
npx prisma validate
npx prisma generate
npm run build
npm test
```

### Backend em producao/container

Arquivos reais:

- `backend/Dockerfile`
- `backend/docker-compose.prod.yml`
- `backend/Caddyfile`
- `backend/.env.production.example`

Exemplo conservador:

```powershell
cd backend
Copy-Item .env.production.example .env.production
docker compose --env-file .env.production -f docker-compose.prod.yml build
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
```

Topologia esperada pelo compose de producao:

- `edge` com Caddy escutando `80/443`
- TLS para `api.tatuzin.com.br`
- proxy apenas de `/api/*` para `backend:4000`
- backend Node em container, com healthcheck em `/api/readiness`

### Admin Web

```bash
cd admin_web
flutter pub get
flutter run -d chrome --web-port 3000
```

Build web:

```bash
cd admin_web
flutter build web
```

Para apontar o admin web para backend local:

```bash
flutter run -d chrome --web-port 3000 --dart-define=TATUZIN_ADMIN_API_URL=http://localhost:4000/api
```

Build de producao apontando para a API oficial:

```bash
flutter build web --release --dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

## Variaveis de Ambiente do Backend

Exemplos reais:

- `backend/.env.example`
- `backend/.env.production.example`

Principais variaveis:

- `PORT`
- `HOST`
- `DATABASE_URL`
- `JWT_SECRET`
- `ACCESS_TOKEN_TTL`
- `REFRESH_TOKEN_TTL_DAYS`
- `PASSWORD_RESET_TOKEN_TTL_MINUTES`
- `PASSWORD_RESET_APP_BASE_URL`
- `RESEND_API_KEY`
- `MAIL_FROM_AUTH`
- `MAIL_REPLY_TO_SUPPORT`
- `CORS_ORIGINS`
- `TRUST_PROXY`
- `APP_ENV`
- `ALLOW_INITIAL_BOOTSTRAP`
- `MERCADO_PAGO_ACCESS_TOKEN`
- `MERCADO_PAGO_WEBHOOK_SECRET`
- `API_PUBLIC_URL`
- `APP_PUBLIC_URL`
- `BILLING_BASIC_PRICE_CENTS`
- `BILLING_PRO_PRICE_CENTS`

Use valores reais apenas no ambiente. Nao commite `.env`, tokens, segredos JWT, chaves Resend ou credenciais Mercado Pago.

## Contratos Importantes

### App Context e Bootstrap

`/api/app/bootstrap` entrega contexto da empresa, usuario, device, licenca, entitlements e permissoes efetivas. O backend continua sendo fonte de verdade para:

- device
- license
- `license.plan`
- limites
- features
- billing status
- permissoes efetivas de funcionario

### Billing

O app pode listar planos, iniciar checkout, consultar status, atualizar status e executar acoes de assinatura. Ele nao ativa plano pago localmente.

### Sync

Nao altere `/api/sync/*`, materializadores ou sync policies para implementar CRUD server-first de ERP/CRM. Essas areas tem responsabilidade propria e protegida.

### Downgrade

Downgrade para FREE/BASIC bloqueia recursos pelo entitlement, mas nao apaga dados de negocio, faturas, eventos, sessoes ou `EmployeeProfile`.

## Testes e Validacao

App Flutter:

```bash
flutter analyze
flutter test
```

Backend:

```bash
cd backend
npx prisma validate
npx prisma generate
npm run build
npm test
```

Admin Web:

```bash
cd admin_web
flutter analyze
flutter test
```

## Notas de Escopo

- Este repositorio e Tatuzin ERP/SaaS.
- Nao documente arquitetura, paths, PM2, `api-go`, checkout web ou planos do TatuLog aqui.
- O backend Tatuzin ERP roda em container/Docker, com API publica em `api.tatuzin.com.br`.
- O admin web e painel da plataforma em `admin.tatuzin.com.br`.
- Painel owner ainda nao deve ser apresentado como pronto.
