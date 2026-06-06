# Tatuzin Owner Web

Painel de gestão da empresa do cliente Tatuzin. Este app é separado do
`admin_web`: o domínio `painel.tatuzin.com.br` é para o dono ou gestor da
empresa acompanhar o negócio, enquanto `admin.tatuzin.com.br` continua
exclusivo para plataforma/suporte interno.

Esta fase mantém o painel em modo consulta. O app não implementa ações de
escrita, não usa arquitetura local-first e não depende do `admin_web`.

## Stack

- Flutter Web
- Riverpod
- GoRouter
- `http`
- `shared_preferences`

## Rotas Frontend

- `/login`
- `/privacidade` (pública)
- `/exclusao-de-dados` (pública)
- `/dashboard`
- `/sales`
- `/clients`
- `/finance`
- `/products`
- `/reports`
- `/company`
- `/billing`
- `/employees`
- `/devices`
- `/settings`

Não existe rota `/admin` neste app.

## Endpoints HTTP Consumidos

Autenticação segura:

- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`

Dados read-only do painel da empresa:

- `GET /api/owner/company`
- `GET /api/owner/dashboard`
- `GET /api/owner/billing/status`
- `GET /api/owner/billing/invoices`
- `GET /api/owner/employees`
- `GET /api/owner/devices`

O app não consome `/api/admin/*`, `/api/billing/*`, `/api/employees/*` ou
`/api/sync/*` diretamente. A rota visual `/billing` consome somente
`/api/owner/billing/*`, a rota visual `/employees` consome somente
`/api/owner/employees`, e os cards gerenciais sem endpoint real mostram estados
vazios honestos.

## Produto

O painel é organizado como uma ferramenta de acompanhamento gerencial:

- Dashboard
- Vendas
- Clientes / CRM
- Fiado e financeiro
- Produtos e estoque
- Funcionários
- Relatórios
- Assinatura e cobranças
- Configurações

Enquanto o backend ainda não expõe relatórios gerenciais reais, as telas de
vendas, CRM, financeiro, produtos, estoque, funcionários e relatórios mostram
estados vazios amigáveis em vez de métricas inventadas.

## Configuração

O backend de produção esperado é:

```text
https://api.tatuzin.com.br/api
```

O app lê a URL via `TATUZIN_OWNER_API_URL`. O valor deve incluir o sufixo
`/api` e o código normaliza apenas a barra final para evitar duplicações.

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

Diretório gerado:

```text
owner_web/build/web
```

Também existe um script auxiliar:

```bash
bash owner_web/scripts/build_release.sh
```

O script executa `flutter pub get`, `flutter analyze`, `flutter test` e o build
release com `TATUZIN_OWNER_API_URL=https://api.tatuzin.com.br/api`.

## Deploy Estático

Subdomínio recomendado:

```text
painel.tatuzin.com.br
```

O painel da empresa deve ser publicado como site estático Flutter Web. O exemplo de
Nginx fica em:

```text
owner_web/deploy/nginx-owner-web.example.conf
```

Esse exemplo serve apenas o conteúdo estático do Flutter Web e não configura
proxy para `/api`, porque o app chama `https://api.tatuzin.com.br/api` via
`--dart-define`.

Publicação manual sugerida:

```bash
cd owner_web
flutter pub get
flutter analyze
flutter test
flutter build web --release --dart-define=TATUZIN_OWNER_API_URL=https://api.tatuzin.com.br/api
```

No servidor web:

```bash
sudo mkdir -p /var/www/tatuzin/owner_web
rsync -av --delete owner_web/build/web/ usuario@servidor:/var/www/tatuzin/owner_web/
sudo nginx -t
sudo systemctl reload nginx
```

Ajuste `usuario@servidor` e o caminho `/var/www/tatuzin/owner_web` conforme o
ambiente real. Não execute deploy real a partir deste repositório sem confirmar
o servidor de destino.

## DNS e SSL

DNS:

- Criar um registro `A` ou `CNAME` para `painel.tatuzin.com.br`, apontando para
  o servidor web ou CDN escolhido.

SSL:

- Configurar certificado TLS para `painel.tatuzin.com.br`.
- Se o ambiente usa Nginx com Certbot, um fluxo comum é:

```bash
sudo certbot --nginx -d painel.tatuzin.com.br
```

Headers recomendados no servidor:

- `X-Frame-Options SAMEORIGIN`
- `X-Content-Type-Options nosniff`
- `Referrer-Policy strict-origin-when-cross-origin`
- `Permissions-Policy` básica

CSP deve ser avaliada com cuidado em ambiente real, porque Flutter Web pode
precisar de scripts e assets específicos conforme a estratégia de build.

## Segurança

- Modo consulta nesta fase.
- Não implementa cancelamento, troca de plano, refresh de billing, bloqueio de
  dispositivo ou CRUD.
- Não exibe `providerSubscriptionId` completo.
- Não exibe payloads Mercado Pago, tokens, secrets, `inviteTokenHash` ou
  `clientInstanceId` completo.
- Não usa SQLite nem arquitetura local-first.
- Não usa `/api/admin/*`.
- Não deve ser publicado em `admin.tatuzin.com.br`.
