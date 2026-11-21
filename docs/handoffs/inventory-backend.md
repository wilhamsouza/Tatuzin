# Backend Estoque — entrega para integração

Estado: revisão. Nenhuma alteração foi aplicada ao ambiente publicado por este agente.

## Arquivos e contratos

- `backend/prisma/schema.prisma`: campos `catalogRevision`, `stockRevision`, mínimos e reposição; entidades InventoryMovement, InventoryCount/Item, InventoryOperation e InventoryAuditEvent.
- Migração aditiva `20261114170000_inventory_workspace`: revisões de todo escritor por trigger, ledger somente por SKU operacional, auditoria imutável (cascata da exclusão de empresa permanece independente). Reverter a aplicação sem remover as tabelas/colunas.
- `backend/src/modules/inventory/`: consultas SQL paginadas, contexto transacional, serviços e rotas autenticadas. Todo companyId vem do contexto validado.
- `backend/src/modules/sync/sync-event.service.ts`: contexto transacional de origem/autor, preservando o usuário do evento armazenado no reprocessamento. A lógica de baixa não foi substituída.

Novas escritas exigem allowlist `INVENTORY_WORKSPACE_PILOT_COMPANY_IDS` (IDs separados por vírgula, ou `*` no ambiente de testes), permissão e plano. `/capabilities` informa os gates reais.

`GET /inventory` mantém envelope e agora aceita `query`, `filter=all|active|zeroed|belowMinimum|inactive`, `productId`, `productVariantId`, `page`, `pageSize`. Item contém identidade, unidade, saldos físico/reservado/disponível, mínimos, custo/preço autorizados, situação, revisão e data. Resumo não soma unidades diferentes. `divergenceItemsCount:null` significa fonte indisponível.

`GET /items/:productId?productVariantId`, `GET /movements` paginado com filtros produto/variação/período/tipo/origem. Movimentação inclui snapshots de autor e identidade e referência; registros sem autoria são identificados explicitamente. `PATCH /items/:productId/settings` (alias sem `/settings`) recebe `{expectedRevision,minimumStockMil,reorderPointMil}`.

`POST /adjustments` recebe `{requestId,productId,productVariantId?,expectedRevision,quantityDeltaMil,reason,notes?}`. Operação transacional, idempotente e vinculada ao autor, com recusa a saldo negativo e revisão desatualizada.

`POST /initial-balances` usa o mesmo contrato, delta positivo, apenas item novo com saldo/revisão zero e sem histórico ou reservas ativas. Requer inventoryBasic, products.write e stock.adjust; preserva o saldo inicial do FREE sem liberar ajustes/contagens avançados. `canInitializeStock` informa elegibilidade geral; as condições do item são revalidadas na execução.

Contagens: GET/POST `/counts`, GET/PATCH `/counts/:id`, PUT `/counts/:id/items`, POST `/counts/:id/review|apply|cancel`. Mutação exige `expectedRevision`, ações POST também `requestId`. Criação recebe nome e seleção opcional por productIds. PUT faz upsert; remoção explícita com `{productId,productVariantId?,remove:true}`. Quantidade não preenchida é `null`, jamais zero. Até 500 itens por sessão. Detalhe retorna `{session,items,history}` com revisões, divergência e `isStale`; histórico mostra os últimos 100 eventos auditados. Todos os eventos permanecem no banco.

Aplicação requer sessão revisada, todos os itens contados e revisões atuais. Mudança de estoque exige nova conferência. Sessões aplicadas/canceladas são imutáveis. Responsabilidade única; transferência só por dono/gerente para usuário ativo autorizado da mesma empresa. `/count-assignees` fornece `{items:[{userId,name}]}`. O backend não presume que aparelhos desconectados já enviaram suas operações; os clientes devem sincronizar suas pendências antes da confirmação.

## Evidências

- Migrações aplicadas somente no PostgreSQL descartável da porta 55441.
- 13 testes HTTP (9 novos + 4 existentes): `/tmp/inventory-workspace-tests.log`, todos passaram.
- 80 regressões de sincronização/vínculo de cliente: `/tmp/inventory-workspace-sync-regression.log`, todas passaram.
- TypeScript sem erros: `/tmp/inventory-workspace-types.log`.
- `git diff --check` dos arquivos desta entrega sem problemas.

Prisma gerado com a versão já instalada no backend. As alterações locais anteriores foram preservadas. Produção, compilação Flutter/APK e publicação ficam com o integrador.


## Checagem da imagem compilada — 16/11/2026

Teste HTTP contra a imagem `tatuzin-backend:products-stock-20261115-r1` em porta isolada 4006, conectada exclusivamente ao banco descartável 55441. Evidência: `build/products-stock/candidate-image-check.json`.

Sete verificações passaram: autorização/capabilities; criação cadastral sem quantidade; saldo inicial central; item não contado nulo; revisão/aplicação/reenvio com uma movimentação e uma auditoria; edição cadastral preservando saldo; cliente legado com saldo desatualizado recusado com 409. Fixtures removidas, sem credenciais na evidência.

Revisão de reversão: o schema é aditivo e compatível com leituras de clientes/backends anteriores. Os triggers observam escritas sem repetir a alteração de quantidade. Reverter telas e desligar o piloto mantendo o backend compatível é a estratégia preferida. Um backend anterior ainda pode recriar variações ou sobrescrever quantidades ao editar produtos; um downgrade desse backend exige congelar as escritas afetadas, ou usar uma correção por rollforward. Nenhum rollback real foi executado neste teste.
