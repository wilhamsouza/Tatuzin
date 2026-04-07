# Tatuzin Admin Web

Painel administrativo web separado do app operacional do cliente.

## O que este projeto faz

- autentica administradores da plataforma
- lista empresas e licencas
- permite editar licencas
- mostra saude resumida da sync
- mostra auditoria administrativa

## O que este projeto nao faz

- nao substitui o app mobile do cliente
- nao executa operacao de vendas, caixa, compras ou relatorios
- nao altera a fonte de verdade offline-first do cliente

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
