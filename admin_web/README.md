# Tatuzin Admin Web

Painel web interno da plataforma Tatuzin, usado por suporte e operação. Este
projeto é **platform admin** e não é painel owner do cliente.

O admin web consome rotas `/api/admin/*` do backend Tatuzin ERP. Ele não deve
ser usado para atender fluxos owner, não deve criar rota `/owner` e não deve
consumir `/api/owner/*`.

## Stack

- Flutter Web
- Riverpod
- GoRouter
- `http`
- `shared_preferences`

## Rotas atuais

Rotas registradas em
[`admin_web_router.dart`](c:/Simples/admin_web/lib/src/app/admin_web_router.dart):

- `/login`
- `/dashboard`
- `/management/dashboard`
- `/management/reports`
- `/management/governance`
- `/management/crm/customers`
- `/management/crm/customers/:customerId`
- `/companies`
- `/companies/:companyId`
- `/licenses`
- `/billing`
- `/billing/:companyId`
- `/sync-health`
- `/audit`

## Áreas do painel

- Login administrativo e restauração de sessão.
- Dashboard resumido de plataforma.
- Empresas e detalhes administrativos.
- Licenças legadas, mantidas para suporte e depreciadas para billing Mercado
  Pago.
- Billing Admin Seguro para investigação e correção administrativa auditada de
  assinaturas.
- Sync Health resumido.
- Auditoria administrativa.
- Dashboard, relatórios, governança híbrida e CRM gerencial de plataforma.

## Billing Admin

A área `/billing` é interna de plataforma/suporte. Ela consome:

- `GET /api/admin/billing/companies`
- `GET /api/admin/companies/:companyId/billing/status`
- `GET /api/admin/companies/:companyId/billing/events`
- `GET /api/admin/companies/:companyId/billing/checkout-sessions`
- `POST /api/admin/companies/:companyId/billing/refresh`
- `POST /api/admin/companies/:companyId/billing/force-plan`
- `POST /api/admin/companies/:companyId/billing/cancel-local`

Regras de segurança no painel:

- Listagens nunca exibem `providerSubscriptionId` completo.
- Payloads/eventos são sanitizados defensivamente antes de renderizar.
- URLs completas de checkout não são renderizadas nem copiáveis.
- `cancel-local` deixa claro que não cancela Mercado Pago.
- Tokens, Authorization, webhook secrets e payloads sensíveis não devem aparecer
  em UI ou logs.

## Licenças legadas

A rota `/licenses` continua disponível, mas está depreciada para assinaturas
Mercado Pago. Edições diretas exigem motivo visual local e confirmação final.
Esse motivo não é auditoria backend, porque o endpoint legado de licença não
aceita `reason`.

Para assinaturas Mercado Pago, use Billing Admin.

## Configuração da API

A URL base é definida por `TATUZIN_ADMIN_API_URL` via `--dart-define`. O código
também possui default de produção em `AdminEnv`, portanto um build release não
falha apenas pela ausência da variável.

A URL deve incluir o prefixo `/api`, por exemplo:

```powershell
--dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

## Como rodar localmente

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port 3000 --dart-define=TATUZIN_ADMIN_API_URL=http://localhost:4000/api
```

## Build web

Build de produção para publicar o admin em `https://admin.tatuzin.com.br`:

```powershell
cd admin_web
flutter build web --release --dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

Como o projeto usa `usePathUrlStrategy()`, o servidor web precisa servir
`index.html` nas rotas profundas.

## O que este projeto não faz

- Não é painel owner.
- Não executa operação de vendas, caixa, compras ou relatórios do cliente.
- Não substitui o app Tatuzin.
- Não substitui SQLite/local-first do PDV.
- Não transforma ERP/CRM em local-first.
- Não consome `/api/owner/*`.

