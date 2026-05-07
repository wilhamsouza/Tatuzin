import {
  domainIdentityFor,
  firstDate,
  firstIdentity,
  firstString,
  firstUuid,
  invalidRemoteIdentity,
  isUuid,
  localSequenceFor,
  localIdentityFor,
  nonNegativeInt,
  positiveInt,
} from "./payload-utils";
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from "./materializer.types";

type OperationalOrderLike = {
  id: string;
  companyId: string;
  localUuid: string;
  cashSessionId: string | null;
  customerId: string | null;
  sellerUserId: string | null;
  deviceId: string | null;
  status: string;
  subtotalCents: number;
  discountCents: number;
  totalCents: number;
  notes: string | null;
  closedAt: Date | null;
  cancelledAt: Date | null;
  convertedSaleId: string | null;
  lastLocalSequence: number | null;
  updatedAt: Date;
};

type ProductTarget =
  | {
      productId: string;
      productVariantId: string | null;
    }
  | {
      productId: null;
      productVariantId: null;
    };

export class OperationalOrderMaterializer {
  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (input.event.entity === "operationalOrder") {
      return this.materializeOrder(input);
    }

    if (input.event.entity === "operationalOrderItem") {
      return this.materializeItem(input);
    }

    return {
      outcome: "accepted",
      entityServerId: null,
      materializedAt: null,
    };
  }

  async findOrder(input: SyncMaterializerInput) {
    const orderId =
      (isUuid(input.event.entityServerId)
        ? input.event.entityServerId
        : null) ??
      firstUuid(input.payload, [
        "operationalOrderId",
        "operationalOrderServerId",
        "orderServerId",
      ]);
    if (orderId != null) {
      const order = await input.tx.operationalOrder.findFirst({
        where: {
          id: orderId,
          companyId: input.context.company.id,
        },
      });
      if (order != null) {
        return order;
      }
    }

    const localUuid =
      this.orderLocalIdentity(input) ??
      (input.event.entity === "operationalOrder"
        ? localIdentityFor(input.event, input.payload)
        : null);
    if (localUuid == null) {
      return null;
    }

    return input.tx.operationalOrder.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
  }

  async convertToSale(
    input: SyncMaterializerInput,
    saleId: string,
  ): Promise<SyncMaterializerResult | null> {
    const order = await this.findOrder(input);
    if (order == null) {
      return null;
    }

    if (this.isCanceled(order)) {
      return this.immutable(
        order,
        "Pedido operacional cancelado nao pode virar venda.",
      );
    }

    if (order.convertedSaleId != null && order.convertedSaleId !== saleId) {
      return this.immutable(
        order,
        "Pedido operacional ja foi convertido em outra venda.",
      );
    }

    if (order.convertedSaleId === saleId) {
      return null;
    }

    await input.tx.operationalOrder.update({
      where: { id: order.id },
      data: {
        status: "converted",
        closedAt: order.closedAt ?? new Date(),
        convertedSaleId: saleId,
      },
    });

    return null;
  }

  private async materializeOrder(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!["create", "update", "upsert"].includes(input.event.operation)) {
      return {
        outcome: "rejected",
        code: "INVALID_OPERATION",
        message: "operationalOrder aceita create, update ou upsert.",
      };
    }

    const localUuid = domainIdentityFor(input.event, input.payload, [
      "operationalOrderLocalId",
      "operationalOrderLocalUuid",
      "orderLocalId",
      "orderUuid",
      "uuid",
      "localUuid",
      "localId",
      "id",
    ]);
    if (localUuid == null) {
      return {
        outcome: "rejected",
        code: "LOCAL_ID_REQUIRED",
        message: "operationalOrder precisa de entityLocalId, uuid ou localId.",
      };
    }

    const existing = await input.tx.operationalOrder.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    const localSequence = localSequenceFor(input.event, input.payload);

    if (input.event.operation === "create" && existing != null) {
      return {
        outcome: "duplicate",
        entityServerId: existing.id,
      };
    }

    if (input.event.operation === "update" && existing == null) {
      return {
        outcome: "conflict",
        code: "OPERATIONAL_ORDER_NOT_FOUND",
        message: "Pedido operacional nao encontrado para atualizacao.",
        payload: {
          entityLocalId: input.event.entityLocalId,
          localUuid,
        },
      };
    }

    if (
      existing != null &&
      ["update", "upsert"].includes(input.event.operation) &&
      localSequence != null &&
      existing.lastLocalSequence != null &&
      existing.lastLocalSequence > localSequence
    ) {
      return {
        outcome: "conflict",
        code: "STALE_LOCAL_SEQUENCE",
        message:
          "Evento operacional possui localSequence anterior ao ultimo evento materializado para a entidade.",
        payload: {
          entity: input.event.entity,
          entityLocalId: input.event.entityLocalId,
          localUuid,
          localSequence,
          latestLocalSequence: existing.lastLocalSequence,
        },
      };
    }

    if (existing != null) {
      const immutable = this.immutableIfNeeded(input, existing);
      if (immutable != null) {
        return immutable;
      }
    }

    const cashSession = await this.findCashSession(input);
    const customerId = await this.resolveCustomerId(input);
    const requestedStatus = this.orderStatus(input, existing);
    const now = new Date();
    const baseData = {
      cashSessionId: cashSession?.id ?? existing?.cashSessionId,
      customerId: customerId ?? existing?.customerId,
      sellerUserId: existing?.sellerUserId ?? input.context.user.id,
      deviceId: existing?.deviceId ?? input.context.device.id,
      status: requestedStatus,
      subtotalCents:
        nonNegativeInt(input.payload, ["subtotalCents"]) ??
        existing?.subtotalCents ??
        0,
      discountCents:
        nonNegativeInt(input.payload, ["discountCents"]) ??
        existing?.discountCents ??
        0,
      totalCents:
        nonNegativeInt(input.payload, ["totalCents", "finalCents"]) ??
        existing?.totalCents ??
        0,
      notes:
        firstString(input.payload, ["notes", "description"]) ?? existing?.notes,
      closedAt: this.closedAt(input, existing, requestedStatus, now),
      cancelledAt: this.cancelledAt(input, existing, requestedStatus, now),
      lastLocalSequence: localSequence ?? existing?.lastLocalSequence ?? null,
    };

    if (existing == null) {
      const created = await input.tx.operationalOrder.create({
        data: {
          companyId: input.context.company.id,
          localUuid,
          ...baseData,
          createdAt: firstDate(input.payload, ["createdAt", "openedAt"], now),
        },
      });

      return {
        outcome: "accepted",
        entityServerId: created.id,
        materializedAt: created.updatedAt,
      };
    }

    const updated = await input.tx.operationalOrder.update({
      where: { id: existing.id },
      data: baseData,
    });

    return {
      outcome: "accepted",
      entityServerId: updated.id,
      materializedAt: updated.updatedAt,
    };
  }

  private async materializeItem(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (
      !["create", "append", "update", "upsert"].includes(input.event.operation)
    ) {
      return {
        outcome: "rejected",
        code: "INVALID_OPERATION",
        message:
          "operationalOrderItem aceita create, append, update ou upsert.",
      };
    }

    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        "operationalOrderItemLocalId",
        "operationalOrderItemLocalUuid",
        "itemLocalId",
        "itemUuid",
        "uuid",
        "localUuid",
        "localId",
        "id",
      ],
      {
        preferIdempotencyKey: ["create", "append"].includes(
          input.event.operation,
        ),
      },
    );
    if (localUuid == null) {
      return {
        outcome: "rejected",
        code: "LOCAL_ID_REQUIRED",
        message:
          "operationalOrderItem precisa de entityLocalId, uuid ou localId.",
      };
    }

    const existing = await input.tx.operationalOrderItem.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
      include: {
        operationalOrder: true,
      },
    });

    if (
      existing != null &&
      ["create", "append"].includes(input.event.operation)
    ) {
      return {
        outcome: "duplicate",
        entityServerId: existing.id,
      };
    }

    const order = existing?.operationalOrder ?? (await this.findOrder(input));
    if (order == null) {
      return {
        outcome: "conflict",
        code: "OPERATIONAL_ORDER_NOT_FOUND",
        message: "Pedido operacional nao encontrado para materializar item.",
        payload: this.orderLookupPayload(input),
      };
    }

    if (this.isImmutable(order)) {
      return this.immutable(
        order,
        "Item nao pode alterar pedido operacional convertido ou cancelado.",
      );
    }

    if (input.event.operation === "update" && existing == null) {
      return {
        outcome: "conflict",
        code: "OPERATIONAL_ORDER_ITEM_NOT_FOUND",
        message: "Item de pedido operacional nao encontrado para atualizacao.",
        payload: {
          entityLocalId: input.event.entityLocalId,
          localUuid,
        },
      };
    }

    const quantityMil =
      positiveInt(input.payload, ["quantityMil", "quantity"]) ??
      existing?.quantityMil;
    if (quantityMil == null || quantityMil <= 0) {
      return {
        outcome: "rejected",
        code: "INVALID_QUANTITY",
        message: "operationalOrderItem precisa de quantityMil positivo.",
      };
    }

    const totalCents =
      nonNegativeInt(input.payload, ["totalCents", "totalPriceCents"]) ??
      existing?.totalCents;
    if (totalCents == null || totalCents < 0) {
      return {
        outcome: "rejected",
        code: "INVALID_TOTAL",
        message:
          "operationalOrderItem precisa de totalCents maior ou igual a zero.",
      };
    }

    const target = await this.resolveProductTarget(input);
    const invalidRemote = invalidRemoteIdentity(input.payload, [
      "productId",
      "productServerId",
      "productVariantId",
      "productVariantServerId",
      "variantId",
    ]);
    if (invalidRemote != null) {
      return {
        outcome: "rejected",
        code: "INVALID_REMOTE_ID",
        message:
          `${invalidRemote.field} precisa ser um UUID remoto valido; ` +
          "IDs locais devem ser enviados apenas em productLocalId/productVariantLocalId.",
        details: {
          entity: input.event.entity,
          operation: input.event.operation,
          entityLocalId: input.event.entityLocalId,
          field: invalidRemote.field,
          value: invalidRemote.value,
          productLocalId: firstIdentity(input.payload, ["productLocalId"]),
          productVariantLocalId: firstIdentity(input.payload, [
            "productVariantLocalId",
          ]),
        },
      };
    }
    if (target === "missingVariant") {
      return {
        outcome: "conflict",
        code: "STOCK_VARIANT_NOT_FOUND",
        message: "Variante remota nao encontrada para item operacional.",
        payload: {
          entity: input.event.entity,
          operation: input.event.operation,
          entityLocalId: input.event.entityLocalId,
          productVariantId: firstString(input.payload, [
            "productVariantId",
            "productVariantServerId",
            "variantId",
          ]),
          productLocalId: firstIdentity(input.payload, ["productLocalId"]),
          productVariantLocalId: firstIdentity(input.payload, [
            "productVariantLocalId",
          ]),
        },
      };
    }

    const productTarget = target ?? {
      productId: existing?.productId ?? null,
      productVariantId: existing?.productVariantId ?? null,
    };
    const data = {
      productId: productTarget.productId,
      productVariantId: productTarget.productVariantId,
      description:
        firstString(input.payload, ["description", "productName", "name"]) ??
        existing?.description ??
        "Item operacional",
      quantityMil,
      unitPriceCents:
        nonNegativeInt(input.payload, ["unitPriceCents", "priceCents"]) ??
        existing?.unitPriceCents ??
        0,
      totalCents,
    };

    if (existing == null) {
      const created = await input.tx.operationalOrderItem.create({
        data: {
          companyId: input.context.company.id,
          operationalOrderId: order.id,
          localUuid,
          ...data,
          createdAt: firstDate(
            input.payload,
            ["createdAt", "occurredAt"],
            new Date(),
          ),
        },
      });

      return {
        outcome: "accepted",
        entityServerId: created.id,
        materializedAt: created.updatedAt,
      };
    }

    const updated = await input.tx.operationalOrderItem.update({
      where: { id: existing.id },
      data,
    });

    return {
      outcome: "accepted",
      entityServerId: updated.id,
      materializedAt: updated.updatedAt,
    };
  }

  private immutableIfNeeded(
    input: SyncMaterializerInput,
    order: OperationalOrderLike,
  ): SyncMaterializerResult | null {
    if (order.convertedSaleId != null || this.isConvertedStatus(order.status)) {
      return this.immutable(
        order,
        "Pedido operacional convertido nao pode ser alterado.",
      );
    }

    const requestedStatus = this.orderStatus(input, order);
    if (this.isCanceled(order) && this.isOpenStatus(requestedStatus)) {
      return this.immutable(
        order,
        "Pedido operacional cancelado nao pode ser reaberto.",
      );
    }

    return null;
  }

  private async findCashSession(input: SyncMaterializerInput) {
    const cashSessionId = firstUuid(input.payload, [
      "cashSessionId",
      "cashSessionServerId",
    ]);
    if (cashSessionId != null) {
      return input.tx.cashSession.findFirst({
        where: {
          id: cashSessionId,
          companyId: input.context.company.id,
        },
      });
    }

    const localUuid = firstIdentity(input.payload, [
      "cashSessionUuid",
      "cashSessionLocalId",
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

  private async resolveCustomerId(input: SyncMaterializerInput) {
    const customerId = firstUuid(input.payload, [
      "customerId",
      "customerServerId",
    ]);
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

  private async resolveProductTarget(
    input: SyncMaterializerInput,
  ): Promise<ProductTarget | "missingVariant" | null> {
    const variantId = firstUuid(input.payload, [
      "productVariantId",
      "productVariantServerId",
      "variantId",
    ]);
    if (variantId != null) {
      const variant = await input.tx.productVariant.findFirst({
        where: {
          id: variantId,
          product: {
            companyId: input.context.company.id,
            deletedAt: null,
          },
        },
        include: {
          product: {
            select: {
              id: true,
            },
          },
        },
      });
      if (variant == null) {
        return "missingVariant";
      }
      return {
        productId: variant.product.id,
        productVariantId: variant.id,
      };
    }

    const productId = firstUuid(input.payload, [
      "productId",
      "productServerId",
    ]);
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

    return product == null
      ? null
      : {
          productId: product.id,
          productVariantId: null,
        };
  }

  private orderStatus(
    input: SyncMaterializerInput,
    existing?: OperationalOrderLike | null,
  ) {
    const status = firstString(input.payload, ["status", "state"]);
    if (status == null) {
      return existing?.status ?? "open";
    }

    const normalized = status.trim().toLowerCase();
    if (
      ["cancelled", "canceled", "cancelado", "cancelada"].includes(normalized)
    ) {
      return "canceled";
    }
    if (
      ["closed", "finished", "finalized", "fechado", "fechada"].includes(
        normalized,
      )
    ) {
      return "closed";
    }
    if (["converted", "convertido", "convertida"].includes(normalized)) {
      return "converted";
    }
    if (["open", "opened", "active", "aberto", "aberta"].includes(normalized)) {
      return "open";
    }
    return normalized;
  }

  private closedAt(
    input: SyncMaterializerInput,
    existing: OperationalOrderLike | null,
    status: string,
    fallback: Date,
  ) {
    if (!["closed", "converted"].includes(status)) {
      return existing?.closedAt ?? null;
    }

    return firstDate(
      input.payload,
      ["closedAt", "finalizedAt", "updatedAt"],
      existing?.closedAt ?? fallback,
    );
  }

  private cancelledAt(
    input: SyncMaterializerInput,
    existing: OperationalOrderLike | null,
    status: string,
    fallback: Date,
  ) {
    if (status !== "canceled") {
      return existing?.cancelledAt ?? null;
    }

    return firstDate(
      input.payload,
      ["cancelledAt", "canceledAt", "cancelAt", "updatedAt"],
      existing?.cancelledAt ?? fallback,
    );
  }

  private orderLocalIdentity(input: SyncMaterializerInput) {
    return firstIdentity(input.payload, [
      "operationalOrderLocalId",
      "operationalOrderLocalUuid",
      "orderLocalId",
      "orderUuid",
    ]);
  }

  private orderLookupPayload(input: SyncMaterializerInput) {
    return {
      entityLocalId: input.event.entityLocalId,
      entityServerId: input.event.entityServerId,
      operationalOrderId: firstString(input.payload, [
        "operationalOrderId",
        "operationalOrderServerId",
      ]),
      operationalOrderLocalId: this.orderLocalIdentity(input),
    };
  }

  private immutable(order: OperationalOrderLike, message: string) {
    return {
      outcome: "conflict" as const,
      code: "OPERATIONAL_ORDER_IMMUTABLE",
      message,
      payload: {
        operationalOrderId: order.id,
        operationalOrderLocalId: order.localUuid,
        status: order.status,
        convertedSaleId: order.convertedSaleId,
      },
    };
  }

  private isImmutable(order: OperationalOrderLike) {
    return (
      order.convertedSaleId != null ||
      this.isConvertedStatus(order.status) ||
      this.isCanceled(order)
    );
  }

  private isCanceled(order: OperationalOrderLike) {
    return (
      order.cancelledAt != null ||
      ["canceled", "cancelled"].includes(order.status)
    );
  }

  private isConvertedStatus(status: string) {
    return status === "converted";
  }

  private isOpenStatus(status: string) {
    return status === "open";
  }
}
