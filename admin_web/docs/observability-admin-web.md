# Observabilidade do Admin Web

Este documento define a base de observabilidade read-only do `admin_web`.
Ele descreve sinais operacionais exibidos hoje, metricas futuras desejadas,
lacunas conhecidas e dependencias de backend/infra. Esta fase nao cria coleta
real de metricas, alertas externos, webhooks, endpoints, contratos novos ou
mudancas em backend.

## Objetivo

A observabilidade do Admin Web deve ajudar suporte, operacao e auditoria a
entender rapidamente a saude de uma empresa ou da plataforma, usando sinais
seguros e interpretaveis:

- OK: operacao aparentemente saudavel.
- Atencao: ha sinais que merecem verificacao.
- Critico: ha erro, conflito aberto, falha ou risco operacional.
- Sem dados: nao ha informacao suficiente para classificar.

Esses indicadores sao informativos. Decisoes operacionais reais continuam
dependendo de backend, permissoes, auditoria obrigatoria e processos de suporte.

## Limites atuais do front-end

O front-end pode agregar dados ja retornados pelas APIs atuais, ordenar listas,
filtrar itens e exibir alertas visuais. Ele nao mede latencia real de backend,
nao coleta metricas de infraestrutura, nao cria logs backend, nao envia alertas
externos e nao substitui monitoramento server-side.

Nesta fase, observabilidade significa apresentacao segura de sinais existentes,
como contagens de sync, conflitos, eventos de auditoria, status de billing e
status de dispositivos.

## Dados ja disponiveis no Admin Web

- Sync Center global: empresas monitoradas, conflitos, pendencias, erros,
  incidentes, ultimo evento e status de saude.
- Sync Center por empresa: diagnostico de sync, ultimo sync, ultimo erro,
  pendencias, conflitos e sugestao operacional.
- Central de Suporte da Empresa: status de sync, dispositivos, sessoes,
  usuarios, funcionarios, billing, auditoria e seguranca operacional.
- Billing: status de assinatura, provider, cancelamento, eventos e historico
  sanitizado quando retornado pela API atual.
- Auditoria: eventos administrativos, categoria, resultado, severidade visual,
  recurso afetado e detalhes sanitizados.
- Dispositivos: plataforma, versao do app, ultimo sync, ultimo erro, pendencias
  e status operacional quando o dado ja existe.

## Checklist futuro de metricas

| Metrica | Origem futura | Status nesta fase |
| --- | --- | --- |
| requests por rota | Backend/infra | Pendente |
| latencia por endpoint | Backend/infra/APM | Pendente |
| taxa de erro por endpoint | Backend/infra/APM | Pendente |
| erros por empresa | Backend/auditoria | Parcial via dados atuais |
| syncs pendentes | Sync API atual | Parcial |
| syncs com erro | Sync API atual | Parcial |
| conflitos por empresa | Sync API atual | Parcial |
| status de billing | Billing API atual | Parcial |
| falhas de webhook | Backend/billing engine | Pendente |
| backend offline | Infra/healthcheck | Pendente |
| banco indisponivel | Infra/DB monitoring | Pendente |
| versao do app por dispositivo | Inventario atual | Parcial |
| empresas sem sync recente | Sync API atual | Parcial |
| eventos de auditoria criticos | Auditoria atual | Parcial |

## Alertas futuros desejados

- Empresa sem sync recente acima de um limite definido.
- Aumento de conflitos por empresa.
- Erros de sync recorrentes por dispositivo.
- Billing com assinatura cancelada, vencida ou sem provider esperado.
- Falhas de webhook de pagamento.
- Backend offline ou degradado.
- Banco indisponivel ou com latencia alta.
- Pico de erros por rota administrativa.
- Acoes sensiveis sem auditoria backend.

Todos esses alertas dependem de backend, infraestrutura, filas, jobs ou
ferramentas externas. O `admin_web` pode exibir o resultado quando houver
contrato oficial, mas nao deve criar coleta ou alerta real por conta propria.

## Relacao com telas existentes

- Central de Suporte: hub por empresa, consolida sinais de sync, billing,
  dispositivos e auditoria para orientar atendimento.
- Sync Center: fonte visual principal para saude de sincronizacao.
- Billing: fonte read-only de status financeiro/assinatura quando ja disponivel.
- Auditoria: contexto read-only para diagnostico e rastreabilidade.
- Dispositivos: evidencia local por aparelho, app version, ultimo sync e erros.

## Lacunas conhecidas

- Nao ha metrica real de latencia por endpoint.
- Nao ha healthcheck backend dedicado no front-end.
- Nao ha status de banco ou fila.
- Nao ha alertas externos reais.
- Nao ha historico temporal de metricas no front-end.
- Nem todo payload atual permite distinguir falta de dados de sistema saudavel.
- Permissoes visuais nao representam autorizacao real de observabilidade.

## Seguranca de dados

Observabilidade nao deve expor tokens, secrets, headers, documentos completos,
payloads brutos sensiveis, stack traces completos ou URLs privadas. Dados
devem usar mascaramento, sanitizacao e fallbacks como `Nao informado`,
`Indisponivel`, `Sem dados` ou `Sem metricas disponiveis`.

## Dependencias futuras

- Backend com endpoints oficiais de metricas.
- Infra com healthchecks e security headers.
- APM ou mecanismo equivalente para latencia e erros.
- Auditoria backend obrigatoria para acoes sensiveis.
- Contratos claros para status de billing, webhook e sync.
- Politica de retencao e acesso a metricas por papel.
