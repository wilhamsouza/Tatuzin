import type { FinancialEvent, Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { FinancialEventCreateInput } from './financial-events.schemas';

export class FinancialEventsService {
  async listForCompany(companyId: string) {
    const items = await prisma.financialEvent.findMany({
      where: { companyId },
      orderBy: [{ createdAt: 'desc' }, { updatedAt: 'desc' }],
    });

    return items.map((item) => this.toDto(item));
  }

  async create(companyId: string, input: FinancialEventCreateInput) {
    const existing = await prisma.financialEvent.findFirst({
      where: {
        companyId,
        localUuid: input.localUuid,
      },
    });

    if (existing) {
      if (!this.matches(existing, input)) {
        throw new AppError(
          'Ja existe um evento financeiro com este localUuid, mas com dados divergentes.',
          409,
          'FINANCIAL_EVENT_CONFLICT',
        );
      }

      return this.toDto(existing);
    }

    if (input.saleId != null) {
      const sale = await prisma.sale.findFirst({
        where: {
          id: input.saleId,
          companyId,
        },
        select: { id: true },
      });

      if (!sale) {
        throw new AppError(
          'Venda remota invalida para este evento financeiro.',
          400,
          'SALE_INVALID',
        );
      }
    }

    const event = await prisma.financialEvent.create({
      data: {
        companyId,
        saleId: input.saleId,
        fiadoId: input.fiadoId,
        eventType: input.eventType,
        localUuid: input.localUuid,
        amountCents: input.amountCents,
        paymentType: input.paymentType,
        createdAt: new Date(input.createdAt),
        ...(input.metadata != null
            ? { metadata: input.metadata as Prisma.InputJsonValue }
            : {}),
      },
    });

    return this.toDto(event);
  }

  private matches(existing: FinancialEvent, input: FinancialEventCreateInput) {
    return (
      existing.saleId === input.saleId &&
      existing.fiadoId === input.fiadoId &&
      existing.eventType === input.eventType &&
      existing.amountCents === input.amountCents &&
      existing.paymentType === input.paymentType &&
      JSON.stringify(existing.metadata ?? null) ===
        JSON.stringify(input.metadata ?? null)
    );
  }

  private toDto(event: FinancialEvent) {
    return {
      id: event.id,
      companyId: event.companyId,
      saleId: event.saleId,
      fiadoId: event.fiadoId,
      eventType: event.eventType,
      localUuid: event.localUuid,
      amountCents: event.amountCents,
      paymentType: event.paymentType,
      createdAt: event.createdAt.toISOString(),
      updatedAt: event.updatedAt.toISOString(),
      metadata: event.metadata,
    };
  }
}
