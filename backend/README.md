# Tatuzin Backend

Backend de plataforma do Tatuzin.

Este projeto nao e um backend generico de ERP completo. Hoje ele atua principalmente como camada de plataforma para autenticacao, sessao, licenciamento, multi-tenant administrativo e persistencia remota das entidades operacionais suportadas.

## Papel real do backend hoje

O backend cobre principalmente:

- autenticacao e refresh token
- sessoes por dispositivo
- companies e memberships
- licenciamento
- operacao administrativa da plataforma
- espelho remoto de dados operacionais

Modulos atuais em [src/modules](c:/Simples/backend/src/modules):

- `auth`
- `admin`
- `companies`
- `users`
- `categories`
- `products`
- `customers`
- `suppliers`
- `purchases`
- `sales`
- `financial-events`
- `cash`
- `fiado`

## O que o backend nao deve ser descrito como sendo hoje

O backend ainda nao deve ser descrito como:

- unica fonte de verdade operacional do app
- camada completa de reconciliacao de conflitos
- plataforma com telemetria profunda de sync
- substituto da base SQLite local do Tatuzin

Na pratica, ele ja atende autenticacao, sessao, licenciamento e persistencia remota das entidades suportadas, mas a observabilidade de sync ainda e resumida.

## Banco e stack

- Node.js 24+
- Express + TypeScript
- Prisma
- PostgreSQL

Schema e migrations ficam em [prisma](c:/Simples/backend/prisma).

## Variaveis de ambiente

Copie o exemplo:

```powershell
Copy-Item .env.example .env
```

Se for usar PostgreSQL isolado em porta alternativa, ajuste `DATABASE_URL` no `.env`.

## Opcao A: PostgreSQL via Docker

```powershell
docker compose up -d
```

Use:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/simples_erp_dev?schema=public
```

## Opcao B: PostgreSQL isolado local

```powershell
New-Item -ItemType Directory -Force -Path .local-postgres\data | Out-Null
& 'C:\Program Files\PostgreSQL\17\bin\initdb.exe' -D .local-postgres\data -U postgres -A trust
& 'C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe' -D .local-postgres\data -l .local-postgres\server.log -o "-p 55432" start
& 'C:\Program Files\PostgreSQL\17\bin\createdb.exe' -h localhost -p 55432 -U postgres simples_erp_dev
```

No `.env`:

```env
DATABASE_URL=postgresql://postgres@localhost:55432/simples_erp_dev?schema=public
```

Para parar o cluster local:

```powershell
& 'C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe' -D .local-postgres\data stop
```

## Instalar dependencias

```powershell
npm install
```

## Prisma

```powershell
npm run prisma:generate
npx prisma migrate dev --skip-seed
npm run seed
```

## Usuario seeded

- e-mail: `admin@simples.local`
- senha: `123456`

## Rodar API

```powershell
npm run dev
```

Base local:

- `http://localhost:4000/api`

## Endpoints administrativos e operacionais principais

Exemplos de rotas atualmente expostas:

- `GET /api/health`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/logout`
- `GET /api/admin/companies`
- `GET /api/admin/licenses`
- `GET /api/admin/sync/summary`
- `GET /api/admin/audit/summary`
- `GET /api/categories`
- `GET /api/products`
- `GET /api/customers`
- `GET /api/suppliers`
- `GET /api/purchases`
- `GET /api/sales`

O conjunto exato de rotas deve ser lido no codigo. Este README serve como mapa funcional, nao como referencia exaustiva de API.

## Reset seguro de dados remotos operacionais

Use este reset apenas em ambiente local/dev quando precisar limpar o espelho remoto operacional e repovoar o backend via sync do app.

O script preserva:

- users
- companies
- memberships
- licenses
- auth/admin role
- auditoria administrativa por padrao

O script remove:

- categorias remotas
- produtos remotos
- clientes remotos
- fornecedores remotos
- compras, itens e pagamentos remotos
- vendas e itens remotos
- pagamentos de fiado remotos
- eventos financeiros remotos
- eventos de caixa remotos

Execucao padrao:

```powershell
$env:ALLOW_REMOTE_BUSINESS_RESET='true'
npm run reset:remote-business-data
```

Protecoes:

- aborta sem `ALLOW_REMOTE_BUSINESS_RESET=true`
- aborta em `NODE_ENV=production`
- aborta por padrao se o `DATABASE_URL` nao apontar para host local

Opcao adicional para limpar tambem a auditoria administrativa:

```powershell
$env:ALLOW_REMOTE_BUSINESS_RESET='true'
$env:CLEAN_ADMIN_AUDIT='true'
npm run reset:remote-business-data
```

Se realmente precisar executar contra um banco nao local em ambiente controlado:

```powershell
$env:ALLOW_REMOTE_BUSINESS_RESET='true'
$env:ALLOW_NON_LOCAL_DATABASE_RESET='true'
npm run reset:remote-business-data
```

Nao use esse script em producao.

## Limitacoes atuais relevantes

- a camada administrativa e mais madura em auth/licenciamento do que em telemetria de sync
- o backend suporta espelho remoto e operacao administrativa, mas ainda nao oferece diagnostico profundo de conflitos
- o painel admin web depende deste backend para operacao de plataforma; ele nao substitui o app local-first
