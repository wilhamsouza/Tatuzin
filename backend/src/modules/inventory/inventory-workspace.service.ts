import { createHash, randomUUID } from 'node:crypto';
import { Prisma, type InventoryCount } from '@prisma/client';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { effectivePermissionsForEmployee, roleFromMembershipRole, defaultPermissionsForRole } from '../employees/employee-permissions';
import { setInventoryContext } from './inventory-context';
import { inventoryItemsSql, type WorkspaceItem } from './inventory-items';
import type { InventoryAdjustmentInput, InventoryCountActionInput, InventoryCountCreateInput, InventoryCountItemsInput, InventoryCountListQuery, InventoryCountUpdateInput, InventoryMovementsQuery, InventorySettingsInput } from './inventory.schemas';

type Actor = { id: string; name: string; role: string };
type Tx = Prisma.TransactionClient;
function json(value: unknown): Prisma.InputJsonValue { return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue; }
function fail(message: string, code = 'INVENTORY_CONFLICT', status = 409): never { throw new AppError(message, status, code); }
function targetKey(productId: string, variantId?: string | null) { return productId + ':' + (variantId ?? ''); }
const terminal = new Set(['APPLIED', 'CANCELED']);

export class InventoryWorkspaceService {
  async item(companyId: string, productId: string, productVariantId?: string | null, db: Tx = prisma) {
    const [row] = await db.$queryRaw<WorkspaceItem[]>`${inventoryItemsSql(companyId)} SELECT * FROM items WHERE "productId"=${productId} AND "productVariantId" IS NOT DISTINCT FROM ${productVariantId ?? null}::text`;
    if (!row) fail('Item de estoque não encontrado.', 'INVENTORY_ITEM_NOT_FOUND', 404);
    return row;
  }

  async movements(companyId: string, q: InventoryMovementsQuery) {
    const where: Prisma.InventoryMovementWhereInput = { companyId,
      ...(q.productId ? { productId: q.productId } : {}), ...(q.productVariantId ? { productVariantId: q.productVariantId } : {}),
      ...(q.type ? { type: q.type } : {}), ...(q.origin ? { origin: q.origin } : {}),
      ...((q.startDate || q.endDate) ? { createdAt: { ...(q.startDate ? { gte: new Date(q.startDate + 'T00:00:00Z') } : {}), ...(q.endDate ? { lt: new Date(new Date(q.endDate + 'T00:00:00Z').getTime() + 86400000) } : {}) } } : {}) };
    const [items, total] = await prisma.$transaction([
      prisma.inventoryMovement.findMany({ where, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], skip: (q.page - 1) * q.pageSize, take: q.pageSize }), prisma.inventoryMovement.count({ where }),
    ]);
    const actors = await prisma.user.findMany({ where: { id: { in: [...new Set(items.flatMap(m => m.actorUserId ? [m.actorUserId] : []))] } }, select: { id: true, name: true } });
    const names = new Map(actors.map(u => [u.id, u.name]));
    return { items: items.map(m => ({ ...m, responsibleName: m.actorName ?? (m.actorUserId ? names.get(m.actorUserId) : null) ?? 'Responsável não registrado' })), pagination: { page: q.page, pageSize: q.pageSize, total, totalPages: Math.ceil(total / q.pageSize) }, source: 'server' };
  }

  async adjust(companyId: string, actor: Actor, input: InventoryAdjustmentInput, initial = false) {
    return this.idempotent(companyId, actor, input.requestId, initial ? 'INITIAL_BALANCE' : 'ADJUST', input, async (tx, operationId) => {
      await this.lockTarget(tx, companyId, input.productId, input.productVariantId);
      const before = await this.item(companyId, input.productId, input.productVariantId, tx);
      this.assertActive(before); this.assertStockRevision(before, input.expectedRevision);
      if (initial) {
        const history = await tx.inventoryMovement.count({where:{companyId,productId:input.productId,productVariantId:input.productVariantId??null}});
        const reserved = await tx.stockReservation.count({where:{companyId,productId:input.productId,productVariantId:input.productVariantId??null,status:'active'}});
        if (input.quantityDeltaMil <= 0 || before.currentStockMil !== 0 || before.stockRevision !== 0 || history > 0 || reserved > 0) fail('O saldo inicial só pode ser registrado uma vez em um item novo e sem operações anteriores.', 'INVENTORY_ALREADY_INITIALIZED');
      }
      const afterStock = before.currentStockMil + input.quantityDeltaMil;
      if (afterStock < 0 || afterStock > 2147483647) fail('A movimentação deixaria o saldo fora do limite permitido.', 'INVENTORY_INVALID_STOCK', 422);
      await setInventoryContext(tx, { actorUserId: actor.id, actorName: actor.name, type: initial ? 'INITIAL' : input.quantityDeltaMil > 0 ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT', origin: initial ? 'initial_balance' : 'manual_adjustment', operationId, reason: input.reason, notes: input.notes });
      await this.writeStock(tx, input.productId, input.productVariantId, afterStock);
      const item = await this.item(companyId, input.productId, input.productVariantId, tx);
      await this.audit(tx, companyId, actor, initial ? 'INITIAL_BALANCE' : 'ADJUST', before.id, before, item);
      const movement = await tx.inventoryMovement.findFirst({ where: { companyId, operationId }, orderBy: { createdAt: 'desc' } });
      return { item, movement };
    });
  }

  async settings(companyId: string, actor: Actor, productId: string, variantId: string | null, input: InventorySettingsInput) {
    return prisma.$transaction(async tx => {
      await this.lockTarget(tx, companyId, productId, variantId);
      const before = await this.item(companyId, productId, variantId, tx); this.assertStockRevision(before, input.expectedRevision);
      const data = { minimumStockMil: input.minimumStockMil, reorderPointMil: input.reorderPointMil ?? null };
      if (variantId) await tx.productVariant.update({ where: { id: variantId }, data });
      else await tx.product.update({ where: { id: productId }, data });
      if (variantId) await tx.product.update({ where: { id: productId }, data: { updatedAt: new Date() } });
      const item = await this.item(companyId, productId, variantId, tx);
      await this.audit(tx, companyId, actor, 'SETTINGS', before.id, before, item);
      return { item };
    });
  }

  async counts(companyId: string, q: InventoryCountListQuery) {
    const where = { companyId, ...(q.status ? { status: q.status } : {}) };
    const [rows, total] = await prisma.$transaction([
      prisma.inventoryCount.findMany({ where, include: { _count: { select: { items: true } }, items: { select: { countedStockMil: true, referenceStockMil: true } } }, orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }], skip: (q.page - 1) * q.pageSize, take: q.pageSize }), prisma.inventoryCount.count({ where }),
    ]);
    const users = await prisma.user.findMany({ where: { id: { in: [...new Set(rows.map(r => r.assigneeUserId))] } }, select: { id: true, name: true } });
    const names = new Map(users.map(u => [u.id, u.name]));
    return { items: rows.map(({ items, _count, ...row }) => ({ ...row, assigneeName: names.get(row.assigneeUserId) ?? 'Responsável não registrado', totalItems: _count.items, countedItems: items.filter(i => i.countedStockMil !== null).length, itemsWithDifference: items.filter(i => i.countedStockMil !== null && i.countedStockMil !== i.referenceStockMil).length })), pagination: { page: q.page, pageSize: q.pageSize, total, totalPages: Math.ceil(total / q.pageSize) } };
  }

  async assignees(companyId: string) {
    const members = await prisma.membership.findMany({ where: { companyId, user: { isActive: true } }, include: { user: { select: { id: true, name: true } }, employeeProfiles: true }, orderBy: { user: { name: 'asc' } } });
    return { items: members.filter(m => { const profile = m.employeeProfiles[0]; return profile ? profile.status === 'ACTIVE' && effectivePermissionsForEmployee(profile).includes('stock.adjust') : defaultPermissionsForRole(roleFromMembershipRole(m.role)).includes('stock.adjust'); }).map(m => ({ userId: m.user.id, name: m.user.name })) };
  }

  async createCount(companyId: string, actor: Actor, input: InventoryCountCreateInput) {
    return this.idempotent(companyId, actor, input.requestId, 'COUNT_CREATE', input, async tx => {
      const session = await tx.inventoryCount.create({ data: { companyId, name: input.name, assigneeUserId: actor.id, createdByUserId: actor.id, requestId: input.requestId } });
      if (input.productIds?.length) {
        const items = await tx.$queryRaw<WorkspaceItem[]>`${inventoryItemsSql(companyId)} SELECT * FROM items WHERE "productId" IN (${Prisma.join(input.productIds)}) AND "isActive" ORDER BY "productId","productVariantId" NULLS FIRST LIMIT 501`;
        if (items.length > 500) fail('Selecione até 500 itens por contagem.', 'INVENTORY_COUNT_ITEM_LIMIT', 422);
        const found = new Set(items.map(i => i.productId));
        if (input.productIds.some(id => !found.has(id))) fail('A seleção contém produto indisponível.', 'INVENTORY_ITEM_NOT_FOUND', 404);
        for (const item of items) await tx.inventoryCountItem.create({ data: this.countItemData(session.id, item, null) });
      }
      await this.audit(tx, companyId, actor, 'COUNT_CREATE', session.id, null, session);
      return this.detail(companyId, session.id, tx);
    });
  }

  async detail(companyId: string, id: string, tx: Tx = prisma) {
    const session = await tx.inventoryCount.findFirst({ where: { id, companyId }, include: { items: { orderBy: [{ productName: 'asc' }, { targetKey: 'asc' }] } } });
    if (!session) fail('Contagem não encontrada.', 'INVENTORY_COUNT_NOT_FOUND', 404);
    const { items: recorded, ...row } = session;
    const [owner, live, history] = await Promise.all([
      tx.user.findUnique({ where: { id: session.assigneeUserId }, select: { name: true } }),
      recorded.length ? tx.$queryRaw<WorkspaceItem[]>`${inventoryItemsSql(companyId)} SELECT * FROM items WHERE "productId" IN (${Prisma.join([...new Set(recorded.map(i => i.productId))])})` : Promise.resolve([] as WorkspaceItem[]),
      tx.inventoryAuditEvent.findMany({ where: { companyId, entityId: id }, orderBy: [{createdAt:'desc'},{id:'desc'}], take:100 }),
    ]);
    const byKey = new Map(live.map(i => [targetKey(i.productId, i.productVariantId), i]));
    const items = recorded.map(i => { const current = byKey.get(i.targetKey); return { ...i, name: i.productName, currentStockMil: current?.currentStockMil ?? null, stockRevision: current?.stockRevision ?? null, isActive: current?.isActive ?? false, isStale: !terminal.has(session.status) && (!current || current.stockRevision !== i.expectedStockRevision), differenceMil: i.countedStockMil === null ? null : i.countedStockMil - i.referenceStockMil }; });
    return { session: { ...row, assigneeName: owner?.name ?? 'Responsável não registrado', totalItems: items.length, countedItems: items.filter(i => i.countedStockMil !== null).length, itemsWithDifference: items.filter(i => i.differenceMil !== null && i.differenceMil !== 0).length }, items, history };
  }

  async updateCount(companyId: string, actor: Actor, id: string, input: InventoryCountUpdateInput) {
    return prisma.$transaction(async tx => {
      const before = await this.lockCount(tx, companyId, id, input.expectedRevision);
      if (input.assigneeUserId && input.assigneeUserId !== before.assigneeUserId) {
        if (!['OWNER', 'MANAGER'].includes(actor.role)) fail('Somente dono ou gerente pode transferir a contagem.', 'INVENTORY_PERMISSION_REQUIRED', 403);
        const choices = await this.assignees(companyId);
        if (!choices.items.some(m => m.userId === input.assigneeUserId)) fail('O responsável precisa de acesso ativo e permissão para ajustar estoque nesta empresa.', 'INVENTORY_INVALID_ASSIGNEE', 422);
      } else this.assertOwner(before, actor);
      const after = await tx.inventoryCount.update({ where: { id }, data: { ...(input.name ? { name: input.name } : {}), ...(input.assigneeUserId ? { assigneeUserId: input.assigneeUserId } : {}), revision: { increment: 1 }, status: before.status === 'REVIEWED' ? 'COUNTING' : before.status } });
      await this.audit(tx, companyId, actor, 'COUNT_UPDATE', id, before, after);
      return this.detail(companyId, id, tx);
    });
  }

  async putCountItems(companyId: string, actor: Actor, id: string, input: InventoryCountItemsInput) {
    return prisma.$transaction(async tx => {
      const session = await this.lockCount(tx, companyId, id, input.expectedRevision); this.assertOwner(session, actor);
      const seen = new Set<string>();
      const sorted = [...input.items].sort((a, b) => targetKey(a.productId, a.productVariantId).localeCompare(targetKey(b.productId, b.productVariantId)));
      for (const update of sorted) {
        const key = targetKey(update.productId, update.productVariantId);
        if (seen.has(key)) fail('O mesmo item foi enviado mais de uma vez.', 'INVENTORY_DUPLICATE_ITEM', 422); seen.add(key);
        if (update.remove) { await tx.inventoryCountItem.deleteMany({ where: { countId: id, targetKey: key } }); continue; }
        await this.lockTarget(tx, companyId, update.productId, update.productVariantId);
        const item = await this.item(companyId, update.productId, update.productVariantId, tx); this.assertActive(item); this.assertStockRevision(item, update.expectedStockRevision!);
        const data = this.countItemData(id, item, update.countedStockMil!);
        await tx.inventoryCountItem.upsert({ where: { countId_targetKey: { countId: id, targetKey: key } }, create: data, update: data });
      }
      if (await tx.inventoryCountItem.count({ where: { countId: id } }) > 500) fail('Selecione até 500 itens por contagem.', 'INVENTORY_COUNT_ITEM_LIMIT', 422);
      const after = await tx.inventoryCount.update({ where: { id }, data: { status: 'COUNTING', revision: { increment: 1 } } });
      await this.audit(tx, companyId, actor, 'COUNT_ITEMS', id, { revision: session.revision }, { revision: after.revision, items: input.items });
      return this.detail(companyId, id, tx);
    }, { timeout: 30000 });
  }

  async countAction(companyId: string, actor: Actor, id: string, action: 'review' | 'apply' | 'cancel', input: InventoryCountActionInput) {
    return this.idempotent(companyId, actor, input.requestId, 'COUNT_' + action.toUpperCase(), { id, ...input }, async (tx, operationId) => {
      const before = await this.lockCount(tx, companyId, id, input.expectedRevision); this.assertOwner(before, actor);
      if (action !== 'cancel') {
        if (action === 'apply' && before.status !== 'REVIEWED') fail('Revise a contagem antes de aplicar.', 'INVENTORY_COUNT_REVIEW_REQUIRED', 422);
        const items = await tx.inventoryCountItem.findMany({ where: { countId: id }, orderBy: { targetKey: 'asc' } });
        if (!items.length || items.some(i => i.countedStockMil === null)) fail('Conte todos os itens selecionados antes de revisar.', 'INVENTORY_COUNT_INCOMPLETE', 422);
        const checked: Array<{ item: WorkspaceItem; counted: number }> = [];
        for (const countItem of items) {
          await this.lockTarget(tx, companyId, countItem.productId, countItem.productVariantId);
          const current = await this.item(companyId, countItem.productId, countItem.productVariantId, tx); this.assertActive(current); this.assertStockRevision(current, countItem.expectedStockRevision);
          checked.push({ item: current, counted: countItem.countedStockMil! });
        }
        if (action === 'apply') {
          await setInventoryContext(tx, { actorUserId: actor.id, actorName: actor.name, type: 'COUNT_ADJUSTMENT', origin: 'inventory_count', referenceId: id, operationId, reason: 'Aplicação de contagem revisada' });
          for (const { item, counted } of checked) if (counted !== item.currentStockMil) await this.writeStock(tx, item.productId, item.productVariantId, counted);
        }
      }
      const status = action === 'apply' ? 'APPLIED' : action === 'review' ? 'REVIEWED' : 'CANCELED';
      const after = await tx.inventoryCount.update({ where: { id }, data: { status, revision: { increment: 1 }, ...(action === 'apply' ? { appliedAt: new Date() } : {}), ...(action === 'cancel' ? { canceledAt: new Date() } : {}) } });
      await this.audit(tx, companyId, actor, 'COUNT_' + action.toUpperCase(), id, before, after);
      return this.detail(companyId, id, tx);
    });
  }

  private async lockCount(tx: Tx, companyId: string, id: string, expectedRevision: number) {
    await tx.$queryRaw`SELECT id FROM "InventoryCount" WHERE id=${id} AND "companyId"=${companyId} FOR UPDATE`;
    const session = await tx.inventoryCount.findFirst({ where: { id, companyId } });
    if (!session) fail('Contagem não encontrada.', 'INVENTORY_COUNT_NOT_FOUND', 404);
    if (terminal.has(session.status)) fail('A contagem já foi aplicada ou cancelada.', 'INVENTORY_COUNT_CLOSED');
    if (session.revision !== expectedRevision) fail('A contagem mudou em outro acesso. Atualize antes de continuar.', 'INVENTORY_COUNT_REVISION_CONFLICT');
    return session;
  }
  private assertOwner(session: InventoryCount, actor: Actor) {
    if (session.assigneeUserId !== actor.id) fail('Esta contagem está com outro responsável. Solicite a transferência antes de editar.', 'INVENTORY_COUNT_OWNER_REQUIRED', 403);
  }
  private assertStockRevision(item: WorkspaceItem, expected: number) {
    if (item.stockRevision !== expected) fail('O estoque mudou. Atualize e confira novamente a quantidade deste item.', 'INVENTORY_STOCK_REVISION_CONFLICT');
  }
  private assertActive(item: WorkspaceItem) { if (!item.isActive) fail('Este item está inativo.', 'INVENTORY_ITEM_INACTIVE', 422); }
  private countItemData(countId: string, item: WorkspaceItem, countedStockMil: number | null) {
    return { countId, productId: item.productId, productVariantId: item.productVariantId, targetKey: targetKey(item.productId, item.productVariantId), productName: item.name, sku: item.sku, unitMeasure: item.unitMeasure, countedStockMil, referenceStockMil: item.currentStockMil, expectedStockRevision: item.stockRevision };
  }
  private async lockTarget(tx: Tx, companyId: string, productId: string, variantId?: string | null) {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "Product" WHERE id=${productId} AND "companyId"=${companyId} AND "deletedAt" IS NULL FOR UPDATE`;
    if (!rows.length) fail('Item de estoque não encontrado.', 'INVENTORY_ITEM_NOT_FOUND', 404);
    if (variantId) {
      const variants = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "ProductVariant" WHERE id=${variantId} AND "productId"=${productId} FOR UPDATE`;
      if (!variants.length) fail('Variação não encontrada.', 'INVENTORY_ITEM_NOT_FOUND', 404);
    }
  }
  private async writeStock(tx: Tx, productId: string, variantId: string | null | undefined, stockMil: number) {
    if (variantId) {
      await tx.productVariant.update({ where: { id: variantId }, data: { stockMil } });
      const sum = await tx.productVariant.aggregate({ where: { productId, isActive: true }, _sum: { stockMil: true } });
      await tx.product.update({ where: { id: productId }, data: { stockMil: sum._sum.stockMil ?? 0 } });
    } else await tx.product.update({ where: { id: productId }, data: { stockMil } });
  }
  private async audit(tx: Tx, companyId: string, actor: Actor, operation: string, entityId: string, before: unknown, after: unknown) {
    await tx.inventoryAuditEvent.create({ data: { companyId, actorUserId: actor.id, actorName: actor.name, operation, entityId, ...(before == null ? {} : { before: json(before) }), after: json(after) } });
  }
  private async idempotent<T>(companyId: string, actor: Actor, requestId: string, type: string, input: unknown, run: (tx: Tx, operationId: string) => Promise<T>): Promise<T> {
    const fingerprint = createHash('sha256').update(JSON.stringify(input)).digest('hex');
    return prisma.$transaction(async tx => {
      await tx.$queryRaw`SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(${companyId + ':' + requestId},0))`;
      const prior = await tx.inventoryOperation.findUnique({ where: { companyId_requestId: { companyId, requestId } } });
      if (prior) {
        if (prior.actorUserId !== actor.id || prior.type !== type || prior.fingerprint !== fingerprint) fail('Esta chave já foi usada em outra operação.', 'INVENTORY_IDEMPOTENCY_CONFLICT');
        return prior.response as T;
      }
      const operationId = randomUUID(); const result = await run(tx, operationId);
      await tx.inventoryOperation.create({ data: { id: operationId, companyId, requestId, actorUserId: actor.id, type, fingerprint, response: json(result) } });
      return result;
    }, { timeout: 30000 });
  }
}
