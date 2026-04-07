# Simples ERP Backend

API real de desenvolvimento para autenticacao, sessao remota e tenant/company.

## Stack

- Node.js 24+
- Express + TypeScript
- Prisma
- PostgreSQL

## Variaveis de ambiente

Copie o exemplo:

```powershell
Copy-Item .env.example .env
```

Se for usar o PostgreSQL isolado em porta alternativa, ajuste `DATABASE_URL` no `.env`.

## Opcao A: PostgreSQL via Docker

```powershell
docker compose up -d
```

Depois mantenha:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/simples_erp_dev?schema=public
```

## Opcao B: PostgreSQL isolado local

Usada na validacao desta fase quando o Docker nao estava disponivel.

```powershell
New-Item -ItemType Directory -Force -Path .local-postgres\data | Out-Null
& 'C:\Program Files\PostgreSQL\17\bin\initdb.exe' -D .local-postgres\data -U postgres -A trust
& 'C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe' -D .local-postgres\data -l .local-postgres\server.log -o "-p 55432" start
& 'C:\Program Files\PostgreSQL\17\bin\createdb.exe' -h localhost -p 55432 -U postgres simples_erp_dev
```

E no `.env`:

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

- E-mail: `admin@simples.local`
- Senha: `123456`

## Rodar API

```powershell
npm run dev
```

API base: `http://localhost:4000/api`

## Endpoints principais

- `GET /api/health`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `GET /api/companies/current`
- `GET /api/products`
- `POST /api/products`
- `PUT /api/products/:id`
- `DELETE /api/products/:id`
- `GET /api/products/:id`
- `GET /api/categories`
- `POST /api/categories`
- `PUT /api/categories/:id`
- `DELETE /api/categories/:id`
- `GET /api/customers`
- `POST /api/customers`
- `PUT /api/customers/:id`
- `DELETE /api/customers/:id`
- `GET /api/customers/:id`
- `POST /api/auth/register-initial`
- `POST /api/auth/logout`

## Limpeza segura dos dados remotos operacionais

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

Se voce realmente precisar executar contra um banco nao local em ambiente controlado, use conscientemente:

```powershell
$env:ALLOW_REMOTE_BUSINESS_RESET='true'
$env:ALLOW_NON_LOCAL_DATABASE_RESET='true'
npm run reset:remote-business-data
```

Nao use esse script em producao.
