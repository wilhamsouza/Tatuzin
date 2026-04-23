import { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type {
  SupplyListQueryInput,
  SupplyCostHistoryInput,
  SupplyUpsertInput,
} from './supplies.schemas';

const supplyInclude = {
  defaultSupplier: {
    select: {
      id: true,
      localUuid: true,
      name: true,
    },
  },
  costHistory: {
    orderBy: [{ occurredAt: 'desc' }, { createdAt: 'desc' }],
    include: {
      purchaseItem: {
        select: {
          id: true,
          localUuid: true,
        },
      },
    },
  },
} satisfies Prisma.SupplyInclude;

type SupplyWithRelations = Prisma.SupplyGetPayload<{
  include: typeof supplyInclude;
}>;

export class SuppliesService {
  async listForCompany(companyId: string, query: SupplyListQueryInput) {
    const where = {
      companyId,
      ...(query.includeDeleted ? {} : { deletedAt: null }),
    };
    const { skip, take } = toPaginationParams({
      page: query.page,
      pageSize: query.pageSize,
    });

    const [total, supplies] = await prisma.$transaction([
      prisma.supply.count({ where }),
      prisma.supply.findMany({
        where,
        include: supplyInclude,
        skip,
        take,
        orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
      }),
    ]);

    return {
      items: supplies.map((supply) => this.toSupplyDto(supply)),
      total,
    };
  }

  async getById(companyId: string, supplyId: string) {
    const supply = await prisma.supply.findFirst({
      where: {
        id: supplyId,
        companyId,
      },
      include: supplyInclude,
    });

    if (!supply) {
      throw new AppError('Insumo nao encontrado.', 404, 'SUPPLY_NOT_FOUND');
    }

    return this.toSupplyDto(supply);
  }

  async create(companyId: string, input: SupplyUpsertInput) {
    return prisma.$transaction(async (tx) => {
      const defaultSupplierId = await this.resolveDefaultSupplierId(
        tx,
        companyId,
        input.defaultSupplierId,
      );
      const existing = await tx.supply.findUnique({
        where: {
          companyId_localUuid: {
            companyId,
            localUuid: input.localUuid,
          },
        },
        select: { id: true },
      });

      const supply = existing
        ? await tx.supply.update({
            where: { id: existing.id },
            data: this.toCreateOrUpdateData(companyId, input, defaultSupplierId),
          })
        : await tx.supply.create({
            data: this.toCreateOrUpdateData(companyId, input, defaultSupplierId),
          });

      await this.replaceCostHistory(tx, companyId, supply.id, input.costHistory);

      const persisted = await tx.supply.findUnique({
        where: { id: supply.id },
        include: supplyInclude,
      });

      if (!persisted) {
        throw new AppError(
          'Insumo nao encontrado apos persistencia.',
          500,
          'SUPPLY_CREATE_INCONSISTENT',
        );
      }

      return this.toSupplyDto(persisted);
    });
  }

  async update(companyId: string, supplyId: string, input: SupplyUpsertInput) {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.supply.findFirst({
        where: {
          id: supplyId,
          companyId,
        },
        select: { id: true },
      });

      if (!existing) {
        throw new AppError('Insumo nao encontrado.', 404, 'SUPPLY_NOT_FOUND');
      }

      const defaultSupplierId = await this.resolveDefaultSupplierId(
        tx,
        companyId,
        input.defaultSupplierId,
      );

      const supply = await tx.supply.update({
        where: { id: supplyId },
        data: this.toCreateOrUpdateData(companyId, input, defaultSupplierId),
      });

      await this.replaceCostHistory(tx, companyId, supply.id, input.costHistory);

      const persisted = await tx.supply.findUnique({
        where: { id: supply.id },
        include: supplyInclude,
      });

      if (!persisted) {
        throw new AppError(
          'Insumo nao encontrado apos atualizacao.',
          500,
          'SUPPLY_UPDATE_INCONSISTENT',
        );
      }

      return this.toSupplyDto(persisted);
    });
  }

  async softDelete(companyId: string, supplyId: string) {
    const existing = await prisma.supply.findFirst({
      where: {
        id: supplyId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Insumo nao encontrado.', 404, 'SUPPLY_NOT_FOUND');
    }

    const supply = await prisma.supply.update({
      where: { id: supplyId },
      data: {
        isActive: false,
        deletedAt: new Date(),
      },
      include: supplyInclude,
    });

    return this.toSupplyDto(supply);
  }

  private async resolveDefaultSupplierId(
    tx: Prisma.TransactionClient,
    companyId: string,
    defaultSupplierId: string | null,
  ) {
    if (defaultSupplierId == null) {
      return null;
    }

    const supplier = await tx.supplier.findFirst({
      where: {
        id: defaultSupplierId,
        companyId,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!supplier) {
      throw new AppError(
        'Fornecedor remoto invalido para este insumo.',
        400,
        'SUPPLY_DEFAULT_SUPPLIER_INVALID',
      );
    }

    return supplier.id;
  }

  private async replaceCostHistory(
    tx: Prisma.TransactionClient,
    companyId: string,
    supplyId: string,
    entries: SupplyCostHistoryInput[],
  ) {
    await tx.supplyCostHistory.deleteMany({
      where: {
        companyId,
        supplyId,
      },
    });

    for (const entry of entries) {
      const references = await this.resolveOptionalPurchaseReferences(
        tx,
        companyId,
        entry.purchaseId,
        entry.purchaseItemLocalUuid,
      );

      await tx.supplyCostHistory.create({
        data: {
          companyId,
          localUuid: entry.localUuid,
          supplyId,
          purchaseId: references.purchaseId,
          purchaseItemId: references.purchaseItemId,
          source: entry.source,
          eventType: entry.eventType,
          purchaseUnitType: entry.purchaseUnitType,
          conversionFactor: entry.conversionFactor,
          lastPurchasePriceCents: entry.lastPurchasePriceCents,
          averagePurchasePriceCents: entry.averagePurchasePriceCents,
          changeSummary: entry.changeSummary,
          notes: entry.notes,
          occurredAt: new Date(entry.occurredAt),
        },
      });
    }
  }

  private async resolveOptionalPurchaseReferences(
    tx: Prisma.TransactionClient,
    companyId: string,
    purchaseId: string | null,
    purchaseItemLocalUuid: string | null,
  ) {
    if (purchaseId == null || purchaseId.trim().length === 0) {
      return {
        purchaseId: null,
        purchaseItemId: null,
      };
    }

    const purchase = await tx.purchase.findFirst({
      where: {
        id: purchaseId,
        companyId,
      },
      select: { id: true },
    });

    if (!purchase) {
      return {
        purchaseId: null,
        purchaseItemId: null,
      };
    }

    let purchaseItemId: string | null = null;
    if (
      purchaseItemLocalUuid != null &&
      purchaseItemLocalUuid.trim().length > 0
    ) {
      const purchaseItem = await tx.purchaseItem.findFirst({
        where: {
          purchaseId: purchase.id,
          localUuid: purchaseItemLocalUuid.trim(),
        },
        select: { id: true },
      });
      purchaseItemId = purchaseItem?.id ?? null;
    }

    return {
      purchaseId: purchase.id,
      purchaseItemId,
    };
  }

  private toCreateOrUpdateData(
    companyId: string,
    input: SupplyUpsertInput,
    defaultSupplierId: string | null,
  ): Prisma.SupplyUncheckedCreateInput {
    return {
      companyId,
      localUuid: input.localUuid,
      defaultSupplierId,
      name: input.name.trim(),
      sku: input.sku,
      unitType: input.unitType,
      purchaseUnitType: input.purchaseUnitType,
      conversionFactor: input.conversionFactor,
      lastPurchasePriceCents: input.lastPurchasePriceCents,
      averagePurchasePriceCents: input.averagePurchasePriceCents,
      currentStockMil: input.currentStockMil,
      minimumStockMil: input.minimumStockMil,
      isActive: input.deletedAt == null ? input.isActive : false,
      deletedAt: input.deletedAt,
    };
  }

  private toSupplyDto(supply: SupplyWithRelations) {
    return {
      id: supply.id,
      companyId: supply.companyId,
      localUuid: supply.localUuid,
      defaultSupplierId: supply.defaultSupplierId,
      defaultSupplierLocalUuid: supply.defaultSupplier?.localUuid ?? null,
      defaultSupplierName: supply.defaultSupplier?.name ?? null,
      name: supply.name,
      sku: supply.sku,
      unitType: supply.unitType,
      purchaseUnitType: supply.purchaseUnitType,
      conversionFactor: supply.conversionFactor,
      lastPurchasePriceCents: supply.lastPurchasePriceCents,
      averagePurchasePriceCents: supply.averagePurchasePriceCents,
      currentStockMil: supply.currentStockMil,
      minimumStockMil: supply.minimumStockMil,
      isActive: supply.isActive,
      deletedAt: supply.deletedAt?.toISOString() ?? null,
      createdAt: supply.createdAt.toISOString(),
      updatedAt: supply.updatedAt.toISOString(),
      costHistory: supply.costHistory.map((entry) => ({
        id: entry.id,
        localUuid: entry.localUuid,
        supplyId: entry.supplyId,
        purchaseId: entry.purchaseId,
        purchaseItemId: entry.purchaseItemId,
        purchaseItemLocalUuid: entry.purchaseItem?.localUuid ?? null,
        source: entry.source,
        eventType: entry.eventType,
        purchaseUnitType: entry.purchaseUnitType,
        conversionFactor: entry.conversionFactor,
        lastPurchasePriceCents: entry.lastPurchasePriceCents,
        averagePurchasePriceCents: entry.averagePurchasePriceCents,
        changeSummary: entry.changeSummary,
        notes: entry.notes,
        occurredAt: entry.occurredAt.toISOString(),
        createdAt: entry.createdAt.toISOString(),
      })),
    };
  }
}
