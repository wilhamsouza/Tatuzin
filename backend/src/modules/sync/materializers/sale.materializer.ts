import {
  domainIdentityFor,
  firstDate,
  firstIdentity,
  firstString,
  firstUuid,
  isUuid,
  nonNegativeInt,
  positiveInt,
} from './payload-utils';
import { OperationalOrderMaterializer } from './operational-order.materializer';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';

export class SaleMaterializer {
  constructor(
    private readonly operationalOrderMaterializer =
      new OperationalOrderMaterializer(),
  ) {}

  async materializeSale(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (['update', 'delete'].includes(input.event.operation)) {
      const existing = await this.findSale(input);
      if (existing == null) {
        return {
          outcome: 'conflict',
          code: 'SALE_NOT_FOUND',
          message: 'Venda nao encontrada para alteracao offline.',
          payload: this.saleLookupPayload(input),
        };
      }

      if (existing.status !== 'canceled') {
        return {
          outcome: 'conflict',
          code: 'SALE_IMMUTABLE',
          message: 'Venda finalizada nao pode ser alterada por evento offline.',
          payload: {
            saleId: existing.id,
            status: existing.status,
          },
        };
      }
    }

    if (!['create', 'upsert', 'append'].includes(input.event.operation)) {
      return {
        outcome: 'rejected',
        code: 'INVALID_OPERATION',
        message: 'sale aceita create, upsert ou append nesta etapa.',
      };
    }

    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        'saleUuid',
        'saleLocalUuid',
        'saleLocalId',
        'uuid',
        'localUuid',
        'localId',
        'id',
      ],
      { preferIdempotencyKey: true },
    );
    if (localUuid == null) {
      return {
        outcome: 'rejected',
        code: 'LOCAL_ID_REQUIRED',
        message: 'sale precisa de entityLocalId, uuid ou localId.',
      };
    }

    const existing = await input.tx.sale.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    if (existing != null) {
      const existingConversion = await this.convertExistingSaleOrder(
        input,
        existing.id,
      );
      if (existingConversion != null) {
        return existingConversion;
      }
      return { outcome: 'duplicate', entityServerId: existing.id };
    }

    const operationalOrder = await this.operationalOrderMaterializer.findOrder(
      input,
    );
    if (operationalOrder != null) {
      const conflict = this.orderConversionConflict(operationalOrder);
      if (conflict != null) {
        return conflict;
      }
    }

    const receiptNumber = firstString(input.payload, ['receiptNumber', 'number']);
    if (receiptNumber != null) {
      const receiptOwner = await input.tx.sale.findFirst({
        where: {
          companyId: input.context.company.id,
          receiptNumber,
        },
        select: { id: true, localUuid: true },
      });
      if (receiptOwner != null) {
        return {
          outcome: 'conflict',
          code: 'DUPLICATE_RECEIPT',
          message: 'Numero de comprovante ja pertence a outra venda.',
          payload: {
            receiptNumber,
            existingSaleId: receiptOwner.id,
            existingSaleLocalUuid: receiptOwner.localUuid,
          },
        };
      }
    }

    const totalAmountCents =
      nonNegativeInt(input.payload, [
        'totalAmountCents',
        'finalCents',
        'totalCents',
        'amountCents',
      ]) ?? 0;

    const customerId = await this.resolveCustomerId(input);
    const cashSession = await this.findCashSession(input);
    const created = await input.tx.sale.create({
      data: {
        companyId: input.context.company.id,
        cashSessionId: cashSession?.id,
        localUuid,
        customerId,
        receiptNumber,
        paymentType: this.paymentType(input),
        paymentMethod: this.paymentMethod(input),
        status: this.saleStatus(input),
        totalAmountCents,
        totalCostCents:
          nonNegativeInt(input.payload, ['totalCostCents', 'costCents']) ?? 0,
        soldAt: firstDate(input.payload, ['soldAt', 'occurredAt'], new Date()),
        notes: firstString(input.payload, ['notes']),
      },
    });

    if (operationalOrder != null) {
      await input.tx.operationalOrder.update({
        where: { id: operationalOrder.id },
        data: {
          status: 'converted',
          closedAt: operationalOrder.closedAt ?? new Date(),
          convertedSaleId: created.id,
        },
      });
    }

    return {
      outcome: 'accepted',
      entityServerId: created.id,
      materializedAt: created.updatedAt,
    };
  }

  async materializeSaleItem(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!['create', 'append', 'upsert'].includes(input.event.operation)) {
      return {
        outcome: 'rejected',
        code: 'INVALID_OPERATION',
        message: 'saleItem aceita create, append ou upsert nesta etapa.',
      };
    }

    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        'saleItemLocalId',
        'saleItemUuid',
        'itemLocalId',
        'itemUuid',
        'uuid',
        'localUuid',
        'localId',
        'id',
      ],
      { preferIdempotencyKey: true },
    );
    if (localUuid == null) {
      return {
        outcome: 'rejected',
        code: 'LOCAL_ID_REQUIRED',
        message: 'saleItem precisa de entityLocalId, uuid ou localId.',
      };
    }

    const sale = await this.findSale(input);
    if (sale == null) {
      return {
        outcome: 'conflict',
        code: 'SALE_NOT_FOUND',
        message: 'Venda nao encontrada para materializar item.',
        payload: this.saleLookupPayload(input),
      };
    }

    const quantityMil = positiveInt(input.payload, ['quantityMil', 'quantity']);
    if (quantityMil == null) {
      return {
        outcome: 'rejected',
        code: 'INVALID_QUANTITY',
        message: 'saleItem precisa de quantidade positiva.',
      };
    }

    const existing = await input.tx.saleItem.findUnique({
      where: {
        saleId_localUuid: {
          saleId: sale.id,
          localUuid,
        },
      },
    });
    if (existing != null) {
      return { outcome: 'duplicate', entityServerId: existing.id };
    }

    const productId = await this.resolveProductId(input);
    const totalPriceCents =
      nonNegativeInt(input.payload, ['totalPriceCents', 'subtotalCents']) ?? 0;
    const created = await input.tx.saleItem.create({
      data: {
        saleId: sale.id,
        localUuid,
        productId,
        productNameSnapshot:
          firstString(input.payload, ['productNameSnapshot', 'productName']) ??
          'Produto operacional',
        quantityMil,
        unitPriceCents:
          nonNegativeInt(input.payload, ['unitPriceCents', 'priceCents']) ?? 0,
        totalPriceCents,
        unitCostCents: nonNegativeInt(input.payload, ['unitCostCents']) ?? 0,
        totalCostCents: nonNegativeInt(input.payload, ['totalCostCents']) ?? 0,
        unitMeasure: firstString(input.payload, [
          'unitMeasure',
          'unitMeasureSnapshot',
        ]),
        productType: firstString(input.payload, [
          'productType',
          'productTypeSnapshot',
        ]),
      },
    });

    return {
      outcome: 'accepted',
      entityServerId: created.id,
      materializedAt: created.updatedAt,
    };
  }

  async findSale(input: SyncMaterializerInput) {
    const saleId =
      (isUuid(input.event.entityServerId) ? input.event.entityServerId : null) ??
      firstUuid(input.payload, ['saleId', 'saleServerId']);
    if (saleId != null) {
      const sale = await input.tx.sale.findFirst({
        where: {
          id: saleId,
          companyId: input.context.company.id,
        },
      });
      if (sale != null) {
        return sale;
      }
    }

    const localUuid = firstIdentity(input.payload, [
      'saleUuid',
      'saleLocalUuid',
      'saleLocalId',
    ]);
    if (localUuid != null) {
      return input.tx.sale.findUnique({
        where: {
          companyId_localUuid: {
            companyId: input.context.company.id,
            localUuid,
          },
        },
      });
    }

    if (input.event.entity === 'sale') {
      const eventLocalUuid = domainIdentityFor(
        input.event,
        input.payload,
        [
          'saleUuid',
          'saleLocalUuid',
          'saleLocalId',
          'uuid',
          'localUuid',
          'localId',
          'id',
        ],
        { preferIdempotencyKey: true },
      );
      if (eventLocalUuid != null) {
        return input.tx.sale.findUnique({
          where: {
            companyId_localUuid: {
              companyId: input.context.company.id,
              localUuid: eventLocalUuid,
            },
          },
        });
      }
    }

    return null;
  }

  private async resolveCustomerId(input: SyncMaterializerInput) {
    const customerId = firstUuid(input.payload, ['customerId', 'customerServerId']);
    if (customerId == null) {
      return null;
    }
    const customer = await input.tx.customer.findFirst({
      where: {
        id: customerId,
        companyId: input.context.company.id,
        deletedAt: null,
      },
      select: { id: true },
    });
    return customer?.id ?? null;
  }

  private async resolveProductId(input: SyncMaterializerInput) {
    const productId = firstUuid(input.payload, ['productId', 'productServerId']);
    if (productId == null) {
      return null;
    }
    const product = await input.tx.product.findFirst({
      where: {
        id: productId,
        companyId: input.context.company.id,
        deletedAt: null,
      },
      select: { id: true },
    });
    return product?.id ?? null;
  }

  private async findCashSession(input: SyncMaterializerInput) {
    const cashSessionId = firstUuid(input.payload, [
      'cashSessionId',
      'cashSessionServerId',
    ]);
    if (cashSessionId != null) {
      return input.tx.cashSession.findFirst({
        where: { id: cashSessionId, companyId: input.context.company.id },
      });
    }

    const localUuid = firstIdentity(input.payload, [
      'cashSessionUuid',
      'cashSessionLocalId',
    ]);
    if (localUuid == null) {
      return null;
    }
    return input.tx.cashSession.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
  }

  private saleLookupPayload(input: SyncMaterializerInput) {
    return {
      entityLocalId: input.event.entityLocalId,
      entityServerId: input.event.entityServerId,
      saleId: firstString(input.payload, ['saleId', 'saleServerId']),
      saleUuid: firstIdentity(input.payload, ['saleUuid', 'saleLocalId']),
    };
  }

  private paymentType(input: SyncMaterializerInput) {
    const value = firstString(input.payload, ['paymentType', 'saleType']);
    return value === 'fiado' ? 'fiado' : 'vista';
  }

  private paymentMethod(input: SyncMaterializerInput) {
    return (
      firstString(input.payload, ['paymentMethod']) ??
      (this.paymentType(input) === 'fiado' ? 'fiado' : 'dinheiro')
    );
  }

  private saleStatus(input: SyncMaterializerInput) {
    const status = firstString(input.payload, ['status', 'state']);
    return status === 'canceled' || status === 'cancelada' ? 'canceled' : 'active';
  }

  private async convertExistingSaleOrder(
    input: SyncMaterializerInput,
    saleId: string,
  ): Promise<SyncMaterializerResult | null> {
    const operationalOrder = await this.operationalOrderMaterializer.findOrder(
      input,
    );
    if (operationalOrder == null) {
      return null;
    }

    const conflict = this.orderConversionConflict(operationalOrder, saleId);
    if (conflict != null) {
      return conflict;
    }

    if (operationalOrder.convertedSaleId === saleId) {
      return null;
    }

    const converted = await input.tx.operationalOrder.update({
      where: { id: operationalOrder.id },
      data: {
        status: 'converted',
        closedAt: operationalOrder.closedAt ?? new Date(),
        convertedSaleId: saleId,
      },
    });

    return {
      outcome: 'accepted',
      entityServerId: saleId,
      materializedAt: converted.updatedAt,
    };
  }

  private orderConversionConflict(
    order: {
      id: string;
      localUuid: string;
      status: string;
      cancelledAt: Date | null;
      convertedSaleId: string | null;
    },
    saleId?: string,
  ): SyncMaterializerResult | null {
    if (
      order.cancelledAt != null ||
      ['canceled', 'cancelled'].includes(order.status)
    ) {
      return this.orderImmutableConflict(
        order,
        'Pedido operacional cancelado nao pode virar venda.',
      );
    }

    if (
      order.status === 'converted' &&
      (saleId == null || order.convertedSaleId !== saleId)
    ) {
      return this.orderImmutableConflict(
        order,
        'Pedido operacional convertido nao pode ser alterado.',
      );
    }

    if (order.convertedSaleId != null && order.convertedSaleId !== saleId) {
      return this.orderImmutableConflict(
        order,
        'Pedido operacional ja foi convertido em outra venda.',
      );
    }

    return null;
  }

  private orderImmutableConflict(
    order: {
      id: string;
      localUuid: string;
      status: string;
      convertedSaleId: string | null;
    },
    message: string,
  ): SyncMaterializerResult {
    return {
      outcome: 'conflict',
      code: 'OPERATIONAL_ORDER_IMMUTABLE',
      message,
      payload: {
        operationalOrderId: order.id,
        operationalOrderLocalId: order.localUuid,
        status: order.status,
        convertedSaleId: order.convertedSaleId,
      },
    };
  }
}
