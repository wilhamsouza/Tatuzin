import type { FiadoPayment } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { FiadoPaymentCreateInput } from './fiado-payments.schemas';

export class FiadoPaymentsService {
  async create(companyId: string, input: FiadoPaymentCreateInput) {
    const existing = await prisma.fiadoPayment.findFirst({
      where: {
        companyId,
        localUuid: input.localUuid,
      },
    });

    if (existing) {
      return this.toDto(existing);
    }

    const sale = await prisma.sale.findFirst({
      where: {
        id: input.saleId,
        companyId,
      },
      select: { id: true },
    });

    if (!sale) {
      throw new AppError(
        'Venda remota invalida para este pagamento de fiado.',
        400,
        'SALE_INVALID',
      );
    }

    const payment = await prisma.fiadoPayment.create({
      data: {
        companyId,
        saleId: input.saleId,
        localUuid: input.localUuid,
        amountCents: input.amountCents,
        paymentMethod: input.paymentMethod,
        notes: input.notes,
        createdAt: new Date(input.createdAt),
      },
    });

    return this.toDto(payment);
  }

  private toDto(payment: FiadoPayment) {
    return {
      id: payment.id,
      companyId: payment.companyId,
      saleId: payment.saleId,
      localUuid: payment.localUuid,
      amountCents: payment.amountCents,
      paymentMethod: payment.paymentMethod,
      notes: payment.notes,
      createdAt: payment.createdAt.toISOString(),
      updatedAt: payment.updatedAt.toISOString(),
    };
  }
}
