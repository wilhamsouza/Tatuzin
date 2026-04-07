import type { CashEvent } from '@prisma/client';

import { prisma } from '../../database/prisma';
import type { CashEventCreateInput } from './cash-events.schemas';

export class CashEventsService {
  async create(companyId: string, input: CashEventCreateInput) {
    const existing = await prisma.cashEvent.findFirst({
      where: {
        companyId,
        localUuid: input.localUuid,
      },
    });

    if (existing) {
      return this.toDto(existing);
    }

    const event = await prisma.cashEvent.create({
      data: {
        companyId,
        localUuid: input.localUuid,
        eventType: input.eventType,
        amountCents: input.amountCents,
        paymentMethod: input.paymentMethod,
        referenceType: input.referenceType,
        referenceId: input.referenceId,
        notes: input.notes,
        createdAt: new Date(input.createdAt),
      },
    });

    return this.toDto(event);
  }

  private toDto(event: CashEvent) {
    return {
      id: event.id,
      companyId: event.companyId,
      localUuid: event.localUuid,
      eventType: event.eventType,
      amountCents: event.amountCents,
      paymentMethod: event.paymentMethod,
      referenceType: event.referenceType,
      referenceId: event.referenceId,
      notes: event.notes,
      createdAt: event.createdAt.toISOString(),
      updatedAt: event.updatedAt.toISOString(),
    };
  }
}
