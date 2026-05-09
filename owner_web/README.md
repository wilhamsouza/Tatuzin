# Tatuzin Owner Web

Painel web read-only do dono da empresa Tatuzin. Este app é separado do `admin_web`: o futuro domínio `painel.tatuzin.com.br` é para clientes owners, enquanto `admin.tatuzin.com.br` continua exclusivo para plataforma/suporte interno.

## Stack

- Flutter Web
- Riverpod
- GoRouter
- `http`
- `shared_preferences`

## Rotas

- `/login`
- `/dashboard`
- `/company`
- `/billing`
- `/employees`
- `/devices`

Não existe rota `/admin` neste app.

## Endpoints Consumidos

Autenticação segura:

- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`

Dados read-only do owner:

- `GET /api/owner/company`
- `GET /api/owner/dashboard`
- `GET /api/owner/billing/status`
- `GET /api/owner/billing/invoices`
- `GET /api/owner/employees`
- `GET /api/owner/devices`

O app não consome `/api/admin/*`, `/api/billing/*`, `/api/employees/*` ou `/api/sync/*`.

## Configuração

Rodar localmente:

```bash
cd owner_web
flutter pub get
flutter run -d chrome --dart-define=TATUZIN_OWNER_API_URL=https://api.tatuzin.com.br/api
```

Build de produção:

```bash
cd owner_web
flutter build web --release --dart-define=TATUZIN_OWNER_API_URL=https://api.tatuzin.com.br/api
```

## Segurança

- Read-only nesta fase.
- Não implementa cancelamento, troca de plano, refresh de billing, bloqueio de dispositivo ou CRUD.
- Não exibe `providerSubscriptionId` completo.
- Não exibe payloads Mercado Pago, tokens, secrets, `inviteTokenHash` ou `clientInstanceId` completo.
- Não usa SQLite nem arquitetura local-first.
