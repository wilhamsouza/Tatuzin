import type { Prisma, Sale, SaleItem } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type {
  SaleCancelInput,
  SaleCreateInput,
  SaleItemInput,
} from './sales.schemas';

type SaleWithItems = Sale & { items: SaleItem[] };
type SaleWithCount = Sale & { _count: { items: number } };

export class SalesService {
  async listForCompany(companyId: string) {
    const sales = await prisma.sale.findMany({
      where: { companyId },
      include: {
        _count: {
          select: { items: true },
        },
      },
      orderBy: [{ soldAt: 'desc' }, { updatedAt: 'desc' }],
    });

    return sales.map((sale) => this.toSaleSummaryDto(sale));
  }

  async getById(companyId: string, saleId: string) {
    const sale = await prisma.sale.findFirst({
      where: {
        id: saleId,
        companyId,
      },
      include: {
        items: {
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    if (!sale) {
      throw new AppError('Venda nao encontrada.', 404, 'SALE_NOT_FOUND');
    }

    return this.toSaleDto(sale);
  }

  async create(companyId: string, input: SaleCreateInput) {
    const existing = await prisma.sale.findFirst({
      where: {
        companyId,
        localUuid: input.localUuid,
      },
      include: {
        items: {
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    if (existing) {
      return this.toSaleDto(existing);
    }

    const customerId = await this.resolveCustomerId(companyId, input.customerId);
    const items = await this.resolveItems(companyId, input.items);

    const sale = await prisma.sale.create({
      data: {
        companyId,
        localUuid: input.localUuid,
        customerId,
        receiptNumber: input.receiptNumber,
        paymentType: input.paymentType,
        paymentMethod: input.paymentMethod,
        status: input.status,
        totalAmountCents: input.totalAmountCents,
        totalCostCents: input.totalCostCents,
        soldAt: new Date(input.soldAt),
        notes: input.notes,
        items: {
          create: items,
        },
      },
      include: {
        items: {
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    return this.toSaleDto(sale);
  }

  async cancel(companyId: string, saleId: string, input: SaleCancelInput) {
    const sale = await prisma.sale.findFirst({
      where: {
        id: saleId,
        companyId,
      },
      include: {
        items: {
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    if (!sale) {
      throw new AppError('Venda nao encontrada.', 404, 'SALE_NOT_FOUND');
    }

    if (sale.localUuid !== input.localUuid) {
      throw new AppError(
        'O localUuid informado nao corresponde a venda remota.',
        409,
        'SALE_UUID_MISMATCH',
      );
    }

    if (sale.status === 'canceled') {
      return this.toSaleDto(sale);
    }

    const canceled = await prisma.sale.update({
      where: { id: saleId },
      data: {
        status: 'canceled',
        canceledAt: new Date(input.canceledAt),
      },
      include: {
        items: {
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    return this.toSaleDto(canceled);
  }

  private async resolveCustomerId(companyId: string, customerId: string | null) {
    if (customerId == null) {
      return null;
    }

    const customer = await prisma.customer.findFirst({
      where: {
        id: customerId,
        companyId,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!customer) {
      throw new AppError(
        'Cliente remoto invalido para esta venda.',
        400,
        'CUSTOMER_INVALID',
      );
    }

    return customer.id;
  }

  private async resolveItems(companyId: string, items: SaleItemInput[]) {
    const resolvedItems: Prisma.SaleItemUncheckedCreateWithoutSaleInput[] = [];

    for (const item of items) {
      const productId = await this.resolveProductId(companyId, item.productId);
      resolvedItems.push({
        productId,
        productNameSnapshot: item.productNameSnapshot,
        quantityMil: item.quantityMil,
        unitPriceCents: item.unitPriceCents,
        totalPriceCents: item.totalPriceCents,
        unitCostCents: item.unitCostCents,
        totalCostCents: item.totalCostCents,
        unitMeasure: item.unitMeasure,
        productType: item.productType,
      });
    }

    return resolvedItems;
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
        'Produto remoto invalido para esta venda.',
        400,
        'PRODUCT_INVALID',
      );
    }

    return product.id;
  }

  private toSaleSummaryDto(sale: SaleWithCount) {
    return {
      id: sale.id,
      companyId: sale.companyId,
      localUuid: sale.localUuid,
      customerId: sale.customerId,
      receiptNumber: sale.receiptNumber,
      paymentType: sale.paymentType,
      paymentMethod: sale.paymentMethod,
      status: sale.status,
      totalAmountCents: sale.totalAmountCents,
      totalCostCents: sale.totalCostCents,
      soldAt: sale.soldAt.toISOString(),
      canceledAt: sale.canceledAt?.toISOString() ?? null,
      notes: sale.notes,
      itemsCount: sale._count.items,
      createdAt: sale.createdAt.toISOString(),
      updatedAt: sale.updatedAt.toISOString(),
    };
  }

  private toSaleDto(sale: SaleWithItems) {
    return {
      id: sale.id,
      companyId: sale.companyId,
      localUuid: sale.localUuid,
      customerId: sale.customerId,
      receiptNumber: sale.receiptNumber,
      paymentType: sale.paymentType,
      paymentMethod: sale.paymentMethod,
      status: sale.status,
      totalAmountCents: sale.totalAmountCents,
      totalCostCents: sale.totalCostCents,
      soldAt: sale.soldAt.toISOString(),
      canceledAt: sale.canceledAt?.toISOString() ?? null,
      notes: sale.notes,
      createdAt: sale.createdAt.toISOString(),
      updatedAt: sale.updatedAt.toISOString(),
      items: sale.items.map((item) => ({
        id: item.id,
        saleId: item.saleId,
        productId: item.productId,
        productNameSnapshot: item.productNameSnapshot,
        quantityMil: item.quantityMil,
        unitPriceCents: item.unitPriceCents,
        totalPriceCents: item.totalPriceCents,
        unitCostCents: item.unitCostCents,
        totalCostCents: item.totalCostCents,
        unitMeasure: item.unitMeasure,
        productType: item.productType,
        createdAt: item.createdAt.toISOString(),
        updatedAt: item.updatedAt.toISOString(),
      })),
    };
  }
}
