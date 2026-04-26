# Deploy Oracle ARM

Guia objetivo para publicar o backend do Tatuzin em uma VM Oracle Cloud ARM 1 Flex (`linux/arm64`) usando Docker.

## Escopo

Este guia cobre:

- build da imagem com suporte a `linux/arm64`
- push para registry
- pull e subida da aplicacao na VM
- uso de `docker-compose.prod.yml`
- proxy reverso HTTPS via Caddy
- migracao Prisma explicita antes do startup
- health check, logs e rollback simples

O PostgreSQL e externo ao compose desta etapa. O container depende de `DATABASE_URL` valida e acessivel pela VM.

## Artefatos usados

- [Dockerfile](/C:/Simples/backend/Dockerfile)
- [docker-entrypoint.sh](/C:/Simples/backend/docker-entrypoint.sh)
- [docker-compose.prod.yml](/C:/Simples/backend/docker-compose.prod.yml)
- [Caddyfile](/C:/Simples/backend/Caddyfile)
- [.env.production.example](/C:/Simples/backend/.env.production.example)

## 1. Preparar o arquivo de ambiente

Na pasta `backend`, copie o exemplo e preencha os valores reais:

```bash
cp .env.production.example .env.production
```

Campos obrigatorios para producao:

- `HOST=0.0.0.0`
- `API_DOMAIN=api.tatuzin.com.br`
- `DATABASE_URL`
- `JWT_SECRET`
- `CORS_ORIGINS`
- `TRUST_PROXY`
- `RESEND_API_KEY`
- `MAIL_FROM_AUTH`
- `PASSWORD_RESET_APP_BASE_URL`
- `APP_ENV=production`

Valores recomendados para Oracle VM atras de reverse proxy:

- `HOST=0.0.0.0`
- `PORT=4000`
- `TRUST_PROXY=1`
- `RUN_DB_MIGRATIONS=false`

Se o container ficar exposto diretamente na internet, use:

- `TRUST_PROXY=false`

Variaveis novas desta base de deploy:

- `BACKEND_IMAGE`: nome/tag da imagem a ser buildada ou puxada
- `BACKEND_BIND_IP`: bind local do backend publicado no host
- `BACKEND_BIND_PORT`: porta publicada do backend no host
- `EDGE_HTTP_PORT`: porta HTTP publica do Caddy
- `EDGE_HTTPS_PORT`: porta HTTPS publica do Caddy

Se existir uma stack antiga ocupando `80`, `443` ou `127.0.0.1:4000`, ajuste essas portas antes do primeiro `up -d`.

## 2. Validar localmente antes da publicacao

No diretorio `backend`:

```bash
npm run build
npm test
docker build -t tatuzin-backend-local-check .
docker run --rm tatuzin-backend-local-check sh -lc 'echo entrypoint-ok'
```

Para validar o empacotamento ARM no host local:

```bash
docker buildx create --name tatuzin-builder --use --bootstrap
docker buildx build --platform linux/arm64 -t tatuzin-backend-arm64-check --load .
docker image inspect tatuzin-backend-arm64-check --format '{{.Architecture}}/{{.Os}}'
```

Saida esperada no inspect:

```text
arm64/linux
```

## 3. Build e push da imagem para registry

Defina a imagem final:

```bash
export BACKEND_IMAGE=ghcr.io/seu-usuario/tatuzin-backend:2026-04-20
```

Build `arm64` com push direto:

```bash
docker buildx build --platform linux/arm64 -t "$BACKEND_IMAGE" --push .
```

Opcional, se quiser publicar manifest multi-arch:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t "$BACKEND_IMAGE" -t ghcr.io/seu-usuario/tatuzin-backend:latest --push .
```

Para rollback, publique sempre com tag imutavel alem da `latest`.

## 4. Preparar a VM Oracle ARM

Assumindo que a VM ja possui Docker Engine e Docker Compose plugin instalados:

```bash
mkdir -p ~/tatuzin/backend
cd ~/tatuzin/backend
```

Copie para a VM:

- `docker-compose.prod.yml`
- `Caddyfile`
- `.env.production`

Exemplo com `scp`:

```bash
scp docker-compose.prod.yml opc@IP_DA_VM:~/tatuzin/backend/
scp Caddyfile opc@IP_DA_VM:~/tatuzin/backend/
scp .env.production opc@IP_DA_VM:~/tatuzin/backend/
```

## 5. Pull, build, migration e subida na VM

Na VM:

```bash
cd ~/tatuzin/backend
git pull origin main
docker compose --env-file .env.production -f docker-compose.prod.yml build --pull backend
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm --no-deps backend npm run prisma:deploy
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --remove-orphans
```

Comandos operacionais basicos:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml ps
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f edge backend
```

## 6. Rede e runtime

- Porta interna do backend: `4000`
- Porta de compatibilidade no host: `${BACKEND_BIND_IP}:${BACKEND_BIND_PORT}`
- Porta publica do proxy: `${EDGE_HTTP_PORT}/${EDGE_HTTPS_PORT}`
- O backend nao fica publicado diretamente no host
- Health endpoint: `GET /api/health`
- Readiness endpoint: `GET /api/readiness`
- Banco: PostgreSQL externo via `DATABASE_URL`
- Ordem de subida: banco acessivel antes de subir o backend
- Fluxo recomendado: `build --pull`, `run --rm backend npm run prisma:deploy`, depois `up -d`
- `RUN_DB_MIGRATIONS=true` fica reservado para cenarios controlados de bootstrap unico, nao como fluxo padrao
- TLS: o Caddy emite e renova certificado automaticamente para `API_DOMAIN`

## 7. Validacao na VM

Depois do `up -d`, execute:

```bash
curl -fsS "http://127.0.0.1:${BACKEND_BIND_PORT:-4000}/api/readiness"
curl -fsS http://127.0.0.1/healthz
curl -fsS "https://${API_DOMAIN}/api/health"
curl -fsS "https://${API_DOMAIN}/api/readiness"
```

Se houver proxy reverso publico, valide tambem pelo dominio final.

## 8. Rollback simples

Use um commit ou tag anterior conhecido e refaca o mesmo fluxo:

```bash
cd ~/tatuzin/backend
git checkout <tag-ou-commit-anterior>
docker compose --env-file .env.production -f docker-compose.prod.yml build --pull backend
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm --no-deps backend npm run prisma:deploy
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --remove-orphans
```

Atencao:

- rollback de imagem nao desfaz migrations ja aplicadas
- so volte para uma tag anterior se ela for compativel com o schema atual
- por isso, mantenha tags imutaveis por release se tambem publicar imagens em registry

## 9. Smoke test publicado

Checklist minimo na VM:

1. `docker compose --env-file .env.production -f docker-compose.prod.yml ps` mostra `backend` e `edge` em `Up`.
2. `GET http://127.0.0.1:${BACKEND_BIND_PORT:-4000}/api/readiness` retorna `200`.
3. `GET https://${API_DOMAIN}/api/health` retorna `200`.
4. `GET https://${API_DOMAIN}/api/readiness` retorna `200`.
5. `POST /api/auth/register` cria conta nova.
6. `POST /api/auth/login` autentica.
7. `POST /api/auth/forgot-password` aceita requisicao.
8. `POST /api/auth/reset-password` conclui redefinicao com token valido.
9. rate limit responde `429` depois das tentativas invalidas previstas.
10. logs nao exibem segredos, token de reset puro ou `JWT_SECRET`.

## 10. Riscos restantes

- `RUN_DB_MIGRATIONS=true` continua existindo como fallback, mas ainda traz risco de corrida se duas replicas tentarem subir ao mesmo tempo.
- rollback de imagem e limitado pela compatibilidade do schema ja migrado.
- o compose desta etapa nao sobe o PostgreSQL; a disponibilidade do banco continua sendo dependencia externa.
- `TRUST_PROXY` precisa refletir a topologia real da VM. Valor errado afeta IP real e rate limit.
- o Caddy depende de DNS apontando `api.tatuzin.com.br` para a VM e de portas `80/443` liberadas no firewall e no Security List/NSG da Oracle.
