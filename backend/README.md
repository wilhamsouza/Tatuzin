# Tatuzin Backend

Backend de plataforma do Tatuzin.

Este projeto nao e um backend generico de ERP completo. Hoje ele atua principalmente como camada de plataforma para autenticacao, sessao, licenciamento, multi-tenant administrativo e persistencia remota das entidades operacionais suportadas.

## Papel real do backend hoje

O backend cobre principalmente:

- autenticacao, refresh token e redefinicao de senha
- sessoes por dispositivo
- companies e memberships
- licenciamento
- operacao administrativa da plataforma
- espelho remoto de dados operacionais suportados
- health/readiness e logs estruturados

Modulos atuais em [src/modules](c:/Simples/backend/src/modules):

- `auth`
- `admin`
- `companies`
- `users`
- `categories`
- `products`
- `customers`
- `suppliers`
- `supplies`
- `purchases`
- `sales`
- `product-recipes`
- `financial-events`
- `cash`
- `fiado`

## O que o backend nao deve ser descrito como sendo hoje

O backend ainda nao deve ser descrito como:

- unica fonte de verdade operacional do app
- camada completa de reconciliacao de conflitos
- plataforma com telemetria profunda de sync
- substituto da base SQLite local do Tatuzin

Na pratica, ele atende autenticacao, sessao, licenciamento e persistencia remota das entidades suportadas, mas a observabilidade de sync ainda e resumida.

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

Variaveis mais importantes:

- `HOST`: interface de bind HTTP do processo Node
- `DATABASE_URL`: conexao PostgreSQL
- `JWT_SECRET`: segredo do JWT, minimo de 16 caracteres
- `APP_ENV`: `local-development` ou `production`
- `CORS_ORIGINS`: lista separada por virgula
- `TRUST_PROXY`: configuracao repassada ao Express para ambientes atras de proxy
- `RATE_LIMIT_BUCKET_RETENTION_MINUTES`: tempo de retencao da limpeza de buckets de rate limit persistidos
- `PASSWORD_RESET_APP_BASE_URL`: URL HTTPS ou deep link do app para reset de senha
- `RESEND_API_KEY`, `MAIL_FROM_AUTH` e `MAIL_REPLY_TO_SUPPORT`: entrega de e-mails

Obrigatorias em producao:

- `APP_ENV=production`
- `HOST=0.0.0.0`
- `DATABASE_URL`
- `JWT_SECRET`
- `RESEND_API_KEY`
- `MAIL_FROM_AUTH`
- `PASSWORD_RESET_APP_BASE_URL`

### Como configurar `TRUST_PROXY`

Use o menor escopo confiavel possivel:

- `TRUST_PROXY=false`: backend exposto diretamente, sem proxy reverso na frente
- `TRUST_PROXY=1`: um proxy reverso confiavel na frente do app
- `TRUST_PROXY=2`: dois hops confiaveis
- `TRUST_PROXY=loopback,linklocal,uniquelocal`: lista explicita de faixas confiaveis

Nao use `true` por padrao em producao sem saber exatamente quantos proxies confiaveis existem na cadeia.

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

## Rodar API localmente

```powershell
npm run dev
```

Base local:

- `http://localhost:4000/api`

## Build e deploy com Docker

O repositorio agora inclui um `Dockerfile` multi-stage e um entrypoint de producao.

Para deploy em Oracle Cloud ARM 1 Flex com Docker, use o guia dedicado em [DEPLOY_ORACLE_ARM.md](/C:/Simples/backend/DEPLOY_ORACLE_ARM.md).

Build da imagem:

```powershell
docker build -t tatuzin-backend .
```

Exemplo de execucao local em container apontando para um PostgreSQL do host no Windows:

```powershell
docker run --rm `
  -p 4000:4000 `
  --env-file .env `
  -e APP_ENV=production `
  -e DATABASE_URL="postgresql://postgres:postgres@host.docker.internal:5432/simples_erp_dev?schema=public" `
  -e TRUST_PROXY=1 `
  -e RUN_DB_MIGRATIONS=true `
  tatuzin-backend
```

Detalhes importantes do runtime de producao:

- executa `npm run prisma:deploy` automaticamente no startup quando `RUN_DB_MIGRATIONS=true`
- backend responde internamente em `4000`
- `docker-compose.prod.yml` publica `80/443` via Caddy
- inclui `HEALTHCHECK` em `/api/health`
- inicia com `NODE_ENV=production`

Em orquestradores como Render, Railway, Fly.io, ECS ou Kubernetes, a configuracao equivalente e:

- imagem gerada por `docker build`
- `APP_ENV=production`
- `TRUST_PROXY` ajustado para a cadeia de proxy real
- `RUN_DB_MIGRATIONS=true` apenas se o deploy puder serializar migracoes com seguranca

## Publicacao HTTPS de producao

O repositório agora inclui uma borda HTTPS minima para producao:

- [docker-compose.prod.yml](/C:/Simples/backend/docker-compose.prod.yml)
- [Caddyfile](/C:/Simples/backend/Caddyfile)

Topologia esperada:

- `edge` escuta `80/443`
- `edge` encerra TLS para `api.tatuzin.com.br`
- `edge` encaminha apenas `/api/*` para `backend:4000`
- `backend` nao expõe `4000` publicamente no host

- `backend` publica `127.0.0.1:4000` apenas para compatibilidade com um proxy reverso de host ja existente

Variaveis adicionais no `.env.production`:

- `API_DOMAIN=api.tatuzin.com.br`
- `HOST=0.0.0.0`

Observacao de CORS:

- o app Flutter nativo nao depende de CORS de navegador
- o `admin_web` precisa estar presente em `CORS_ORIGINS`
- se surgir um frontend web adicional, adicione sua origin explicitamente em `CORS_ORIGINS`

## Contrato de paginacao das listas operacionais

As listas operacionais suportam `page` e `pageSize` via query string.

Resposta padrao:

```json
{
  "items": [],
  "page": 1,
  "pageSize": 25,
  "total": 0,
  "count": 0,
  "hasNext": false,
  "hasPrevious": false
}
```

Isso vale para rotas como:

- `GET /api/categories`
- `GET /api/products`
- `GET /api/customers`
- `GET /api/suppliers`
- `GET /api/supplies`
- `GET /api/purchases`
- `GET /api/sales`
- `GET /api/product-recipes`
- `GET /api/financial-events`

O conjunto exato de rotas deve ser lido no codigo. Este README serve como mapa funcional, nao como referencia exaustiva de API.

## Endpoints administrativos e operacionais principais

Exemplos de rotas atualmente expostas:

- `GET /api/health`
- `GET /api/readiness`
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

## Checklist minima antes de producao

- `npm test`
- `npm run build`
- `npx prisma migrate status`
- segredos reais em `JWT_SECRET` e `RESEND_API_KEY`
- `PASSWORD_RESET_APP_BASE_URL` apontando para URL/deep link real
- `TRUST_PROXY` ajustado ao proxy real
- banco PostgreSQL com backup e observabilidade basica
- CORS restrito aos frontends autorizados

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
