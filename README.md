# Tatuzin Monorepo

Monorepo do Tatuzin, um ERP/PDV com app operacional local-first, backend de plataforma e painel administrativo web.

Este README descreve a arquitetura real atual do projeto. Ele nao descreve um estado idealizado e nao assume capacidades que ainda nao existem no codigo.

## Branding e publicacao

Guias praticos da identidade do Tatuzin:

- [Brand guidelines](c:/Simples/docs/tatuzin-brand-guidelines.md)
- [Brand verification checklist](c:/Simples/docs/tatuzin-brand-verification-checklist.md)

## Mapa real do monorepo

```text
.
|-- lib/                 App Tatuzin em Flutter
|-- backend/             API Node/Express + Prisma
|-- admin_web/           Painel administrativo web em Flutter
|-- android/             Shell Android do app Flutter principal
|-- test/                Testes do app Flutter principal
|-- pubspec.yaml         Dependencias do app Tatuzin
`-- README.md            Visao geral do monorepo
```

### App Tatuzin

Codigo principal em [lib](c:/Simples/lib).

Areas relevantes:

```text
lib/
|-- app/
|   |-- core/
|   |   |-- app_context/    Contexto operacional e modos de dados
|   |   |-- config/         Ambiente, endpoint e AppDataMode
|   |   |-- database/       SQLite, migrations e nomes de tabela
|   |   `-- sync/           Fila, metadata, reconciliacao e repair
|   `-- routes/             Roteamento do app
`-- modules/
    |-- dashboard
    |-- vendas
    |-- carrinho
    |-- checkout
    |-- clientes
    |-- produtos
    |-- categorias
    |-- compras
    |-- fornecedores
    |-- caixa
    |-- fiado
    |-- financeiro
    |-- relatorios
    |-- comprovantes
    |-- account
    |-- admin
    `-- system
```

### Backend

Codigo principal em [backend](c:/Simples/backend).

Areas relevantes:

```text
backend/
|-- prisma/              Schema e migrations do banco remoto
`-- src/
    |-- modules/
    |   |-- auth
    |   |-- admin
    |   |-- companies
    |   |-- users
    |   |-- categories
    |   |-- products
    |   |-- customers
    |   |-- suppliers
    |   |-- purchases
    |   |-- sales
    |   |-- financial-events
    |   |-- cash
    |   `-- fiado
    `-- shared/
        |-- http
        |-- observability
        `-- platform
```

### Admin web

Codigo principal em [admin_web](c:/Simples/admin_web).

Areas relevantes:

```text
admin_web/lib/src/
|-- app/                 Router e shell do painel
|-- core/                Auth, network, models e widgets base
`-- features/
    |-- auth
    |-- dashboard
    |-- companies
    |-- licenses
    |-- sync_health
    `-- audit
```

## Papel real de cada bloco

### App Tatuzin

O app Tatuzin e a superficie operacional principal do produto. Ele concentra:

- operacao de PDV e ERP no dispositivo
- persistencia local em SQLite
- fluxo local-first/offline-first
- fila de sync, metadata de sincronizacao, reconciliacao e repair
- experiencia de uso do operador final

Na pratica, o app continua sendo o bloco mais rico em regra operacional e o mais avancado em preparacao para sync.

### Backend

O backend e um monolito modular de plataforma. Hoje ele cobre principalmente:

- autenticacao e sessao remota
- licenciamento
- companies e memberships
- operacao administrativa de plataforma
- espelho remoto de entidades operacionais
- suporte a multi-tenant por company

O backend ja atende o necessario para login remoto, licenciamento, sessao por dispositivo e persistencia remota das entidades suportadas. Ele ainda nao opera como uma camada completa de reconciliacao, conflito e telemetria profunda de sync.

### Admin web

O admin web e a superficie administrativa principal da plataforma. Hoje ele cobre:

- login administrativo
- dashboard resumido
- listagem e detalhe de empresas
- gestao de licencas
- visao resumida de sync
- auditoria administrativa

Ele nao substitui o app operacional e nao executa vendas, caixa, compras ou operacao diaria do cliente.

## Estrategia atual local-first / offline-first

O projeto foi implementado com SQLite local como base operacional do app. O modo de dados do app fica em [app_data_mode.dart](c:/Simples/lib/app/core/config/app_data_mode.dart) e a politica de acesso em [data_access_policy.dart](c:/Simples/lib/app/core/app_context/data_access_policy.dart).

Os modos atuais sao:

- `localOnly`
  - SQLite local e a unica fonte de dados.
  - Sem leitura remota.
  - Sem escrita remota.
- `futureRemoteReady`
  - SQLite local continua como fonte principal.
  - Leitura remota e permitida quando houver sessao e sync habilitada para a empresa.
  - Escrita remota ainda nao e permitida.
- `futureHybridReady`
  - SQLite local continua como base principal.
  - Leitura remota e permitida.
  - Escrita remota e permitida.
  - Este modo e a base para o fluxo local-first com sincronizacao.

Em todos os modos, o app foi desenhado para manter a base local como fonte operacional primaria. O backend nao substitui o banco local do app.

## Status real do sync

O app possui infraestrutura local de sync em [lib/app/core/sync](c:/Simples/lib/app/core/sync), incluindo:

- fila de sync
- metadata por registro
- auditoria local de sync
- readiness
- reconciliacao local/remota
- repair mode

As chaves de feature atualmente previstas no app estao em [sync_feature_keys.dart](c:/Simples/lib/app/core/sync/sync_feature_keys.dart):

- `suppliers`
- `categories`
- `products`
- `customers`
- `purchases`
- `sales`
- `financial_events`
- `sale_cancellations`
- `fiado_payments`
- `cash_events`
- `fiado`
- `cash_movements`

### O que ja tem suporte de sincronizacao/espelho no projeto

Com base no app e nas rotas/modulos existentes no backend, o projeto ja tem base de sync ou espelho remoto para:

- categorias
- produtos
- clientes
- fornecedores
- compras
- vendas
- eventos financeiros
- eventos de caixa
- dados administrativos da plataforma, como licenca, sessao e company

### O que ainda e espelho parcial

Hoje o backend ainda se comporta mais como espelho remoto por entidade do que como uma plataforma completa de reconciliacao de dados. Na pratica, isso significa:

- o app carrega mais inteligencia de sync do que o servidor
- a idempotencia e o mapeamento remoto existem, mas a resolucao de conflito do lado do backend ainda e limitada
- a operacao administrativa de sync ainda e mais resumida do que a complexidade real que existe no app

### O que ainda nao tem telemetria suficiente

O projeto ainda nao oferece telemetria operacional profunda de sync para suporte de plataforma. Hoje faltam, de forma clara:

- trilha detalhada de incidentes por tenant/feature
- diagnostico forte de conflito no backend
- visao consolidada de fila local do app no admin web
- observabilidade mais profunda para reconciliacao e retry

O painel admin web mostra saude resumida e volume remoto, mas isso ainda nao equivale a diagnostico completo de sincronizacao.

## Responsabilidades e limites atuais

### App Tatuzin

- responsavel pela operacao de ERP/PDV
- responsavel pela persistencia local
- responsavel pela experiencia offline/local-first
- contem uma area administrativa interna em [admin_page.dart](c:/Simples/lib/modules/admin/presentation/pages/admin_page.dart), mas essa area deve ser tratada como apoio temporario/interno

### Backend

- responsavel por auth, licenciamento, companies, memberships e sessao remota
- responsavel por persistencia remota das entidades operacionais suportadas
- nao e a fonte primaria de operacao do app
- nao substitui a camada local de sync/reconciliacao existente no cliente

### Admin web

- e a superficie administrativa principal do projeto neste momento
- consome capacidades administrativas ja expostas pelo backend
- serve para operacao de plataforma, nao para operacao de PDV

## Decisao atual de produto e arquitetura

Neste repositorio existem duas superficies administrativas:

- admin web em [admin_web](c:/Simples/admin_web)
- admin interno no app em [lib/modules/admin](c:/Simples/lib/modules/admin)

Decisao atual:

- o admin web e a superficie administrativa principal
- o admin interno do app permanece apenas como apoio temporario/interno
- novas capacidades administrativas devem priorizar o admin web, salvo necessidade explicita de suporte interno no app

## Limitacoes atuais importantes

As limitacoes abaixo fazem parte do estado atual do projeto e devem ser consideradas reais:

- o README anterior do monorepo estava desatualizado e em conflito
- o app ja possui infraestrutura de sync mais avancada do que o backend/admin conseguem operar
- o backend ainda concentra mais capacidade em auth/licenciamento do que em observabilidade de sync
- o admin web ainda cobre a operacao administrativa principal, mas nao oferece diagnostico profundo de sync
- existem modulos do app que estao preparados para sync futura, mesmo quando a operacao remota correspondente ainda e parcial
- a experiencia administrativa ainda esta dividida entre app interno e admin web, embora a direcao atual seja centralizar no admin web

## Como rodar cada bloco

### App Tatuzin

No diretorio raiz:

```powershell
flutter pub get
flutter run
```

### Backend

Veja [backend/README.md](c:/Simples/backend/README.md) para setup de banco, Prisma, seed e execucao da API.

### Admin web

Veja [admin_web/README.md](c:/Simples/admin_web/README.md) para rodar o painel apontando para o backend local.
