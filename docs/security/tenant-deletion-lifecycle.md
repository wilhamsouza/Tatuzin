# Ciclo de vida seguro para exclusao e anonimizacao de tenant

Status: Fases 1 e 2 implementam solicitacao, validacao, dry-run e persistencia
dedicada. A Fase 3 implementa quarentena operacional reversivel no codigo, mas
as migrations propostas ainda nao foram aplicadas e o fluxo nao esta
autorizado para uso em producao. Purge, anonimizacao e execucao final continuam
nao implementados.

## 1. Objetivo

Este documento define o roadmap para tratar solicitacoes de exclusao de conta,
empresa e dados sem apagar fisicamente a raiz `Company`.

O resultado esperado e um processo controlado que:

- desative o tenant;
- bloqueie login, escrita e sincronizacao;
- revogue sessoes e dispositivos;
- exclua dados elegiveis;
- anonimize dados pessoais;
- preserve um tombstone minimo para billing, auditoria, retencao legal e
  comprovacao;
- produza evidencia interna da conclusao.

O processo nao deve prometer exclusao automatica, imediata ou fisica de todos
os registros.

## 2. Decisao arquitetural

`Company` nao deve ser excluida fisicamente. Ela deve permanecer como um
tombstone inativo e minimizado, identificado por um estado terminal do ciclo de
vida.

A linha preservada deve conter somente os campos necessarios para:

- manter integridade referencial;
- identificar de forma interna o tenant tratado;
- relacionar invoices, checkout sessions e eventos de billing;
- manter auditoria e comprovantes;
- cumprir retencoes legais;
- impedir recriacao ou reativacao acidental durante a retencao.

Nome, razao social, documento, telefone, endereco, configuracoes de recibo e
outros identificadores devem ser anonimizados ou removidos quando nao houver
base de retencao.

## 3. Por que Company nao deve ser excluida

`Company` e a raiz de isolamento do tenant no schema remoto. Memberships,
funcionarios, dispositivos, sessoes, sync, clientes, produtos, estoque, vendas,
fiado, caixa, compras, custos, analytics e outros registros possuem relacoes
diretas ou indiretas com ela.

Uma exclusao direta causaria dois problemas:

1. relacoes `ON DELETE CASCADE` poderiam eliminar historico operacional e
   financeiro sem classificacao previa;
2. relacoes `ON DELETE RESTRICT` impediriam a operacao quando existirem
   registros que foram deliberadamente protegidos.

O banco atual usa `ON DELETE RESTRICT` em pelo menos:

- `BillingInvoice.companyId`;
- `BillingCheckoutSession.companyId`;
- `BillingCheckoutSession.userId`.

Essas restricoes protegem o historico de cobranca e demonstram que billing nao
deve ser removido implicitamente junto com o tenant.

## 4. Risco de cascade destrutivo

Grande parte dos modelos tenant-scoped usa cascade a partir de `Company`.
Executar `DELETE Company` poderia apagar em uma unica operacao:

- memberships e perfis de funcionarios;
- dispositivos, sessoes e estado de sync;
- eventos, conflitos e diagnosticos de sync;
- categorias, produtos, variantes e estoque;
- clientes e CRM;
- fornecedores, compras e custos;
- vendas, itens, fiado, caixa e eventos financeiros;
- snapshots de analytics.

Essa operacao nao distinguiria dados elegiveis para exclusao de registros que
precisam ser anonimizados, desativados ou retidos. Tambem dificultaria
recuperacao, auditoria e comprovacao do tratamento executado.

O fluxo de producao nao deve reutilizar teardowns de testes ou scripts de reset
de desenvolvimento.

## 5. Usuarios globais compartilhados

`User` e uma identidade global e pode possuir memberships em mais de uma
empresa. Portanto, uma solicitacao de um tenant nao autoriza apagar ou
desativar indiscriminadamente o usuario global.

Antes de tratar um usuario, o processo deve verificar:

- memberships em outras empresas;
- papel de administrador da plataforma;
- sessoes vinculadas a outros tenants;
- registros de auditoria em que o usuario e ator;
- obrigacoes de retencao associadas a billing ou seguranca.

Por padrao, deve-se remover ou desativar apenas o vinculo com o tenant tratado.
A identidade global somente pode ser anonimizada ou excluida quando nao houver
outros vinculos, privilegios ou retencoes aplicaveis.

## 6. Destino por categoria de dados

| Categoria | Destino recomendado |
| --- | --- |
| `Company` | Desativar e anonimizar; preservar tombstone minimo |
| Licenca | Desativar sync e operacao; preservar estado minimo de billing |
| Memberships | Revogar e remover apos a janela de seguranca |
| Usuarios globais | Preservar se compartilhados; avaliar anonimizacao apenas sem outros vinculos |
| Funcionarios | Desativar; apagar convites e credenciais temporarias; anonimizar contato |
| Clientes e CRM | Anonimizar dados pessoais; excluir notas, tarefas, tags e conteudo livre elegivel |
| Produtos e categorias | Excluir apos a janela, preservando snapshots financeiros necessarios |
| Estoque e receitas | Excluir dados operacionais elegiveis |
| Fornecedores e compras | Anonimizar contatos; reter registros financeiros necessarios |
| Vendas e itens | Reter historico financeiro minimo; remover ou anonimizar referencias pessoais |
| Fiado e contas | Reter valores e eventos exigidos; anonimizar partes identificaveis |
| Caixa e eventos financeiros | Reter registros contabeis e de auditoria necessarios |
| Sync | Bloquear imediatamente; excluir payloads, conflitos e diagnosticos elegiveis |
| Dispositivos | Revogar imediatamente; remover labels e identificadores quando elegiveis |
| Sessoes | Revogar imediatamente; eliminar hashes de refresh token |
| Billing | Reter invoices, checkout sessions, eventos e auditoria pelo prazo aplicavel |
| Auditoria | Preservar eventos sanitizados e evidencia before/after |
| Logs | Aplicar sanitizacao e politica de retencao da infraestrutura |
| Backups | Preservar ate substituicao ou expiracao conforme ciclo documentado |
| Analytics | Excluir ou manter somente agregados irreversivelmente anonimizados |

Cada categoria deve ter uma disposicao registrada: `DELETE`, `ANONYMIZE`,
`DISABLE` ou `RETAIN`, acompanhada de motivo e prazo quando houver retencao.

## 7. Estados do ciclo de vida

Estados propostos:

1. `ACTIVE`
2. `DELETION_REQUESTED`
3. `IDENTITY_VALIDATION`
4. `PENDING_DELETION`
5. `QUARANTINED`
6. `APPROVED`
7. `PROCESSING`
8. `COMPLETED`
9. `CANCELLED`
10. `BLOCKED`

`PENDING_DELETION` deve representar uma solicitacao validada e aguardando
quarentena, aprovacoes ou resolucao de blockers.

Quarentena e o periodo em que o tenant permanece inacessivel, mas a execucao
irreversivel ainda nao ocorreu. Ela permite:

- cancelar uma solicitacao fraudulenta ou equivocada;
- resolver cobrancas, chargebacks e pendencias financeiras;
- aguardar dispositivos offline;
- produzir e revisar o inventario final;
- concluir a dupla aprovacao.

## 8. Fluxo seguro proposto

### 8.1 Recebimento

1. Registrar a solicitacao, canal, data e identificadores fornecidos.
2. Gerar `requestId` e correlation ID.
3. Nao registrar senhas, tokens ou dados de pagamento completos.
4. Enviar confirmacao de recebimento sem prometer prazo de conclusao total.

### 8.2 Validacao

1. Confirmar a identidade do solicitante.
2. Confirmar sua autoridade ou relacao legitima com a empresa.
3. Registrar evidencias de validacao de forma minimizada.
4. Negar ou pausar o processo quando a autoridade nao puder ser confirmada.

### 8.3 Inventario e dry-run

1. Contar registros por categoria.
2. Detectar usuarios compartilhados.
3. Detectar sessoes, dispositivos e filas de sync.
4. Detectar caixa aberto, fiado, recebiveis e pendencias operacionais.
5. Detectar invoices, checkout sessions, assinatura e eventos de billing.
6. Classificar cada categoria como exclusao, anonimizacao, desativacao ou
   retencao.
7. Retornar blockers, riscos e efeitos esperados sem mutacao.

### 8.4 PENDING_DELETION e bloqueio

Ao entrar em `PENDING_DELETION`, o sistema deve:

- usar `TenantDeletionRequest.status=FUTURE_PENDING_DELETION` e
  `activeCompanyGuard` como controle equivalente, sem alterar
  `Company.isActive`;
- preservar `License`, billing e `License.syncEnabled` sem mutacao nesta fase;
- rejeitar login, refresh de token, escrita e sync;
- impedir novos checkouts e mudancas de plano;
- revogar sessoes operacionais e dispositivos do tenant;
- preservar sessoes `ADMIN_WEB` de platform admins autorizados para suporte,
  sem bypass de RBAC para as acoes do workflow;
- registrar auditoria before/after.

O bloqueio precisa ser transacional ou compensavel. Nao deve existir uma janela
em que o tenant esteja marcado para exclusao e ainda consiga gravar dados.

Na implementacao da Fase 3, o cancelamento restaura cada dispositivo ao estado
anterior (`ACTIVE`, `PENDING` ou `BLOCKED`). Sessoes revogadas nao sao
reativadas: apos o cancelamento, o usuario deve realizar novo login. Essa
decisao evita reutilizar refresh tokens invalidados.

### 8.5 Clearance financeiro

Antes da execucao irreversivel, verificar:

- invoices abertas ou vencidas;
- pagamentos em processamento;
- chargebacks, estornos ou disputas;
- assinatura ativa;
- checkout pendente;
- caixa aberto;
- fiado e contas pendentes;
- obrigacoes fiscais ou contabeis.

O fluxo de exclusao nao deve cancelar automaticamente o Mercado Pago. Qualquer
cancelamento no provedor exige fluxo proprio, permissao especifica, dry-run,
confirmacao, idempotencia, auditoria e tratamento de falha parcial.

Enquanto esse fluxo proprio nao existir, a pendencia do provedor deve bloquear
ou condicionar a execucao irreversivel.

### 8.6 Dupla aprovacao

A execucao irreversivel deve exigir duas aprovacoes independentes.

Regras minimas:

- o solicitante administrativo nao pode ser o unico aprovador;
- o executor nao pode ser a mesma pessoa que abriu a solicitacao;
- aprovadores devem possuir permissoes adequadas;
- toda aprovacao deve ter motivo, timestamp e ator;
- mudanca relevante no dry-run invalida aprovacoes anteriores.

Essa separacao entre solicitante e executor reduz fraude, erro humano e abuso de
privilegio.

### 8.7 Janela de seguranca e quarentena

Depois do bloqueio e das aprovacoes, iniciar uma janela configuravel de
quarentena. Durante esse periodo:

- o tenant continua bloqueado;
- a solicitacao pode ser cancelada de forma auditada;
- o inventario pode ser recalculado;
- blockers precisam permanecer resolvidos;
- nenhuma acao irreversivel e executada.

O prazo deve ser politica configuravel, nao constante espalhada pelo codigo.

### 8.8 Execucao

A execucao deve ocorrer em job assincromo, reiniciavel e idempotente.

Para cada categoria:

1. conferir o estado esperado;
2. registrar auditoria before;
3. executar a disposicao;
4. validar contagens e invariantes;
5. registrar auditoria after;
6. persistir resultado, erro e tentativa;
7. avancar somente quando a etapa estiver consistente.

Falhas parciais devem manter o pedido em `PROCESSING` ou `BLOCKED`, nunca marcar
conclusao silenciosamente.

### 8.9 Comprovante final

Ao concluir, gerar comprovante interno imutavel contendo:

- request ID e tenant tombstone ID;
- atores de validacao, aprovacao e execucao;
- timestamps;
- versao da politica aplicada;
- contagens before/after por categoria;
- disposicao aplicada por categoria;
- retencoes, fundamentos e prazos;
- falhas resolvidas e retries;
- hash ou fingerprint do relatorio;
- estado de billing e do provedor;
- estado da limpeza local dos dispositivos.

O comprovante nao deve conter secrets, tokens, payloads integrais ou PII
desnecessaria.

## 9. Limpeza local posterior no app

O app Android usa banco SQLite isolado por tenant. Revogar sessao e fechar o
banco local nao remove automaticamente o arquivo e seus dados.

O fluxo futuro deve prever uma diretiva terminal do servidor que:

- force logout;
- interrompa sync;
- feche o banco do tenant;
- apague tokens;
- remova o banco SQLite e caches tenant-scoped;
- registre acknowledgement local quando o dispositivo voltar a ficar online.

Dispositivos offline podem manter dados ate receberem a diretiva ou ate o
usuario remover o app/dados do app. O comprovante deve diferenciar conclusao
remota de limpeza local confirmada.

## 10. RBAC necessario

Permissoes propostas:

| Permissao | Uso |
| --- | --- |
| `tenant.deletion.read` | Consultar solicitacoes e inventario sanitizado |
| `tenant.deletion.request.manage` | Criar e atualizar solicitacoes |
| `tenant.deletion.identity.verify` | Registrar validacao de identidade e autoridade |
| `tenant.deletion.quarantine` | Colocar ou retirar tenant da quarentena |
| `tenant.deletion.approve` | Aprovar execucao irreversivel |
| `tenant.deletion.execute` | Executar job aprovado |
| `tenant.deletion.cancel` | Cancelar durante a janela permitida |
| `tenant.deletion.audit.read` | Consultar auditoria e comprovante |

Requisitos:

- nenhuma permissao deve ser inferida apenas por `isPlatformAdmin`;
- escopo de empresa deve ser suportado;
- permissoes de aprovacao e execucao devem ser criticas;
- grant e revoke devem ser auditados;
- o backend e a fonte de verdade, nunca o payload do cliente.

## 11. Telas futuras no Admin Web

### 11.1 Fila de solicitacoes

- filtros por estado, empresa, data e blocker;
- indicadores de prazo operacional;
- responsaveis e aprovacoes pendentes;
- acesso ao comprovante de pedidos concluidos.

### 11.2 Aba Ciclo de vida no detalhe da empresa

- estado atual do tenant;
- data e origem da solicitacao;
- inventario por categoria;
- sessoes, dispositivos e sync;
- billing e blockers financeiros;
- timeline de auditoria;
- acoes permitidas pelo RBAC.

### 11.3 Wizard de preparacao

- validacao de identidade;
- dry-run;
- revisao das disposicoes;
- declaracao de retencoes;
- confirmacao de quarentena;
- dupla aprovacao.

### 11.4 Progresso e comprovante

- etapas e tentativas do job;
- erros e blockers;
- contagens before/after;
- limpeza local confirmada ou pendente;
- comprovante final somente leitura.

Nao deve existir botao direto `Excluir empresa`.

## 12. Endpoints futuros

```text
POST /admin/companies/:companyId/deletion-requests
GET  /admin/deletion-requests
GET  /admin/deletion-requests/:requestId
POST /admin/deletion-requests/:requestId/verify-identity
POST /admin/deletion-requests/:requestId/dry-run
POST /admin/deletion-requests/:requestId/quarantine
POST /admin/deletion-requests/:requestId/approve
POST /admin/deletion-requests/:requestId/cancel
POST /admin/deletion-requests/:requestId/execute
GET  /admin/deletion-requests/:requestId/receipt
```

Contratos obrigatorios:

- idempotency key para comandos;
- correlation ID;
- motivo obrigatorio;
- confirmacao textual explicita;
- permissao granular;
- dry-run recente e compativel;
- versionamento otimista;
- auditoria before/after;
- resposta sem payload sensivel;
- codigos de erro estaveis para blockers e conflitos de estado.

Nao deve existir endpoint generico capaz de executar SQL, cascade ou delecao
arbitraria.

## 13. Migrations futuras

As migrations devem ser aditivas e revisadas separadamente. Proposta:

### 13.1 Company

- enum `CompanyLifecycleStatus`;
- `lifecycleStatus`;
- `deletionRequestedAt`;
- `quarantinedAt`;
- `anonymizedAt`;
- `deletionCompletedAt`;
- `tombstoneVersion`;
- `lifecycleReason`.

### 13.2 Solicitacao

Tabela `TenantDeletionRequest`:

- estado;
- origem;
- solicitante;
- tenant;
- motivo;
- politica e versao;
- janela de seguranca;
- data agendada;
- fingerprints do dry-run;
- timestamps e resultado.

### 13.3 Disposicoes

Tabela `TenantDeletionDisposition`:

- categoria;
- acao;
- fundamento;
- prazo de retencao;
- contagens before/after;
- status e erro.

### 13.4 Aprovacoes

Tabela `TenantDeletionApproval`:

- ator;
- papel;
- decisao;
- motivo;
- fingerprint aprovado;
- timestamp.

Constraints devem impedir aprovacao duplicada e, quando aplicavel, solicitante,
aprovador e executor iguais.

### 13.5 Execucao e comprovante

- tabela de etapas/tentativas do job;
- idempotency key unica;
- tabela `TenantDeletionReceipt`;
- fingerprint ou hash do comprovante;
- acknowledgement de limpeza por dispositivo;
- legal hold e retencao por categoria.

Os `ON DELETE RESTRICT` de billing nao devem ser removidos para facilitar a
implementacao.

## 14. Testes essenciais

### 14.1 Unidade

- maquina de estados;
- calculo de blockers;
- classificacao de disposicoes;
- sanitizacao;
- separacao entre solicitante, aprovador e executor;
- expiracao de dry-run e aprovacoes.

### 14.2 Integracao com Prisma real

- `PENDING_DELETION` bloqueia login, refresh, escrita e sync;
- todas as sessoes e dispositivos sao revogados;
- dry-run nao altera dados;
- billing `RESTRICT` permanece preservado;
- usuarios compartilhados nao sao apagados;
- auditoria before/after e gravada;
- retries nao duplicam efeitos;
- falha no meio pode ser retomada;
- comprovante corresponde as contagens reais;
- tenant tombstone preserva integridade referencial.

### 14.3 Seguranca e RBAC

- permissao ausente resulta em negacao auditada;
- `isPlatformAdmin` sozinho nao autoriza;
- dupla aprovacao obrigatoria;
- solicitante nao executa;
- mudanca no inventario invalida aprovacao;
- payloads e logs nao vazam PII, tokens ou secrets.

### 14.4 Billing

- assinatura ativa, invoice aberta, checkout pendente e chargeback atuam como
  blockers conforme politica;
- falha no provedor nao marca conclusao;
- fluxo nao cancela automaticamente Mercado Pago;
- historico de invoice e checkout permanece consultavel.

### 14.5 App e sync

- dispositivo online recebe bloqueio e limpeza;
- dispositivo offline nao consegue sincronizar ao retornar;
- SQLite tenant-scoped e removido de forma idempotente;
- acknowledgement local e registrado;
- dados de outro tenant no mesmo aparelho nao sao afetados.

### 14.6 Admin Web

- telas respeitam RBAC;
- nao existe acao direta de exclusao;
- estados, blockers e retencoes sao claros;
- confirmacoes impedem clique acidental;
- comprovante e somente leitura.

## 15. Riscos financeiros e operacionais

| Risco | Mitigacao |
| --- | --- |
| Cascade apaga historico necessario | Nunca executar `DELETE Company`; usar disposicoes por categoria |
| Assinatura continua cobrando | Gate financeiro e fluxo proprio do provedor |
| Cancelamento indevido no Mercado Pago | Nao automatizar; exigir permissao, dry-run e auditoria separados |
| Invoice, disputa ou chargeback em aberto | Bloquear execucao irreversivel |
| Usuario compartilhado perde acesso a outro tenant | Analisar memberships globais antes de tratar `User` |
| Dispositivo offline conserva dados | Bloqueio de sync e limpeza local posterior |
| Job falha parcialmente | Etapas idempotentes, checkpoints e retomada |
| Duas execucoes concorrentes | Idempotency key, lock e versionamento otimista |
| PII permanece em auditoria ou logs | Sanitizacao, minimizacao e politica de retencao |
| Backup conserva dados por algum tempo | Ciclo documentado e expiracao controlada |
| Solicitacao fraudulenta | Validacao de identidade, quarentena e dupla aprovacao |
| Erro interno irreversivel | Separacao de funcoes, dry-run e janela de seguranca |
| Recriacao do tenant causa colisao | Tombstone e politica para slug/documento |
| Relatorios quebram apos anonimizacao | Preservar snapshots e invariantes financeiras |

## 16. Roadmap por fases

### Fase 0 - Politica e governanca

- aprovar politica de retencao por categoria;
- definir prazos de quarentena;
- definir fluxo de identidade e autoridade;
- definir legal hold;
- criar runbook de incidente e rollback.

Saida: politica aprovada, sem alteracao funcional.

### Fase 1 - Inventario read-only

- endpoint de leitura;
- contagens por categoria;
- blockers;
- usuarios compartilhados;
- preview de disposicoes;
- testes de integracao.

Saida: dry-run confiavel, sem mutacoes.

### Fase 2 - Estado e quarentena

- migrations aditivas;
- estados do ciclo de vida;
- bloqueio de login, escrita e sync;
- revogacao de sessoes e dispositivos;
- cancelamento auditado durante a janela.

Saida: tenant pode ser colocado com seguranca em `PENDING_DELETION` e
`QUARANTINED`.

### Fase 3 - RBAC e Admin Web

- permissoes granulares;
- fila de solicitacoes;
- aba Ciclo de vida;
- wizard de dry-run;
- dupla aprovacao;
- timeline de auditoria.

Saida: operacao controlada, ainda sem purge geral.

### Fase 4 - Worker de tratamento

- job idempotente;
- disposicoes por categoria;
- anonimizacao;
- exclusao de dados elegiveis;
- retencao legal;
- checkpoints e retries;
- comprovante final.

Saida: execucao remota controlada e comprovavel.

### Fase 5 - Limpeza local no app

- estado terminal recebido pelo app;
- logout e bloqueio;
- remocao do SQLite e caches;
- acknowledgement por dispositivo;
- suporte a aparelhos offline.

Saida: limpeza local posterior integrada ao comprovante.

### Fase 6 - Billing e provedor

- desenhar fluxo especifico para cancelamento;
- implementar conciliacao e blockers;
- testar falhas e idempotencia;
- manter Mercado Pago desacoplado do worker de dados.

Saida: tratamento financeiro seguro sem cancelamento implicito.

### Fase 7 - Piloto e rollout

- tenants sinteticos;
- ambiente isolado;
- feature flag;
- aprovacao operacional;
- metricas, alertas e dashboards;
- piloto interno;
- rollout gradual.

Saida: liberacao controlada com evidencia de seguranca.

## 17. Criterios de liberacao

O fluxo nao deve entrar em producao enquanto faltar qualquer item:

- politica de retencao aprovada;
- inventario completo e testado;
- RBAC persistido;
- dry-run;
- dupla aprovacao;
- separacao entre solicitante e executor;
- auditoria before/after;
- idempotencia e retomada;
- quarentena;
- comprovante final;
- limpeza local planejada;
- tratamento explicito de billing;
- runbook e observabilidade;
- testes com banco isolado;
- rollout protegido por feature flag.

## 18. Fora de escopo deste documento

Este documento nao:

- implementa backend;
- altera banco ou cria migration;
- altera Admin Web;
- altera o app Android;
- cancela assinatura;
- chama Mercado Pago;
- executa exclusao;
- autoriza deploy ou operacao em producao.

Qualquer implementacao futura exige revisao tecnica, juridica, financeira e
operacional independente.
