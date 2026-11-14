# Dashboard mobile — Fase 1

## Escopo e direção visual

A referência `02_feed_mobile.png` orienta hierarquia, rolagem vertical, atalhos circulares e identidade roxa. A implementação usa os componentes Material 3 existentes, sem vídeos, interações sociais decorativas, fotografias de funcionários ou indicadores simulados. O painel web não foi alterado.

O trabalho anterior de navegação, comprovantes, associação de clientes e sincronização foi preservado. Não foi encontrado `AGENTS.md` no repositório nem nos diretórios ancestrais consultados. O Graphify confirmou dependências do dashboard no commit base `726ebb20`; como seu índice não inclui as alterações locais recentes, o código local foi a referência final.

## Contrato visual verificável

- Trabalho principal: conferir a operação disponível neste aparelho e iniciar uma venda rapidamente.
- Hierarquia: marca/empresa e conta → atalhos → resumo → movimento → pendências → últimas movimentações → sincronização.
- Ação principal: “Nova venda”, fixa e disponível mesmo enquanto o resumo carrega ou apresenta erro, somente com permissão de vender.
- Viewports de teste: 360×800 com texto padrão; 360×640 em tema escuro e texto 180%; 412×915 com texto 200%. A grade muda para uma coluna com texto ampliado; atalhos rolam horizontalmente.
- Layout: tokens existentes de espaçamento, cores semânticas para caixa/alertas e uma paleta roxa restrita ao dashboard. A navegação mantém Início, Produtos, Vender, Atividade e Perfil. A barra recebe a paleta da home apenas enquanto essa aba está selecionada.
- Carregamento: consulta visível e atalhos disponíveis. Erro: mensagem sem detalhes técnicos e nova tentativa. Vazio: ausência de vendas/pendências explicada. Parcial: estoque/lucro/série podem falhar sem esconder o resumo disponível. Offline: dados locais e estado real de sincronização continuam visíveis. Permissões: ações e consultas gerenciais são filtradas.

## Fontes e regras

| Conteúdo | Fonte existente | Alcance e disponibilidade |
| --- | --- | --- |
| Vendas do dia | `operationalDashboardSnapshotProvider` / `SqliteOperationalDashboardRepository` | Total e quantidade de vendas ativas do dia na base local. Fiado vendido não significa dinheiro recebido. |
| Caixa atual | Mesmo snapshot / sessão de caixa aberta | Saldo registrado da sessão local; fechado e confirmação de troco são estados explícitos. |
| Lucro realizado | `dashboardDailyOverviewProvider` → `pdvOperationalReportRepositoryProvider.fetchOverview` | Regra existente dos relatórios: margem das vendas à vista e fração da margem do fiado correspondente aos recebimentos. Antes das despesas; sem consolidação entre aparelhos. Custo desconhecido mantém o indicador indisponível. Restrito a `reports.advanced`. |
| Movimento da loja | `dashboardSalesTrendProvider` → mesmo repositório, `fetchSalesTrend` | Vendas líquidas por dia, sete dias corridos incluindo hoje. Canceladas excluídas. Dias sem registros na consulta bem-sucedida têm zero; nenhuma barra mínima artificial. Sem registros, mostra vazio. Sem comparativos percentuais ou curva de lucro presumida. |
| Estoque baixo | `inventoryItemOptionsProvider` / `InventoryAlertService` | Quantidade abaixo do mínimo configurado. Falha ou carregamento não viram zero nem “estoque em dia”. |
| Contas a receber | Snapshot / fiados pendentes ou parciais | Quantidade de **notas**, não de clientes, e valor aberto. Respeita permissão e recurso do plano. |
| Pedidos pendentes | Snapshot / pedidos operacionais ativos | Contagem real, com acesso à lista existente. |
| Atualizações pendentes | `accountCloudStatusProvider` | Estado de conexão, fila, erros, bloqueios e conflitos existentes. Sem inbox ou alertas fictícios. |
| Últimas movimentações | Snapshot / movimentos de caixa | Até cinco registros do caixa aberto; se fechado, os últimos registros locais. Restrito ao acesso a caixa. Valores e datas não são tratados como série de vendas. |
| Clientes e equipe | Destinos existentes de clientes e funcionários | Atalhos, sem contadores ou presença inventados. Equipe exige recurso `employees` e acesso a `employees.manage`. |

Os dois novos providers usam filtros independentes dos relatórios abertos, guard de inicialização do tenant, timeout local e controle de acesso. Atualizam com `appDataRefreshProvider`, pull-to-refresh e virada do dia. O app já emite atualização ao retornar ao primeiro plano e após operações/sincronização. Nenhum schema, contrato HTTP ou cálculo financeiro foi alterado.

## Arquivos desta fase

- `lib/app/core/theme/dashboard_theme.dart`: paleta e tema restritos à home.
- `lib/app/core/widgets/app_navigation_shell.dart`: cor da barra ao selecionar Início, mantendo os destinos e o comportamento existentes.
- `lib/modules/dashboard/presentation/pages/dashboard_page.dart`: feed mobile, dados, permissões, ações e estados.
- `lib/modules/dashboard/presentation/widgets/dashboard_feed_widgets.dart`: atalhos circulares e métricas com tamanho natural, sem reduzir a escala do texto.
- `lib/modules/dashboard/presentation/providers/dashboard_providers.dart`: lucro diário local e série independente de sete dias; atualização na virada do dia.
- `lib/modules/relatorios/presentation/widgets/sales_trend_chart_card.dart`: gráfico existente reutilizado; zeros com altura zero, datas, descrição semântica e resumo que quebra linha.
- `test/widget_test.dart` e `test/operational_dashboard_snapshot_test.dart`: renderização, estados, permissões, preservação de filtros e consultas/atualização com SQLite real.
- `test/app_router_test.dart` e `test/app_bootstrap_flow_test.dart`: fixtures das novas consultas e expectativa do cabeçalho Tatuzin, preservando os cenários anteriores de rotas e autenticação.

## Navegação e repetição no Android

1. Compilar/executar o código desta fase em um Android conectado com `flutter run -d <id-do-android>`. O APK anteriormente entregue não contém esta fase visual. Para atualizar a variante Piloto 2, usar o fluxo de compilação e assinatura persistente documentado em `docs/android-pilot-fixes.md`; não substituir a assinatura por uma chave temporária.
2. Entrar na empresa de testes e abrir **Início**. Conferir empresa, estado de sincronização e a fila de atalhos; arrastar a fila para alcançar os últimos acessos.
3. Tocar em **Vendas** ou no valor de **Vendas de hoje**: histórico filtrado para hoje. **Caixa**, **Estoque**, **Relatórios**, **Equipe**, **Produtos** e **Clientes** levam às rotas existentes, conforme acesso.
4. Fazer uma venda com **Nova venda**, fechar o comprovante e retornar ao Início: resumo e gráfico devem refletir a operação. Conferir Atividade e o histórico pelo fluxo já existente.
5. Conferir lucro contra o relatório diário local. Testar um produto sem custo e um fiado parcialmente recebido: não assumir lucro total da venda a prazo. O gráfico representa vendas, não recebimentos nem lucro.
6. Abrir pendências de fiado/pedidos/estoque e **Ver caixa** em Últimas movimentações. Conferir situação e registros nas telas de destino.
7. Desligar a rede, voltar ao app e conferir estado de sincronização e dados locais. Reconectar e puxar para atualizar. O estado da conexão não deve ser apresentado como atualizado antes de sua consulta terminar.
8. Repetir com um operador de permissões limitadas, tema escuro e tamanho de fonte máximo. Abrir o drawer por ícone e gesto; alternar abas e confirmar que a busca de Produtos permanece preservada.

## Evidências e limites

Validação concluída em 14/11/2026 com Flutter 3.41.9:

- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 625 testes aprovados na suíte completa.
- Após o último ajuste de contraste no estado vazio, `flutter test --no-pub test/widget_test.dart`: 18 testes aprovados novamente.
- Regressões verificadas: comprovantes fora das abas, busca preservada, drawer real por ícone/gesto nas cinco abas, rotas e bootstrap, lucro/recebimentos de fiado, custos desconhecidos, gráficos, estoque indisponível, offline e permissões.
- `labeledTapTargetGuideline` aprovado nos três tamanhos de renderização; capturas inspecionadas com fonte real e ícones do app.
- Nenhuma falha pré-existente remanescente identificada. As falhas encontradas durante esta implementação foram corrigidas, incluindo atualização no mesmo dia, ciclo de vida do relógio diário e fixtures de navegação.

As capturas geradas por testes ficam em `build/phase1-mobile/` e usam exclusivamente fixtures de teste; seus valores não representam uma empresa real. O arquivo `evidence.json` registra os estados e viewports verificados. São renderizações do Flutter, não screenshots de aparelho físico.

Esta entrega implementa a tela Início mobile. Não adiciona dashboard web, consolidação financeira entre dispositivos, notificações remotas, listagem de presença da equipe ou compartilhamento de relatórios. A inspeção em aparelho Android físico e a avaliação dos operadores continuam necessárias; não foram simuladas como concluídas. O APK anterior permanece preservado.
