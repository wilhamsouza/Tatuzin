import {
  absPositiveInt,
  domainIdentityFor,
  firstDate,
  firstIdentity,
  firstString,
  firstUuid,
  invalidRemoteIdentity,
  jsonPayload,
  positiveInt,
} from "./payload-utils";
import { SaleMaterializer } from "./sale.materializer";
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from "./materializer.types";

type StockTarget =
  | {
      type: "variant";
      productId: string;
      productVariantId: string;
      stockMil: number;
    }
  | {
      type: "product";
      productId: string;
      productVariantId: null;
      stockMil: number;
    };

type DeductionTargetResolution =
  | {
      ok: true;
      target: StockTarget;
    }
  | {
      ok: false;
      result: SyncMaterializerResult;
    };

export class StockMaterializer {
  constructor(private readonly saleMaterializer = new SaleMaterializer()) {}

  async materializeReservation(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        "reservationLocalId",
        "reservationUuid",
        "stockReservationLocalId",
        "uuid",
        "localUuid",
        "localId",
        "id",
      ],
      { preferIdempotencyKey: true },
    );
    if (localUuid == null) {
      return {
        outcome: "rejected",
        code: "LOCAL_ID_REQUIRED",
        message: "stockReservation precisa de entityLocalId, uuid ou localId.",
      };
    }

    const existing = await input.tx.stockReservation.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    if (existing != null) {
      if (
        input.event.operation === "update" ||
        input.event.operation === "upsert"
      ) {
        const updated = await input.tx.stockReservation.update({
          where: { id: existing.id },
          data: {
            status: firstString(input.payload, ["status"]) ?? existing.status,
            payload: jsonPayload(input.payload),
          },
        });
        return {
          outcome: "accepted",
          entityServerId: updated.id,
          materializedAt: updated.updatedAt,
        };
      }
      return { outcome: "duplicate", entityServerId: existing.id };
    }

    if (!["create", "append", "upsert"].includes(input.event.operation)) {
      return {
        outcome: "rejected",
        code: "INVALID_OPERATION",
        message:
          "stockReservation aceita create, append ou upsert nesta etapa.",
      };
    }

    const quantityMil = positiveInt(input.payload, ["quantityMil", "quantity"]);
    if (quantityMil == null) {
      return {
        outcome: "rejected",
        code: "INVALID_QUANTITY",
        message: "stockReservation precisa de quantityMil positivo.",
      };
    }

    const invalidRemote = this.invalidStockRemoteIdentity(input);
    if (invalidRemote != null) {
      return invalidRemote;
    }

    const target = await this.resolveStockTarget(input);
    if (target == null) {
      return this.variantNotFound(input);
    }

    if (target.stockMil < quantityMil) {
      return this.stockUnavailable(quantityMil, target.stockMil);
    }

    const sale = await this.saleMaterializer.findSale(input);
    const created = await input.tx.stockReservation.create({
      data: {
        companyId: input.context.company.id,
        saleId: sale?.id,
        productId: target.productId,
        productVariantId: target.productVariantId,
        localUuid,
        quantityMil,
        status: firstString(input.payload, ["status"]) ?? "active",
        payload: jsonPayload(input.payload),
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

  async materializeDeduction(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!["create", "append", "upsert"].includes(input.event.operation)) {
      return {
        outcome: "rejected",
        code: "INVALID_OPERATION",
        message: "stockDeduction aceita create, append ou upsert nesta etapa.",
      };
    }

    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        "deductionLocalId",
        "deductionUuid",
        "stockDeductionLocalId",
        "uuid",
        "localUuid",
        "localId",
        "id",
      ],
      { preferIdempotencyKey: true },
    );
    if (localUuid == null) {
      return {
        outcome: "rejected",
        code: "LOCAL_ID_REQUIRED",
        message: "stockDeduction precisa de entityLocalId, uuid ou localId.",
      };
    }

    const existing = await input.tx.stockDeduction.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    if (existing != null) {
      return { outcome: "duplicate", entityServerId: existing.id };
    }

    const quantityMil = absPositiveInt(input.payload, [
      "quantityMil",
      "quantityDeltaMil",
      "quantity",
    ]);
    if (quantityMil == null) {
      return {
        outcome: "rejected",
        code: "INVALID_QUANTITY",
        message: "stockDeduction precisa de quantidade diferente de zero.",
      };
    }

    const remoteIdentityIssue = this.stockDeductionRemoteIdentityIssue(input);
    if (remoteIdentityIssue != null) {
      return remoteIdentityIssue;
    }

    const targetResolution = await this.resolveDeductionStockTarget(input);
    if (!targetResolution.ok) {
      return targetResolution.result;
    }
    const target = targetResolution.target;

    if (target.stockMil < quantityMil) {
      return this.stockUnavailable(quantityMil, target.stockMil);
    }

    const sale = await this.saleMaterializer.findSale(input);
    const created = await input.tx.stockDeduction.create({
      data: {
        companyId: input.context.company.id,
        saleId: sale?.id,
        productId: target.productId,
        productVariantId: target.productVariantId,
        localUuid,
        quantityMil,
        payload: jsonPayload(input.payload),
        createdAt: firstDate(
          input.payload,
          ["createdAt", "occurredAt"],
          new Date(),
        ),
      },
    });

    if (target.type === "variant") {
      await input.tx.productVariant.update({
        where: { id: target.productVariantId },
        data: { stockMil: { decrement: quantityMil } },
      });
    } else {
      await input.tx.product.update({
        where: { id: target.productId },
        data: { stockMil: { decrement: quantityMil } },
      });
    }

    return {
      outcome: "accepted",
      entityServerId: created.id,
      materializedAt: created.updatedAt,
    };
  }

  private async resolveStockTarget(
    input: SyncMaterializerInput,
  ): Promise<StockTarget | null> {
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
        include: { product: { select: { id: true } } },
      });
      if (variant == null) {
        return null;
      }
      return {
        type: "variant",
        productId: variant.product.id,
        productVariantId: variant.id,
        stockMil: variant.stockMil,
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
      select: {
        id: true,
        stockMil: true,
      },
    });
    if (product == null) {
      return null;
    }
    return {
      type: "product",
      productId: product.id,
      productVariantId: null,
      stockMil: product.stockMil,
    };
  }

  private async resolveDeductionStockTarget(
    input: SyncMaterializerInput,
  ): Promise<DeductionTargetResolution> {
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
        include: { product: { select: { id: true } } },
      });
      if (variant == null) {
        return { ok: false, result: this.variantNotFound(input) };
      }
      return {
        ok: true,
        target: {
          type: "variant",
          productId: variant.product.id,
          productVariantId: variant.id,
          stockMil: variant.stockMil,
        },
      };
    }

    const productId = firstUuid(input.payload, [
      "productId",
      "productServerId",
    ]);
    if (productId == null) {
      return {
        ok: false,
        result: this.stockDeductionRemoteIdRequired(input),
      };
    }

    const product = await input.tx.product.findFirst({
      where: {
        id: productId,
        companyId: input.context.company.id,
        deletedAt: null,
      },
      select: {
        id: true,
        stockMil: true,
      },
    });
    if (product == null) {
      return { ok: false, result: this.productNotFound(input) };
    }

    const activeVariantsCount = await input.tx.productVariant.count({
      where: {
        productId: product.id,
        isActive: true,
      },
    });
    if (activeVariantsCount > 0) {
      return {
        ok: false,
        result: this.stockDeductionRemoteIdRequired(input, {
          reason: "PRODUCT_VARIANT_REMOTE_ID_REQUIRED",
        }),
      };
    }

    return {
      ok: true,
      target: {
        type: "product",
        productId: product.id,
        productVariantId: null,
        stockMil: product.stockMil,
      },
    };
  }

  private variantNotFound(
    input: SyncMaterializerInput,
  ): SyncMaterializerResult {
    return {
      outcome: "conflict",
      code: "STOCK_VARIANT_NOT_FOUND",
      message:
        "Produto/variante remoto nao encontrado para estoque operacional.",
      payload: {
        entity: input.event.entity,
        operation: input.event.operation,
        entityLocalId: input.event.entityLocalId,
        productId: firstString(input.payload, ["productId", "productServerId"]),
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

  private productNotFound(
    input: SyncMaterializerInput,
  ): SyncMaterializerResult {
    return {
      outcome: "conflict",
      code: "STOCK_PRODUCT_NOT_FOUND",
      message: "Produto remoto nao encontrado para estoque operacional.",
      payload: {
        entity: input.event.entity,
        operation: input.event.operation,
        entityLocalId: input.event.entityLocalId,
        productId: firstString(input.payload, ["productId", "productServerId"]),
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

  private stockDeductionRemoteIdentityIssue(
    input: SyncMaterializerInput,
  ): SyncMaterializerResult | null {
    const invalid = invalidRemoteIdentity(input.payload, [
      "productId",
      "productServerId",
      "productVariantId",
      "productVariantServerId",
      "variantId",
    ]);
    if (invalid != null) {
      return this.stockDeductionRemoteIdRequired(input, {
        field: invalid.field,
        value: invalid.value,
      });
    }

    const hasProductRemote =
      firstUuid(input.payload, ["productId", "productServerId"]) != null;
    const hasVariantRemote =
      firstUuid(input.payload, [
        "productVariantId",
        "productVariantServerId",
        "variantId",
      ]) != null;
    if (!hasProductRemote && !hasVariantRemote) {
      return this.stockDeductionRemoteIdRequired(input);
    }

    return null;
  }

  private stockDeductionRemoteIdRequired(
    input: SyncMaterializerInput,
    extra: Record<string, string> = {},
  ): SyncMaterializerResult {
    return {
      outcome: "conflict",
      code: "STOCK_DEDUCTION_REMOTE_ID_REQUIRED",
      message: "Produto sem identificacao remota para baixa de estoque.",
      payload: {
        entity: input.event.entity,
        operation: input.event.operation,
        entityLocalId: input.event.entityLocalId,
        productId: firstIdentity(input.payload, ["productId", "productServerId"]),
        productVariantId: firstIdentity(input.payload, [
          "productVariantId",
          "productVariantServerId",
          "variantId",
        ]),
        productLocalId: firstIdentity(input.payload, ["productLocalId"]),
        productVariantLocalId: firstIdentity(input.payload, [
          "productVariantLocalId",
        ]),
        ...extra,
      },
    };
  }

  private invalidStockRemoteIdentity(
    input: SyncMaterializerInput,
  ): SyncMaterializerResult | null {
    const invalid = invalidRemoteIdentity(input.payload, [
      "productId",
      "productServerId",
      "productVariantId",
      "productVariantServerId",
      "variantId",
    ]);
    if (invalid == null) {
      return null;
    }

    return {
      outcome: "rejected",
      code: "INVALID_REMOTE_ID",
      message:
        `${invalid.field} precisa ser um UUID remoto valido; ` +
        "IDs locais devem ser enviados apenas em productLocalId/productVariantLocalId.",
      details: {
        entity: input.event.entity,
        operation: input.event.operation,
        entityLocalId: input.event.entityLocalId,
        field: invalid.field,
        value: invalid.value,
        productLocalId: firstIdentity(input.payload, ["productLocalId"]),
        productVariantLocalId: firstIdentity(input.payload, [
          "productVariantLocalId",
        ]),
      },
    };
  }

  private stockUnavailable(
    requestedQuantityMil: number,
    availableStockMil: number,
  ): SyncMaterializerResult {
    return {
      outcome: "conflict",
      code: "STOCK_UNAVAILABLE",
      message: "Estoque insuficiente para operacao offline.",
      payload: {
        requestedQuantityMil,
        availableStockMil,
      },
    };
  }
}
