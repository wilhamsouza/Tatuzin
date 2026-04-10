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

1. garanta que o backend esteja rodando em `http://localhost:4000`
2. no diretorio `admin_web`, execute:

```powershell
flutter pub get
flutter run -d chrome --web-port 3000 --dart-define=TATUZIN_ADMIN_API_URL=http://localhost:4000/api
```

## Como gerar build web

```powershell
flutter build web --dart-define=TATUZIN_ADMIN_API_URL=http://localhost:4000/api
```

## Limitacoes atuais importantes

- o dashboard e resumido, nao substitui troubleshooting tecnico profundo
- a tela de sync mostra saude resumida e volume remoto, nao a telemetria completa do app local
- a cobertura administrativa depende diretamente das capacidades ja expostas pelo backend
