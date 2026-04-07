import type { Prisma, Purchase, PurchaseItem, PurchasePayment } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type {
  PurchaseItemInput,
  PurchasePaymentInput,
  PurchaseUpsertInput,
} from './purchases.schemas';

type PurchaseWithRelations = Purchase & {
  items: PurchaseItem[];
  payments: PurchasePayment[];
  supplier: {
    id: string;
    localUuid: string;
    name: string;
  };
};

export class PurchasesService {
  async listForCompany(companyId: string) {
    const purchases = await prisma.purchase.findMany({
      where: { companyId },
      include: {
        supplier: {
          select: {
            id: true,
            localUuid: true,
            name: true,
          },
        },
        items: {
          orderBy: { createdAt: 'asc' },
        },
        payments: {
          orderBy: { paidAt: 'asc' },
        },
      },
      orderBy: [{ purchasedAt: 'desc' }, { updatedAt: 'desc' }],
    });

    return purchases.map((purchase) => this.toPurchaseDto(purchase));
  }

  async getById(companyId: string, purchaseId: string) {
    const purchase = await prisma.purchase.findFirst({
      where: {
        id: purchaseId,
        companyId,
      },
      include: {
        supplier: {
          select: {
            id: true,
            localUuid: true,
            name: true,
          },
        },
        items: {
          orderBy: { createdAt: 'asc' },
        },
        payments: {
          orderBy: { paidAt: 'asc' },
        },
      },
    });

    if (!purchase) {
      throw new AppError('Compra nao encontrada.', 404, 'PURCHASE_NOT_FOUND');
    }

    return this.toPurchaseDto(purchase);
  }

  async create(companyId: string, input: PurchaseUpsertInput) {
    const existing = await prisma.purchase.findFirst({
      where: {
        companyId,
        localUuid: input.localUuid,
      },
      select: { id: true },
    });

    if (existing) {
      return this.update(companyId, existing.id, input);
    }

    const supplierId = await this.resolveSupplierId(companyId, input.supplierId);
    const items = await this.resolveItems(companyId, input.items);
    const payments = this.resolvePayments(input.payments);

    const purchase = await prisma.purchase.create({
      data: {
        companyId,
        localUuid: input.localUuid,
        supplierId,
        documentNumber: input.documentNumber,
        notes: input.notes,
        purchasedAt: new Date(input.purchasedAt),
        dueDate: input.dueDate == null ? null : new Date(input.dueDate),
        paymentMethod: input.paymentMethod,
        status: input.status,
        subtotalCents: input.subtotalCents,
        discountCents: input.discountCents,
        surchargeCents: input.surchargeCents,
        freightCents: input.freightCents,
        finalAmountCents: input.finalAmountCents,
        paidAmountCents: input.paidAmountCents,
        pendingAmountCents: input.pendingAmountCents,
        canceledAt: input.canceledAt == null ? null : new Date(input.canceledAt),
        items: {
          create: items,
        },
        payments: {
          create: payments,
        },
      },
      include: {
        supplier: {
          select: {
            id: true,
            localUuid: true,
            name: true,
          },
        },
        items: {
          orderBy: { createdAt: 'asc' },
        },
        payments: {
          orderBy: { paidAt: 'asc' },
        },
      },
    });

    return this.toPurchaseDto(purchase);
  }

  async update(companyId: string, purchaseId: string, input: PurchaseUpsertInput) {
    const existing = await prisma.purchase.findFirst({
      where: {
        id: purchaseId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Compra nao encontrada.', 404, 'PURCHASE_NOT_FOUND');
    }

    const supplierId = await this.resolveSupplierId(companyId, input.supplierId);
    const items = await this.resolveItems(companyId, input.items);
    const payments = this.resolvePayments(input.payments);

    const purchase = await prisma.$transaction(async (tx) => {
      await tx.purchaseItem.deleteMany({
        where: { purchaseId },
      });
      await tx.purchasePayment.deleteMany({
        where: { purchaseId },
      });

      return tx.purchase.update({
        where: { id: purchaseId },
        data: {
          localUuid: input.localUuid,
          supplierId,
          documentNumber: input.documentNumber,
          notes: input.notes,
          purchasedAt: new Date(input.purchasedAt),
          dueDate: input.dueDate == null ? null : new Date(input.dueDate),
          paymentMethod: input.paymentMethod,
          status: input.status,
          subtotalCents: input.subtotalCents,
          discountCents: input.discountCents,
          surchargeCents: input.surchargeCents,
          freightCents: input.freightCents,
          finalAmountCents: input.finalAmountCents,
          paidAmountCents: input.paidAmountCents,
          pendingAmountCents: input.pendingAmountCents,
          canceledAt:
            input.canceledAt == null ? null : new Date(input.canceledAt),
          items: {
            create: items,
          },
          payments: {
            create: payments,
          },
        },
        include: {
          supplier: {
            select: {
              id: true,
              localUuid: true,
              name: true,
            },
          },
          items: {
            orderBy: { createdAt: 'asc' },
          },
          payments: {
            orderBy: { paidAt: 'asc' },
          },
        },
      });
    });

    return this.toPurchaseDto(purchase);
  }

  private async resolveSupplierId(companyId: string, supplierId: string) {
    const supplier = await prisma.supplier.findFirst({
      where: {
        id: supplierId,
        companyId,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!supplier) {
      throw new AppError(
        'Fornecedor remoto invalido para esta compra.',
        400,
        'SUPPLIER_INVALID',
      );
    }

    return supplier.id;
  }

  private async resolveItems(companyId: string, items: PurchaseItemInput[]) {
    const resolvedItems: Prisma.PurchaseItemUncheckedCreateWithoutPurchaseInput[] = [];

    for (const item of items) {
      const productId = await this.resolveProductId(companyId, item.productId);
      resolvedItems.push({
        localUuid: item.localUuid,
        productId,
        productNameSnapshot: item.productNameSnapshot,
        unitMeasureSnapshot: item.unitMeasureSnapshot,
        quantityMil: item.quantityMil,
        unitCostCents: item.unitCostCents,
        subtotalCents: item.subtotalCents,
      });
    }

    return resolvedItems;
  }

  private resolvePayments(payments: PurchasePaymentInput[]) {
    return payments.map(
      (payment): Prisma.PurchasePaymentUncheckedCreateWithoutPurchaseInput => ({
        localUuid: payment.localUuid,
        amountCents: payment.amountCents,
        paymentMethod: payment.paymentMethod,
        paidAt: new Date(payment.paidAt),
        notes: payment.notes,
      }),
    );
  }

  private async resolveProductId(companyId: string, productId: string | null) {
    if (productId == null) {
      return null;
    }

    const product = await prisma.product.findFirst({
      where: {
        id: productId,
        companyId,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!product) {
      throw new AppError(
        'Produto remoto invalido para esta compra.',
        400,
        'PRODUCT_INVALID',
      );
    }

    return product.id;
  }

  private toPurchaseDto(purchase: PurchaseWithRelations) {
    return {
      id: purchase.id,
      companyId: purchase.companyId,
      localUuid: purchase.localUuid,
      supplierId: purchase.supplierId,
      supplierLocalUuid: purchase.supplier.localUuid,
      supplierName: purchase.supplier.name,
      documentNumber: purchase.documentNumber,
      notes: purchase.notes,
      purchasedAt: purchase.purchasedAt.toISOString(),
      dueDate: purchase.dueDate?.toISOString() ?? null,
      paymentMethod: purchase.paymentMethod,
      status: purchase.status,
      subtotalCents: purchase.subtotalCents,
      discountCents: purchase.discountCents,
      surchargeCents: purchase.surchargeCents,
      freightCents: purchase.freightCents,
      finalAmountCents: purchase.finalAmountCents,
      paidAmountCents: purchase.paidAmountCents,
      pendingAmountCents: purchase.pendingAmountCents,
      canceledAt: purchase.canceledAt?.toISOString() ?? null,
      createdAt: purchase.createdAt.toISOString(),
      updatedAt: purchase.updatedAt.toISOString(),
      items: purchase.items.map((item) => ({
        id: item.id,
        localUuid: item.localUuid,
        purchaseId: item.purchaseId,
        productId: item.productId,
        productNameSnapshot: item.productNameSnapshot,
        unitMeasureSnapshot: item.unitMeasureSnapshot,
        quantityMil: item.quantityMil,
        unitCostCents: item.unitCostCents,
        subtotalCents: item.subtotalCents,
        createdAt: item.createdAt.toISOString(),
        updatedAt: item.updatedAt.toISOString(),
      })),
      payments: purchase.payments.map((payment) => ({
        id: payment.id,
        localUuid: payment.localUuid,
        purchaseId: payment.purchaseId,
        amountCents: payment.amountCents,
        paymentMethod: payment.paymentMethod,
        paidAt: payment.paidAt.toISOString(),
        notes: payment.notes,
        createdAt: payment.createdAt.toISOString(),
        updatedAt: payment.updatedAt.toISOString(),
      })),
    };
  }
}
