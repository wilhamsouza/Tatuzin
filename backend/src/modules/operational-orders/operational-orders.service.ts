import { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { OperationalOrderListQueryInput } from './operational-orders.schemas';

const operationalOrderSummaryInclude = {
  _count: {
    select: {
      items: true,
    },
  },
} satisfies Prisma.OperationalOrderInclude;

const operationalOrderDetailInclude = {
  items: {
    orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
  },
  convertedSale: {
    select: {
      id: true,
      localUuid: true,
      status: true,
      receiptNumber: true,
      paymentType: true,
      paymentMethod: true,
      totalAmountCents: true,
      soldAt: true,
      canceledAt: true,
      createdAt: true,
      updatedAt: true,
    },
  },
  customer: {
    select: {
      id: true,
      localUuid: true,
      name: true,
      phone: true,
      isActive: true,
    },
  },
  sellerUser: {
    select: {
      id: true,
      name: true,
      email: true,
      isActive: true,
    },
  },
  device: {
    select: {
      id: true,
      clientInstanceId: true,
      deviceLabel: true,
      platform: true,
      appVersion: true,
      status: true,
      lastSeenAt: true,
    },
  },
} satisfies Prisma.OperationalOrderInclude;

type OperationalOrderSummary = Prisma.OperationalOrderGetPayload<{
  include: typeof operationalOrderSummaryInclude;
}>;

type OperationalOrderDetail = Prisma.OperationalOrderGetPayload<{
  include: typeof operationalOrderDetailInclude;
}>;

export class OperationalOrdersService {
  async listForCompany(companyId: string, query: OperationalOrderListQueryInput) {
    const where = this.buildWhere(companyId, query);
    const [total, orders] = await prisma.$transaction([
      prisma.operationalOrder.count({ where }),
      prisma.operationalOrder.findMany({
        where,
        include: operationalOrderSummaryInclude,
        skip: (query.page - 1) * query.limit,
        take: query.limit,
        orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
      }),
    ]);

    return {
      items: orders.map((order) => this.toSummaryDto(order)),
      total,
    };
  }

  async getById(companyId: string, orderId: string) {
    const order = await prisma.operationalOrder.findFirst({
      where: {
        id: orderId,
        companyId,
      },
      include: operationalOrderDetailInclude,
    });

    if (order == null) {
      throw new AppError(
        'Pedido operacional nao encontrado.',
        404,
        'OPERATIONAL_ORDER_NOT_FOUND',
      );
    }

    return this.toDetailDto(order);
  }

  async getByLocalUuid(companyId: string, localUuid: string) {
    const order = await prisma.operationalOrder.findUnique({
      where: {
        companyId_localUuid: {
          companyId,
          localUuid,
        },
      },
      include: operationalOrderDetailInclude,
    });

    if (order == null) {
      throw new AppError(
        'Pedido operacional nao encontrado.',
        404,
        'OPERATIONAL_ORDER_NOT_FOUND',
      );
    }

    return this.toDetailDto(order);
  }

  async listItems(companyId: string, orderId: string) {
    const existingOrder = await prisma.operationalOrder.findFirst({
      where: {
        id: orderId,
        companyId,
      },
      select: {
        id: true,
      },
    });

    if (existingOrder == null) {
      throw new AppError(
        'Pedido operacional nao encontrado.',
        404,
        'OPERATIONAL_ORDER_NOT_FOUND',
      );
    }

    const items = await prisma.operationalOrderItem.findMany({
      where: {
        companyId,
        operationalOrderId: orderId,
      },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });

    return items.map((item) => this.toItemDto(item));
  }

  private buildWhere(
    companyId: string,
    query: OperationalOrderListQueryInput,
  ): Prisma.OperationalOrderWhereInput {
    return {
      companyId,
      ...(query.status == null ? {} : { status: query.status }),
      ...(query.cashSessionId == null
        ? {}
        : { cashSessionId: query.cashSessionId }),
      ...(query.customerId == null ? {} : { customerId: query.customerId }),
      ...(query.deviceId == null ? {} : { deviceId: query.deviceId }),
      ...(query.sellerUserId == null
        ? {}
        : { sellerUserId: query.sellerUserId }),
      ...(query.convertedSaleId == null
        ? {}
        : { convertedSaleId: query.convertedSaleId }),
      ...this.createdAtRange(query.from, query.to),
    };
  }

  private createdAtRange(from: Date | undefined, to: Date | undefined) {
    if (from == null && to == null) {
      return {};
    }

    return {
      createdAt: {
        ...(from == null ? {} : { gte: from }),
        ...(to == null ? {} : { lte: to }),
      },
    };
  }

  private toSummaryDto(order: OperationalOrderSummary) {
    return {
      id: order.id,
      localUuid: order.localUuid,
      status: order.status,
      cashSessionId: order.cashSessionId,
      customerId: order.customerId,
      sellerUserId: order.sellerUserId,
      deviceId: order.deviceId,
      subtotalCents: order.subtotalCents,
      discountCents: order.discountCents,
      totalCents: order.totalCents,
      notes: order.notes,
      createdAt: order.createdAt.toISOString(),
      updatedAt: order.updatedAt.toISOString(),
      closedAt: order.closedAt?.toISOString() ?? null,
      cancelledAt: order.cancelledAt?.toISOString() ?? null,
      convertedSaleId: order.convertedSaleId,
      itemsCount: order._count.items,
    };
  }

  private toDetailDto(order: OperationalOrderDetail) {
    return {
      id: order.id,
      companyId: order.companyId,
      localUuid: order.localUuid,
      status: order.status,
      cashSessionId: order.cashSessionId,
      customerId: order.customerId,
      sellerUserId: order.sellerUserId,
      deviceId: order.deviceId,
      subtotalCents: order.subtotalCents,
      discountCents: order.discountCents,
      totalCents: order.totalCents,
      notes: order.notes,
      createdAt: order.createdAt.toISOString(),
      updatedAt: order.updatedAt.toISOString(),
      closedAt: order.closedAt?.toISOString() ?? null,
      cancelledAt: order.cancelledAt?.toISOString() ?? null,
      convertedSaleId: order.convertedSaleId,
      items: order.items.map((item) => this.toItemDto(item)),
      convertedSale:
        order.convertedSale == null
          ? null
          : {
              id: order.convertedSale.id,
              localUuid: order.convertedSale.localUuid,
              status: order.convertedSale.status,
              receiptNumber: order.convertedSale.receiptNumber,
              paymentType: order.convertedSale.paymentType,
              paymentMethod: order.convertedSale.paymentMethod,
              totalAmountCents: order.convertedSale.totalAmountCents,
              soldAt: order.convertedSale.soldAt.toISOString(),
              canceledAt:
                order.convertedSale.canceledAt?.toISOString() ?? null,
              createdAt: order.convertedSale.createdAt.toISOString(),
              updatedAt: order.convertedSale.updatedAt.toISOString(),
            },
      customer:
        order.customer == null
          ? null
          : {
              id: order.customer.id,
              localUuid: order.customer.localUuid,
              name: order.customer.name,
              phone: order.customer.phone,
              isActive: order.customer.isActive,
            },
      sellerUser:
        order.sellerUser == null
          ? null
          : {
              id: order.sellerUser.id,
              name: order.sellerUser.name,
              email: order.sellerUser.email,
              isActive: order.sellerUser.isActive,
            },
      device:
        order.device == null
          ? null
          : {
              id: order.device.id,
              clientInstanceId: order.device.clientInstanceId,
              deviceLabel: order.device.deviceLabel,
              platform: order.device.platform,
              appVersion: order.device.appVersion,
              status: order.device.status,
              lastSeenAt: order.device.lastSeenAt?.toISOString() ?? null,
            },
    };
  }

  private toItemDto(item: {
    id: string;
    localUuid: string;
    productId: string | null;
    productVariantId: string | null;
    description: string;
    quantityMil: number;
    unitPriceCents: number;
    totalCents: number;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: item.id,
      localUuid: item.localUuid,
      productId: item.productId,
      productVariantId: item.productVariantId,
      description: item.description,
      quantityMil: item.quantityMil,
      unitPriceCents: item.unitPriceCents,
      totalCents: item.totalCents,
      createdAt: item.createdAt.toISOString(),
      updatedAt: item.updatedAt.toISOString(),
    };
  }
}
