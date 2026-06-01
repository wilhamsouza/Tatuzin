# CI/CD do Admin Web

Este documento define a base de CI/CD do `admin_web` para validar qualidade
antes de futuras entregas. Nesta fase, CI/CD significa padronizar comandos,
ordem de execucao e criterios de aceite. Nao ha deploy real, secrets reais,
publicacao em producao, alteracao de infraestrutura ou mudanca de backend.

## Objetivo

Garantir que o Admin Web seja validado de forma repetivel antes de evoluir
rotas, navegacao, Central de Suporte, Sync Center, Auditoria, seguranca visual e
observabilidade read-only.

O pipeline recomendado deve proteger:

- Rotas e navegacao documentadas.
- Central de Suporte da Empresa.
- Sync Center global e por empresa.
- Auditoria operacional read-only.
- Billing apenas na exibicao segura de status.
- Mascaramento/redacao de dados sensiveis.
- Ausencia de comandos reais nao autorizados.
- Observabilidade read-only sem coleta real de metricas.

## Comandos locais obrigatorios

Execute sempre dentro da pasta `admin_web`:

```powershell
cd admin_web
flutter pub get
flutter analyze
flutter test
flutter build web
```

Para build de release com API de producao documentada:

```powershell
cd admin_web
flutter build web --release --dart-define=TATUZIN_ADMIN_API_URL=https://api.tatuzin.com.br/api
```

O build local apenas gera artefato em `admin_web/build/web`. Ele nao publica,
nao faz deploy e nao altera infraestrutura.

## Ordem recomendada de pipeline

1. Checkout do repositorio.
2. Setup Flutter na versao definida pelo projeto.
3. Cache de dependencias Flutter/Dart, se o provedor de CI permitir.
4. `cd admin_web`.
5. `flutter pub get`.
6. `flutter analyze`.
7. `flutter test`.
8. `flutter build web`.
9. Upload de artefato web apenas como sugestao futura, sem deploy automatico.

## Criterios de falha

O pipeline deve falhar se qualquer item abaixo ocorrer:

- `flutter pub get` falhar.
- `flutter analyze` reportar issue.
- `flutter test` falhar.
- `flutter build web` falhar em ambiente capaz de executar build web.
- README deixar de documentar rotas principais ou docs obrigatorias.
- Testes detectarem rota owner indevida.
- Testes detectarem exposicao de token, secret ou documento completo.
- Testes detectarem comandos reais nao autorizados em telas read-only.

## Criterios de aprovacao

Uma alteracao do `admin_web` pode ser considerada validada quando:

- `flutter analyze` passa sem issues.
- `flutter test` passa.
- `flutter build web` passa, quando viavel no ambiente.
- Nao ha alteracao em backend, migrations, Android, owner_web, billing engine,
  sync engine ou contratos reais de API.
- Nao ha deploy real, secret real ou publicacao automatica em producao.

## Workflow de CI

O repositorio ainda nao possui estrutura clara de GitHub Actions na raiz, como
`.github/workflows`. Por isso, esta fase nao cria workflow real.

Quando a estrutura de CI for criada oficialmente, um workflow sugerido para o
Admin Web deve:

- Rodar apenas validacao.
- Ser limitado a `admin_web` quando possivel.
- Executar `flutter pub get`, `flutter analyze`, `flutter test` e
  `flutter build web`.
- Nao usar secrets reais.
- Nao publicar artefatos em producao.
- Nao fazer deploy automatico.
- Nao alterar backend, infraestrutura ou contratos de API.

## Limites desta fase

- Nao cria deploy real.
- Nao cria secrets.
- Nao publica build.
- Nao altera infraestrutura.
- Nao altera backend.
- Nao altera contratos de API.
- Nao cria endpoints.
- Nao muda autenticacao ou permissoes.
- Nao cria comandos operacionais reais.

## Pendencias futuras

- Definir provedor oficial de CI.
- Definir versao/pinning oficial do Flutter no pipeline.
- Criar `.github/workflows/admin_web_ci.yml` ou equivalente quando houver
  padrao de CI do repositorio.
- Definir politica de artefatos para `build/web`.
- Definir estrategia de ambientes, approvals e rollback antes de qualquer
  deploy real.
- Separar validacao de pull request de entrega para ambiente homologacao.
- Adicionar checagens futuras de tamanho de bundle, smoke test web e relatorio
  de cobertura se o projeto adotar esses criterios.
