# Fechamento do Roadmap Admin Web Tatuzin

Este relatorio registra o estado do `admin_web` apos a conclusao das 12 fases
iniciais do roadmap. Ele consolida o que foi entregue, o que permanece
read-only por design, as dependencias futuras e os proximos epicos recomendados.

## Resumo executivo

O objetivo original do roadmap era organizar o `admin_web` e transforma-lo na
base de uma plataforma interna de suporte ao app Android e a operacao da
plataforma Tatuzin, sem misturar fluxos owner, sem alterar backend e sem criar
acoes reais antes de contratos, permissoes e auditoria.

O resultado alcancado e um Admin Web mais claro, navegavel e orientado a
suporte, com Central de Suporte da Empresa, console operacional read-only,
Sync Center, Auditoria Operacional, documentacao de contratos, seguranca,
observabilidade, CI/CD, controle futuro de versao Android e preparacao para
Push Notification / FCM.

Estado atual:

- Painel interno da plataforma, separado do `owner_web`.
- Navegacao documentada e padronizada.
- Rotas principais cobertas por testes.
- Central de Suporte da Empresa disponivel em `/companies/:companyId/support`.
- Consoles operacionais read-only para usuarios, funcionarios, dispositivos,
  sessoes, sync, billing, auditoria, seguranca e observabilidade.
- Documentacao criada para contratos, seguranca, observabilidade, CI/CD, versao
  Android e FCM.
- Nenhum backend, Android, owner_web, migration, sync engine, billing engine,
  Firebase real, endpoint novo, contrato real ou deploy real foi criado por
  este roadmap.

## Escopo mantido

Durante as 12 fases, o trabalho ficou restrito ao `admin_web`, README,
documentacao em `admin_web/docs`, paginas/widgets do admin e testes do
admin_web. As evolucoes foram feitas para preparar diagnostico e suporte, sem
executar comandos operacionais reais.

## Fases concluidas

### 1. Organizacao do Admin Web

Objetivo: organizar o `admin_web` como painel interno de plataforma e separar
conceitualmente do `owner_web`.

Principais entregas:

- README atualizado.
- Rotas reais documentadas.
- Labels, titulos e navegacao padronizados.
- Aliases confusos canonicalizados, como `employees` para `users` e `sessions`
  para `devices`.
- Testes para garantir rotas e labels principais.

Status final: concluida.

Observacoes: nenhuma rota owner foi criada ou consumida.

### 2. Tela Central de Suporte

Objetivo: criar a base da tela central de suporte da empresa.

Principais entregas:

- Rota `/companies/:companyId/support`.
- Central de Suporte da Empresa read-only.
- Cards para empresa, licenca, billing, dispositivos, sessoes, usuarios,
  funcionarios, Sync Center, conflitos, auditoria e status operacional.
- Atalhos a partir da listagem e detalhe da empresa.

Status final: concluida.

Observacoes: a tela e hub operacional, mas nao executa comandos reais.

### 3. Navegacao e UX

Objetivo: reduzir cliques, confusao e inconsistencias visuais.

Principais entregas:

- Breadcrumbs persistentes.
- Tela amigavel para rota invalida.
- Atalhos entre empresa, suporte, usuarios, dispositivos, billing e Sync
  Center.
- Estados vazios e dados indisponiveis mais claros.

Status final: concluida.

Observacoes: melhorias de navegacao foram feitas sem quebrar compatibilidade de
rotas existentes.

### 4. Console Operacional

Objetivo: transformar usuarios, sessoes e dispositivos em console operacional
mais util para suporte, mantendo read-only.

Principais entregas:

- `admin_operational_status.dart`.
- Indicadores OK, Atencao, Critico e Sem dados.
- Fallbacks explicitos para dados ausentes.
- Campos de ultima atividade, ultimo sync, ultimo erro e pendencias.
- Central de Suporte com resumos operacionais e links relacionados.

Status final: concluida.

Observacoes: nenhuma acao de bloquear, revogar, forcar sync ou comando real foi
criada.

### 5. Sync Center

Objetivo: evoluir o Sync Center como visao operacional read-only.

Principais entregas:

- Resumo geral com totais.
- Indicadores OK, Atencao, Critico e Sem dados.
- Filtros front-end por saude/condicao.
- Ordenacao por criticidade, ultimo sync, conflitos, pendencias e erros.
- Diagnostico simplificado por empresa.
- Central de Suporte refletindo melhor status de sync.

Status final: concluida.

Observacoes: Sync Center virou a principal fonte visual de saude de
sincronizacao, sem alterar sync engine.

### 6. Auditoria Operacional

Objetivo: melhorar auditoria como fonte read-only de diagnostico e
rastreabilidade.

Principais entregas:

- Categorias visuais.
- Indicadores operacionais.
- Novos campos na tabela de auditoria.
- Fallbacks claros.
- Filtro local por indicador visual.
- Ordenacao local por data, criticidade, categoria, empresa e tipo de acao.
- Link da auditoria para Central de Suporte quando ha `companyId`.

Status final: concluida.

Observacoes: eventos novos nao foram criados; a tela apenas exibe e organiza
dados existentes.

### 7. API e Documentacao

Objetivo: documentar contratos consumidos pelo Admin Web e lacunas futuras.

Documentacoes criadas:

- `docs/api-contracts.md`
- `docs/openapi-admin-web-draft.yaml`

Principais entregas:

- Inventario de endpoints consumidos pelo front-end.
- Models, payloads esperados, estados de erro e fallbacks.
- Mapa de dependencia entre telas e dados.
- Lacunas de contrato.
- Regras futuras para acoes operacionais reais.

Status final: concluida.

Observacoes: OpenAPI e preliminar e nao cria endpoint ou contrato novo.

### 8. Seguranca do Admin

Objetivo: documentar e reforcar seguranca visual/read-only no Admin Web.

Documentacao criada:

- `docs/security-admin-web.md`

Principais entregas:

- Utilitario de mascaramento/redacao para exibicao segura.
- Card "Seguranca operacional" na Central de Suporte.
- Documento da empresa mascarado.
- Regras para logs seguros, dados sensiveis na UI e acoes futuras.

Status final: concluida.

Observacoes: autenticacao real, autorizacao real, Cookie HttpOnly, BFF, MFA,
CSP e headers de seguranca continuam dependentes de backend/infra.

### 9. Observabilidade

Objetivo: preparar base de observabilidade read-only.

Documentacao criada:

- `docs/observability-admin-web.md`

Principais entregas:

- Legenda compartilhada de indicadores.
- Card "Observabilidade operacional" na Central de Suporte.
- Sync Center reforcado como fonte visual de saude de sincronizacao.
- Lacunas e metricas futuras documentadas.

Status final: concluida.

Observacoes: nao ha coleta real de metricas, APM, Prometheus, Grafana ou
alertas externos.

### 10. CI/CD

Objetivo: documentar comandos, ordem de validacao e base futura de pipeline.

Documentacao criada:

- `docs/cicd-admin-web.md`

Principais entregas:

- Comandos locais padronizados: `flutter pub get`, `flutter analyze`,
  `flutter test` e `flutter build web`.
- Pipeline recomendado.
- Criterios de falha e aprovacao.
- Explicitado que nao ha deploy real, secrets, producao ou infraestrutura.

Status final: concluida.

Observacoes: workflow real nao foi criado porque nao havia padrao de CI na raiz
do repositorio.

### 11. Controle de versao Android

Objetivo: preparar controle futuro de versao Android com visao read-only.

Documentacao criada:

- `docs/android-version-control.md`

Principais entregas:

- Card "Controle de versao Android" na Central de Suporte.
- Resumo read-only de versoes Android na tela de Dispositivos.
- Fallback "Versao nao informada".
- Status visual e coluna "Status versao".
- Politica futura de versao minima, recomendada e instalada documentada.

Status final: concluida.

Observacoes: nao ha enforcement real, atualizacao obrigatoria real, bloqueio de
app antigo ou alteracao no Android.

### 12. Push Notification / FCM

Objetivo: preparar o Admin Web para futura evolucao de Push Notification / FCM.

Documentacao criada:

- `docs/push-notification-fcm.md`

Principais entregas:

- Card "Push Notification / FCM" na Central de Suporte.
- Secao read-only de FCM na tela de Dispositivos.
- Fallbacks para token, preferencias, historico e envio real.
- Regras futuras de seguranca, auditoria e observabilidade.
- Teste garantindo que token falso em fixture nao vaza na UI.

Status final: concluida.

Observacoes: nao ha Firebase real, credenciais, registro de token, envio real,
endpoint novo ou Android/backend alterado.

## Read-only por design

Varias areas foram preparadas visualmente e documentalmente, mas continuam sem
executar acoes reais por decisao de seguranca e escopo.

- Suporte operacional: diagnostica e orienta, mas nao bloqueia, revoga, força
  sync ou altera estado real.
- Sync Center: prioriza conflitos, erros e pendencias, mas nao reprocessa fila
  ou resolve conflito.
- Auditoria: exibe e organiza eventos existentes, mas nao cria evento novo.
- Seguranca: documenta hardening e reduz exposicao visual, mas nao muda auth ou
  permissoes reais.
- Observabilidade: agrega sinais existentes, mas nao coleta metricas reais.
- Controle de versao Android: mostra versoes reportadas e lacunas, mas nao
  aplica versao minima.
- FCM: exibe preparo e lacunas, mas nao registra token nem envia push.

## Dependencias futuras

### Backend

- Endpoints reais para acoes de suporte.
- Contratos oficiais e versionados.
- Auditoria backend obrigatoria.
- Permissoes granulares.
- Dry-run para acoes sensiveis.
- Healthchecks.
- Metricas reais.
- Politica de versao Android.
- FCM real: tokens, preferencias, historico, dry-run e envio.

### Android

- Envio de versao instalada por dispositivo.
- Enforcement de versao minima.
- Atualizacao obrigatoria.
- Registro de token FCM.
- Preferencias de push.
- Comportamento de mensagens operacionais.
- Tratamento de politica indisponivel.
- Fluxo seguro para link da Play Store.

### Infraestrutura

- CI oficial.
- Deploy real.
- Secrets e gestao segura de variaveis.
- CSP e security headers.
- Observabilidade real.
- Prometheus, Grafana ou APM.
- Alertas externos.
- Politica de artefatos e ambientes.

### Seguranca e auditoria

- Motivo obrigatorio.
- Confirmacao explicita.
- Ator/admin identificado.
- Payload seguro e resumido.
- Trilha auditavel.
- Permissoes por acao.
- Resultado auditado.
- Falhas auditadas.
- Rollback ou plano de reversao para politicas sensiveis.

## Proximos epicos recomendados

1. Backend Support Actions Foundation
   - Criar contratos oficiais para dry-run, comandos de suporte, impacto,
     motivos e auditoria.

2. Admin Permissions & Audit Enforcement
   - Implementar permissoes granulares reais e auditoria backend obrigatoria
     para cada acao sensivel.

3. Android Version Policy Backend
   - Criar politica de versao minima/recomendada, endpoint de leitura e fluxo
     auditado para alteracao.

4. FCM Backend + Android Integration
   - Registrar tokens, preferencias, historico, dry-run e envio real com
     auditoria e protecao de credenciais.

5. Observability Backend Metrics
   - Expor metricas reais, healthchecks, latencia, erros, status de filas e
     alertas por empresa.

6. Official CI/CD Workflow
   - Criar workflow oficial para analyze, test, build, artefatos e promocao
     controlada por ambiente.

7. Production Security Hardening
   - Implementar Cookie HttpOnly ou BFF, MFA, CSP, security headers, rate limit
     e revisao de armazenamento de tokens.

## Conclusao

As 12 fases iniciais foram concluidas e deixaram o Admin Web preparado como
base operacional read-only. O projeto agora tem melhor navegacao, diagnostico,
documentacao, testes e guardrails. A proxima etapa deve sair do front-end
preparatorio e avancar em contratos reais de backend, Android, seguranca,
auditoria, observabilidade, CI/CD e FCM.
