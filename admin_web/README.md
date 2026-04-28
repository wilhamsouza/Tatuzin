# Tatuzin Admin Web

Painel administrativo web da plataforma Tatuzin.

Este projeto e a superficie administrativa principal do repositorio neste momento. Ele nao substitui o app operacional do cliente e nao deve ser descrito como console completo de diagnostico de sync.

## Papel real do admin web hoje

O painel cobre:

- login administrativo
- dashboard resumido
- listagem e detalhe de empresas
- gestao de licencas
- saude resumida de sync
- auditoria administrativa

Rotas atuais em [admin_web_router.dart](c:/Simples/admin_web/lib/src/app/admin_web_router.dart):

- `/login`
- `/dashboard`
- `/companies`
- `/companies/:companyId`
- `/licenses`
- `/sync-health`
- `/audit`

## O que este projeto nao faz

- nao executa operacao de vendas, caixa, compras ou relatorios do cliente
- nao substitui o app Tatuzin
- nao substitui o banco local SQLite
- nao oferece hoje diagnostico profundo de fila local, conflito e reconciliacao

## Relacao com o admin interno do app

Existe uma superficie administrativa interna no app principal, em [lib/modules/admin](c:/Simples/lib/modules/admin).

Estado atual documentado:

- o admin web e a superficie administrativa principal
- o admin interno do app permanece apenas como apoio temporario/interno

## Dependencia do backend

Este painel depende do backend em [backend](c:/Simples/backend) para:

- autenticacao
- consulta de empresas
- gestao de licencas
- resumo de sync
- auditoria

Se o backend nao estiver disponivel, o painel nao opera.

## Como rodar localmente

1. por padrao o painel usa `https://api.tatuzin.com.br/api`
2. no diretorio `admin_web`, execute:

```powershell
flutter pub get
flutter run -d chrome --web-port 3000
```

## Como gerar build web

Build local apontando para a API oficial:

```powershell
flutter build web
```

Para desenvolvimento contra backend local, informe explicitamente:

```powershell
flutter run -d chrome --web-port 3000 --dart-define=TATUZIN_ADMIN_API_URL=http://localhost:4000/api
```

Build de producao para publicar o admin em `https://admin.tatuzin.com.br` consumindo a API em `https://api.tatuzin.com.br`:

```powershell
flutter build web --release --dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

Observacoes importantes para producao:

- a base URL precisa incluir o prefixo `/api`
- o build release nao deve mais cair silenciosamente para `localhost`; se `TATUZIN_ADMIN_API_URL` faltar, o painel falha cedo
- como o projeto usa `usePathUrlStrategy()`, o servidor web precisa servir `index.html` nas rotas profundas
- para publicar em subdominio raiz como `admin.tatuzin.com.br`, o `<base href="/">` atual ja esta correto

## Limitacoes atuais importantes

- o dashboard e resumido, nao substitui troubleshooting tecnico profundo
- a tela de sync mostra saude resumida e volume remoto, nao a telemetria completa do app local
- a cobertura administrativa depende diretamente das capacidades ja expostas pelo backend
