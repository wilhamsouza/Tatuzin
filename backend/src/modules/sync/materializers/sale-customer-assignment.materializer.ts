import { z } from 'zod';
import type { SyncMaterializerInput, SyncMaterializerResult } from './materializer.types';
import { requireSyncPermission, canManageOtherCashSessions } from './sync-authorization';

const assignmentSchema = z.object({
  saleUuid: z.string().min(1).max(160),
  customerServerId: z.string().uuid().nullable(),
  customerUuid: z.string().min(1).max(160),
  expectedRevision: z.number().int().nonnegative(),
  previousCustomerServerId: z.string().uuid().nullable(),
  previousCustomerUuid: z.string().max(160).nullable(),
});

export class SaleCustomerAssignmentMaterializer {
  async materialize(input: SyncMaterializerInput): Promise<SyncMaterializerResult> {
    if (input.event.operation !== 'append') return {
      outcome: 'rejected', code: 'INVALID_OPERATION', message: 'Associação aceita somente append.' };
    if (input.event.entity === 'saleCustomerLock') {
      const permission = requireSyncPermission(input, 'sales.create', 'Sem permissão para registrar bloqueio da venda.');
      if (!canManageOtherCashSessions(input) && permission) return permission;
      const uuid = z.string().min(1).max(160).safeParse(input.payload.saleUuid);
      if (!uuid.success) return { outcome: 'rejected', code: 'INVALID_SALE_LOCK', message: 'Venda inválida.' };
      const sale = await input.tx.sale.findUnique({ where: { companyId_localUuid: {
        companyId: input.context.company.id, localUuid: uuid.data } } });
      if (!sale) return { outcome: 'deferred', code: 'SALE_DEPENDENCY_PENDING', message: 'Aguardando venda.' };
      await input.tx.sale.update({ where: { id: sale.id }, data: { customerAssignmentLocked: true } });
      return { outcome: 'accepted', entityServerId: sale.id, materializedAt: new Date() };
    }
    const parsed = assignmentSchema.safeParse(input.payload);
    if (!parsed.success) return { outcome: 'rejected', code: 'INVALID_CUSTOMER_ASSIGNMENT',
      message: 'Associação de cliente inválida.' };
    const privileged = canManageOtherCashSessions(input);
    const permission = requireSyncPermission(input, 'sales.create', 'Sem permissão para associar clientes.');
    if (!privileged && permission) return permission;
    const companyId = input.context.company.id;
    const data = parsed.data;
    const sale = await input.tx.sale.findUnique({ where: { companyId_localUuid: {
      companyId, localUuid: data.saleUuid } } });
    if (!sale) return { outcome: 'deferred', code: 'SALE_DEPENDENCY_PENDING', message: 'Aguardando sincronização da venda.' };
    const duplicate = await input.tx.saleCustomerAssignment.findUnique({ where: { id: input.event.eventId } });
    if (duplicate) return duplicate.saleId === sale.id && duplicate.companyId === companyId &&
        duplicate.actorUserId === input.context.user.id && duplicate.deviceId === input.context.device.id
      ? { outcome: 'duplicate', entityServerId: sale.id }
      : { outcome: 'rejected', code: 'ASSIGNMENT_ID_CONFLICT', message: 'Identidade de associação já utilizada.' };
    if (!privileged && sale.sellerUserId !== input.context.user.id) return {
      outcome: 'rejected', code: 'SALE_CUSTOMER_FORBIDDEN', message: 'Operador pode alterar somente suas próprias vendas.' };
    const financialRestriction = await input.tx.financialEvent.findFirst({ where: {
      companyId, saleId: sale.id, OR: [
        { fiadoId: { not: null } },
        { eventType: { in: ['sale_return', 'sale_exchange', 'return', 'exchange', 'customer_credit', 'credit_used', 'credit_generated'] } },
      ],
    }, select: { id: true } });
    const linkedExchange = await input.tx.operationalOrder.findFirst({ where: {
      companyId, convertedSaleId: sale.id, status: { in: ['returned', 'exchanged'] },
    }, select: { id: true } });
    if (sale.customerAssignmentLocked || sale.status !== 'active' || ['fiado','credit'].includes(sale.paymentType) ||
        sale.paymentMethod === 'fiado' || sale.creditUsedCents > 0 || sale.creditGeneratedCents > 0 ||
        financialRestriction || linkedExchange) return {
      outcome: 'rejected', code: 'SALE_CUSTOMER_FINANCIAL_LOCK',
      message: 'Cliente só pode ser alterado em venda ativa sem fiado, haver, troca ou devolução.' };
    const customer = await input.tx.customer.findFirst({ where: {
      ...(data.customerServerId ? { id: data.customerServerId } : { localUuid: data.customerUuid }),
      companyId, deletedAt: null, isActive: true }, select: { id: true } });
    if (!customer) return { outcome: data.customerServerId ? 'rejected' : 'deferred',
      code: 'CUSTOMER_NOT_AVAILABLE', message: 'Cliente não está disponível nesta empresa. Sincronize o cadastro.' };
    const previous = data.previousCustomerServerId ?? (data.previousCustomerUuid
      ? (await input.tx.customer.findFirst({ where: { companyId, localUuid: data.previousCustomerUuid }, select: { id: true } }))?.id
      : null);
    if (data.previousCustomerUuid && !previous) return { outcome: 'deferred',
      code: 'CUSTOMER_DEPENDENCY_PENDING', message: 'Aguardando o cliente anterior.' };
    const changed = await input.tx.sale.updateMany({ where: { id: sale.id, companyId,
      customerAssignmentRevision: data.expectedRevision,
      customerId: previous ?? null, status: 'active',
      customerAssignmentLocked: false,
    }, data: { customerId: customer.id, customerAssignmentRevision: { increment: 1 } } });
    if (changed.count !== 1) return { outcome: 'conflict', code: 'SALE_CUSTOMER_REVISION_CONFLICT',
      message: 'O cliente desta venda foi alterado em outro dispositivo. Consulte o vínculo atual antes de corrigir.',
      payload: { saleUuid: sale.localUuid, customerServerId: sale.customerId,
        revision: sale.customerAssignmentRevision } };
    await input.tx.saleCustomerAssignment.create({ data: {
      id: input.event.eventId, companyId, saleId: sale.id, previousCustomerId: sale.customerId,
      customerId: customer.id, revision: data.expectedRevision + 1,
      actorUserId: input.context.user.id, deviceId: input.context.device.id,
      occurredAt: new Date(input.event.occurredAt),
    } });
    return { outcome: 'accepted', entityServerId: sale.id, materializedAt: new Date() };
  }
}
