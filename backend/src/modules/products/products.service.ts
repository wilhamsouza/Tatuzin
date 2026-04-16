import { Prisma, type Product } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { ProductUpsertInput } from './products.schemas';

const productInclude = {
  variants: {
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  },
  modifierGroups: {
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    include: {
      options: {
        orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
      },
    },
  },
} satisfies Prisma.ProductInclude;

type ProductWithRelations = Prisma.ProductGetPayload<{
  include: typeof productInclude;
}>;

type ProductCollectionsPayload = Pick<
  ProductUpsertInput,
  'modifierGroups' | 'variants'
>;

export class ProductsService {
  async listForCompany(companyId: string, includeDeleted = false) {
    const products = await prisma.product.findMany({
      where: {
        companyId,
        ...(includeDeleted ? {} : { deletedAt: null }),
      },
      include: productInclude,
      orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
    });

    return products.map((product) => this.toProductDto(product));
  }

  async getById(companyId: string, productId: string) {
    const product = await prisma.product.findFirst({
      where: {
        id: productId,
        companyId,
      },
      include: productInclude,
    });

    if (!product) {
      throw new AppError('Produto nao encontrado.', 404, 'PRODUCT_NOT_FOUND');
    }

    return this.toProductDto(product);
  }

  async create(companyId: string, input: ProductUpsertInput) {
    return prisma.$transaction(async (tx) => {
      const categoryId = await this.resolveCategoryId(
        tx,
        companyId,
        input.categoryId,
      );
      const normalizedCollections = this.normalizeCollections(input);

      await this.ensureVariantSkusAvailable(
        tx,
        companyId,
        normalizedCollections.variants,
      );
      await this.ensureLinkedProductsBelongToCompany(
        tx,
        companyId,
        normalizedCollections.modifierGroups,
      );

      const product = await tx.product.upsert({
        where: {
          companyId_localUuid: {
            companyId,
            localUuid: input.localUuid,
          },
        },
        update: this.toCreateOrUpdateData(
          companyId,
          input,
          categoryId,
          normalizedCollections,
        ),
        create: this.toCreateOrUpdateData(
          companyId,
          input,
          categoryId,
          normalizedCollections,
        ),
      });

      await this.replaceProductCollections(
        tx,
        product.id,
        normalizedCollections,
      );

      const persisted = await tx.product.findUnique({
        where: { id: product.id },
        include: productInclude,
      });

      if (!persisted) {
        throw new AppError(
          'Produto nao encontrado apos criacao.',
          500,
          'PRODUCT_CREATE_INCONSISTENT',
        );
      }

      return this.toProductDto(persisted);
    });
  }

  async update(companyId: string, productId: string, input: ProductUpsertInput) {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.product.findFirst({
        where: {
          id: productId,
          companyId,
        },
        select: { id: true },
      });

      if (!existing) {
        throw new AppError('Produto nao encontrado.', 404, 'PRODUCT_NOT_FOUND');
      }

      await this.ensureLocalUuidAvailable(
        tx,
        companyId,
        input.localUuid,
        productId,
      );

      const categoryId = await this.resolveCategoryId(
        tx,
        companyId,
        input.categoryId,
      );
      const normalizedCollections = this.normalizeCollections(input);

      await this.ensureVariantSkusAvailable(
        tx,
        companyId,
        normalizedCollections.variants,
        productId,
      );
      await this.ensureLinkedProductsBelongToCompany(
        tx,
        companyId,
        normalizedCollections.modifierGroups,
      );

      await tx.product.update({
        where: { id: productId },
        data: this.toCreateOrUpdateData(
          companyId,
          input,
          categoryId,
          normalizedCollections,
        ),
      });

      await this.replaceProductCollections(
        tx,
        productId,
        normalizedCollections,
      );

      const persisted = await tx.product.findUnique({
        where: { id: productId },
        include: productInclude,
      });

      if (!persisted) {
        throw new AppError(
          'Produto nao encontrado apos atualizacao.',
          500,
          'PRODUCT_UPDATE_INCONSISTENT',
        );
      }

      return this.toProductDto(persisted);
    });
  }

  async softDelete(companyId: string, productId: string) {
    const existing = await prisma.product.findFirst({
      where: {
        id: productId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Produto nao encontrado.', 404, 'PRODUCT_NOT_FOUND');
    }

    const product = await prisma.product.update({
      where: { id: productId },
      data: {
        isActive: false,
        deletedAt: new Date(),
      },
      include: productInclude,
    });

    return this.toProductDto(product);
  }

  private async resolveCategoryId(
    tx: Prisma.TransactionClient,
    companyId: string,
    categoryId: string | null,
  ) {
    if (categoryId == null) {
      return null;
    }

    const category = await tx.category.findFirst({
      where: {
        id: categoryId,
        companyId,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!category) {
      throw new AppError(
        'Categoria remota invalida para este produto.',
        400,
        'CATEGORY_INVALID',
      );
    }

    return category.id;
  }

  private async ensureLocalUuidAvailable(
    tx: Prisma.TransactionClient,
    companyId: string,
    localUuid: string,
    currentId: string,
  ) {
    const conflicting = await tx.product.findFirst({
      where: {
        companyId,
        localUuid,
        id: { not: currentId },
      },
      select: { id: true },
    });

    if (conflicting) {
      throw new AppError(
        'Ja existe outro produto remoto com este localUuid neste tenant.',
        409,
        'PRODUCT_LOCAL_UUID_CONFLICT',
      );
    }
  }

  private async ensureVariantSkusAvailable(
    tx: Prisma.TransactionClient,
    companyId: string,
    variants: ProductCollectionsPayload['variants'],
    currentProductId?: string,
  ) {
    if (variants.length === 0) {
      return;
    }

    const payloadSkus = new Set<string>();
    for (const variant of variants) {
      const normalizedSku = this.normalizeSku(variant.sku);
      if (payloadSkus.has(normalizedSku)) {
        throw new AppError(
          `SKU duplicado no payload: ${normalizedSku}.`,
          400,
          'PRODUCT_VARIANT_SKU_DUPLICATE',
        );
      }
      payloadSkus.add(normalizedSku);
    }

    const conflicting = await tx.productVariant.findMany({
      where: {
        sku: { in: Array.from(payloadSkus) },
        product: {
          companyId,
          ...(currentProductId == null ? {} : { id: { not: currentProductId } }),
        },
      },
      select: { sku: true },
      take: 1,
    });

    if (conflicting.length > 0) {
      throw new AppError(
        `Ja existe variante com SKU ${conflicting[0]!.sku} neste tenant.`,
        409,
        'PRODUCT_VARIANT_SKU_CONFLICT',
      );
    }
  }

  private async ensureLinkedProductsBelongToCompany(
    tx: Prisma.TransactionClient,
    companyId: string,
    modifierGroups: ProductCollectionsPayload['modifierGroups'],
  ) {
    const linkedIds = modifierGroups
      .flatMap((group) => group.options)
      .map((option) => option.linkedProductId)
      .filter((value): value is string => value != null);

    if (linkedIds.length === 0) {
      return;
    }

    const uniqueLinkedIds = Array.from(new Set(linkedIds));
    const count = await tx.product.count({
      where: {
        companyId,
        id: { in: uniqueLinkedIds },
      },
    });

    if (count !== uniqueLinkedIds.length) {
      throw new AppError(
        'Uma ou mais opcoes de modificador referenciam produtos invalidos para este tenant.',
        400,
        'PRODUCT_MODIFIER_LINKED_PRODUCT_INVALID',
      );
    }
  }

  private async replaceProductCollections(
    tx: Prisma.TransactionClient,
    productId: string,
    collections: ProductCollectionsPayload,
  ) {
    await tx.productVariant.deleteMany({
      where: { productId },
    });

    if (collections.variants.length > 0) {
      await tx.productVariant.createMany({
        data: collections.variants.map((variant, index) => ({
          productId,
          sku: this.normalizeSku(variant.sku),
          colorLabel: variant.colorLabel.trim(),
          sizeLabel: variant.sizeLabel.trim(),
          priceAdditionalCents: variant.priceAdditionalCents,
          stockMil: variant.stockMil,
          sortOrder: variant.sortOrder ?? index,
          isActive: variant.isActive,
        })),
      });
    }

    await tx.productModifierGroup.deleteMany({
      where: { productId },
    });

    for (const [groupIndex, group] of collections.modifierGroups.entries()) {
      await tx.productModifierGroup.create({
        data: {
          productId,
          name: group.name.trim(),
          isRequired: group.isRequired,
          minSelections: group.minSelections,
          maxSelections: group.maxSelections,
          sortOrder: group.sortOrder ?? groupIndex,
          isActive: group.isActive,
          options: {
            create: group.options.map((option, optionIndex) => ({
              name: option.name.trim(),
              adjustmentType: option.adjustmentType,
              priceDeltaCents: option.priceDeltaCents,
              linkedProductId: option.linkedProductId,
              sortOrder: option.sortOrder ?? optionIndex,
              isActive: option.isActive,
            })),
          },
        },
      });
    }
  }

  private toCreateOrUpdateData(
    companyId: string,
    input: ProductUpsertInput,
    categoryId: string | null,
    collections: ProductCollectionsPayload,
  ): Prisma.ProductUncheckedCreateInput {
    const catalogData = this.resolveCatalogData(input, collections.variants.length);
    const resolvedName = this.resolveDisplayName(input, catalogData);
    const resolvedStockMil = this.resolveStockMil(input.stockMil, collections.variants);

    return {
      companyId,
      localUuid: input.localUuid,
      categoryId,
      name: resolvedName,
      description: input.description,
      barcode: input.barcode,
      productType: input.productType,
      niche: input.niche,
      catalogType: catalogData.catalogType,
      modelName: catalogData.modelName,
      variantLabel: catalogData.variantLabel,
      unitMeasure: input.unitMeasure,
      costPriceCents: input.costPriceCents,
      manualCostCents: input.manualCostCents,
      costSource: input.costSource,
      variableCostSnapshotCents: input.variableCostSnapshotCents,
      estimatedGrossMarginCents: input.estimatedGrossMarginCents,
      estimatedGrossMarginPercentBasisPoints:
        input.estimatedGrossMarginPercentBasisPoints,
      lastCostUpdatedAt: input.lastCostUpdatedAt,
      salePriceCents: input.salePriceCents,
      stockMil: resolvedStockMil,
      isActive: input.deletedAt == null ? input.isActive : false,
      deletedAt: input.deletedAt,
    };
  }

  private toProductDto(product: ProductWithRelations) {
    return {
      id: product.id,
      companyId: product.companyId,
      localUuid: product.localUuid,
      categoryId: product.categoryId,
      name: product.name,
      description: product.description,
      barcode: product.barcode,
      productType: product.productType,
      niche: product.niche,
      catalogType: product.catalogType,
      modelName: product.modelName,
      variantLabel: product.variantLabel,
      unitMeasure: product.unitMeasure,
      costPriceCents: product.costPriceCents,
      manualCostCents: product.manualCostCents,
      costSource: product.costSource,
      variableCostSnapshotCents: product.variableCostSnapshotCents,
      estimatedGrossMarginCents: product.estimatedGrossMarginCents,
      estimatedGrossMarginPercentBasisPoints:
        product.estimatedGrossMarginPercentBasisPoints,
      lastCostUpdatedAt: product.lastCostUpdatedAt?.toISOString() ?? null,
      salePriceCents: product.salePriceCents,
      stockMil: product.stockMil,
      isActive: product.isActive,
      deletedAt: product.deletedAt?.toISOString() ?? null,
      createdAt: product.createdAt.toISOString(),
      updatedAt: product.updatedAt.toISOString(),
      variants: product.variants.map((variant) => ({
        id: variant.id,
        sku: variant.sku,
        colorLabel: variant.colorLabel,
        sizeLabel: variant.sizeLabel,
        priceAdditionalCents: variant.priceAdditionalCents,
        stockMil: variant.stockMil,
        sortOrder: variant.sortOrder,
        isActive: variant.isActive,
        createdAt: variant.createdAt.toISOString(),
        updatedAt: variant.updatedAt.toISOString(),
      })),
      modifierGroups: product.modifierGroups.map((group) => ({
        id: group.id,
        name: group.name,
        isRequired: group.isRequired,
        minSelections: group.minSelections,
        maxSelections: group.maxSelections,
        sortOrder: group.sortOrder,
        isActive: group.isActive,
        createdAt: group.createdAt.toISOString(),
        updatedAt: group.updatedAt.toISOString(),
        options: group.options.map((option) => ({
          id: option.id,
          name: option.name,
          adjustmentType: option.adjustmentType,
          priceDeltaCents: option.priceDeltaCents,
          linkedProductId: option.linkedProductId,
          sortOrder: option.sortOrder,
          isActive: option.isActive,
          createdAt: option.createdAt.toISOString(),
          updatedAt: option.updatedAt.toISOString(),
        })),
      })),
    };
  }

  private normalizeCollections(input: ProductUpsertInput): ProductCollectionsPayload {
    return {
      variants: input.variants.map((variant, index) => ({
        ...variant,
        sku: this.normalizeSku(variant.sku),
        colorLabel: variant.colorLabel.trim(),
        sizeLabel: variant.sizeLabel.trim(),
        sortOrder: variant.sortOrder ?? index,
      })),
      modifierGroups: input.modifierGroups.map((group, groupIndex) => ({
        ...group,
        name: group.name.trim(),
        sortOrder: group.sortOrder ?? groupIndex,
        options: group.options.map((option, optionIndex) => ({
          ...option,
          name: option.name.trim(),
          sortOrder: option.sortOrder ?? optionIndex,
        })),
      })),
    };
  }

  private resolveCatalogData(input: ProductUpsertInput, variantCount: number) {
    if (input.catalogType !== 'variant' && variantCount === 0) {
      return {
        catalogType: 'simple' as Product['catalogType'],
        modelName: null,
        variantLabel: null,
      };
    }

    return {
      catalogType: 'variant' as Product['catalogType'],
      modelName: input.modelName,
      variantLabel: input.variantLabel,
    };
  }

  private resolveDisplayName(
    input: ProductUpsertInput,
    catalogData: {
      catalogType: Product['catalogType'];
      modelName: string | null;
      variantLabel: string | null;
    },
  ) {
    if (
      input.variants.length > 0 &&
      catalogData.modelName != null &&
      catalogData.modelName.trim().length > 0
    ) {
      return catalogData.modelName.trim();
    }

    if (
      catalogData.catalogType === 'variant' &&
      catalogData.modelName &&
      catalogData.variantLabel
    ) {
      return `${catalogData.modelName} - ${catalogData.variantLabel}`;
    }

    return input.name.trim();
  }

  private resolveStockMil(
    stockMil: number,
    variants: ProductCollectionsPayload['variants'],
  ) {
    if (variants.length === 0) {
      return stockMil;
    }

    return variants.reduce((sum, variant) => {
      if (!variant.isActive) {
        return sum;
      }
      return sum + variant.stockMil;
    }, 0);
  }

  private normalizeSku(value: string) {
    return value.trim().toUpperCase();
  }
}
