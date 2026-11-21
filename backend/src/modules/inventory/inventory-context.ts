import type { Prisma } from '@prisma/client';

/** Local to the current database transaction; never leaks to the pooled connection. */
export async function setInventoryContext(tx: Prisma.TransactionClient, context: {
  actorUserId?: string; actorName?: string; type?: string; origin?: string;
  referenceId?: string; operationId?: string; reason?: string; notes?: string; skipParent?: boolean;
}) {
  const actorName = context.actorName ?? (context.actorUserId ? (await tx.user.findUnique({ where: { id: context.actorUserId }, select: { name: true } }))?.name : undefined);
  await tx.$queryRaw`SELECT
    set_config('tatuzin.inventory_actor', ${context.actorUserId ?? ''}, true),
    set_config('tatuzin.inventory_actor_name', ${actorName ?? ''}, true),
    set_config('tatuzin.inventory_type', ${context.type ?? ''}, true),
    set_config('tatuzin.inventory_origin', ${context.origin ?? ''}, true),
    set_config('tatuzin.inventory_reference', ${context.referenceId ?? ''}, true),
    set_config('tatuzin.inventory_operation', ${context.operationId ?? ''}, true),
    set_config('tatuzin.inventory_reason', ${context.reason ?? ''}, true),
    set_config('tatuzin.inventory_notes', ${context.notes ?? ''}, true),
    set_config('tatuzin.inventory_skip_parent', ${context.skipParent ? 'true' : ''}, true)`;
}
