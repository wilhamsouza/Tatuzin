import { Prisma, type Product } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { setInventoryContext } from '../inventory/inventory-context';
import { toPaginationParams } from '../../shared/http/pagination';
import { productUpsertSchema, type ProductListQueryInput, type ProductUpsertInput, type ProductUpdateInput } from './products.schemas';

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

type ProductDtoOptions = {
  includeSensitiveData?: boolean;
};

export class ProductsService {
  async listForCompany(
    companyId: string,
    query: ProductListQueryInput,
    options: ProductDtoOptions = {},
  ) {
    const where: Prisma.ProductWhereInput = {
      companyId,
      ...(query.includeDeleted ? {} : { deletedAt: null }),
      ...(query.categoryId ? { categoryId: query.categoryId } : {}),
      ...(query.isActive !== undefined ? { isActive: query.isActive } : {}),
      ...(query.search ? { OR: [
        { name: { contains: query.search, mode: 'insensitive' } },
        { barcode: { contains: query.search, mode: 'insensitive' } },
        { modelName: { contains: query.search, mode: 'insensitive' } },
        { variants: { some: { sku: { contains: query.search, mode: 'insensitive' } } } },
      ] } : {}),
    };
    const { skip, take } = toPaginationParams({
      page: query.page,
      pageSize: query.pageSize,
    });

    const [total, products] = await prisma.$transaction([
      prisma.product.count({ where }),
      prisma.product.findMany({
        where,
        include: productInclude,
        skip,
        take,
        orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
      }),
    ]);

    return {
      items: products.map((product) => this.toProductDto(product, options)),
      total,
    };
  }

  async getById(
    companyId: string,
    productId: string,
    options: ProductDtoOptions = {},
  ) {
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

    return this.toProductDto(product, options);
  }

  async create(companyId: string, input: ProductUpsertInput, actorUserId?: string) {
    return prisma.$transaction(async (tx) => {
      // A retry after a lost response must never reset stock or recreate SKUs.
      await tx.$queryRaw`SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(${companyId + ':' + input.localUuid}, 0))`;
      const existing = await tx.product.findUnique({
        where: { companyId_localUuid: { companyId, localUuid: input.localUuid } },
        include: productInclude,
      });
      if (existing) return this.toProductDto(existing, { includeSensitiveData: true });
      const categoryId = await this.resolveCategoryId(tx, companyId, input.categoryId);
      const collections = this.normalizeCollections(input);
      await this.ensureVariantSkusAvailable(tx, companyId, collections.variants);
      await this.ensureLinkedProductsBelongToCompany(tx, companyId, collections.modifierGroups);
      if (collections.variants.some(v => v.id)) {
        throw new AppError('Novas variações não podem reutilizar uma identidade existente.', 422, 'PRODUCT_VARIANT_ID_INVALID');
      }
      if (input.metadataOnly) {
        input = { ...input, stockMil: 0 };
        collections.variants = collections.variants.map(v => ({ ...v, stockMil: 0 }));
      }
      await setInventoryContext(tx, {
        actorUserId, type: 'INITIAL', origin: 'product_creation',
        referenceId: input.localUuid, skipParent: collections.variants.length > 0,
      });
      const product = await tx.product.create({
        data: this.toCreateOrUpdateData(companyId, input, categoryId, collections),
      });
      await this.replaceProductCollections(tx, product.id, collections);
      const persisted = await tx.product.findUniqueOrThrow({ where: { id: product.id }, include: productInclude });
      return this.toProductDto(persisted, { includeSensitiveData: true });
    });
  }

  async update(companyId: string, productId: string, patch: ProductUpdateInput) {
    return prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Product" WHERE id = ${productId} AND "companyId" = ${companyId} FOR UPDATE`;
      const existing = await tx.product.findFirst({ where: { id: productId, companyId }, include: productInclude });
      if (!existing) throw new AppError('Produto não encontrado.', 404, 'PRODUCT_NOT_FOUND');
      if (patch.expectedCatalogRevision !== undefined && patch.expectedCatalogRevision !== existing.catalogRevision) {
        throw new AppError('O cadastro foi alterado em outro acesso. Atualize antes de salvar.', 409, 'PRODUCT_CATALOG_REVISION_CONFLICT');
      }
      const merged = { ...this.toProductDto(existing, { includeSensitiveData: true }), ...patch };
      // Existing operational debt may make stock negative. Metadata does not
      // validate, clear or change that debt; inventory owns these quantities.
      const input = productUpsertSchema.parse(patch.metadataOnly ? {
        ...merged, stockMil: 0, variants: merged.variants.map(v => ({ ...v, stockMil: 0 })),
      } : merged);
      await this.ensureLocalUuidAvailable(tx, companyId, input.localUuid, productId);
      const categoryId = await this.resolveCategoryId(tx, companyId, input.categoryId);
      const collections = this.normalizeCollections(input);
      await this.ensureVariantSkusAvailable(tx, companyId, collections.variants, productId);
      await this.ensureLinkedProductsBelongToCompany(tx, companyId, collections.modifierGroups);
      if (!input.metadataOnly && input.stockMil !== existing.stockMil) {
        throw new AppError('O saldo mudou ou foi editado no cadastro. Atualize e use Movimentar estoque.', 409, 'PRODUCT_STOCK_CONFLICT');
      }
      const seen = new Set<string>();
      for (const variant of collections.variants) {
        const match = variant.id ? existing.variants.find(v => v.id === variant.id) : existing.variants.find(v => this.normalizeSku(v.sku) === variant.sku);
        if (variant.id && !match) throw new AppError('Variação inválida para este produto.', 422, 'PRODUCT_VARIANT_ID_INVALID');
        if (existing.variants.some(v => this.normalizeSku(v.sku) === variant.sku && v.id !== match?.id)) {
          throw new AppError('Este SKU pertence a outra variação, inclusive se estiver inativa.', 409, 'PRODUCT_VARIANT_SKU_CONFLICT');
        }
        if (match && seen.has(match.id)) throw new AppError('Variação repetida.', 422, 'PRODUCT_VARIANT_ID_DUPLICATE');
        if (!input.metadataOnly && variant.stockMil !== (match?.stockMil ?? 0)) {
          throw new AppError('O saldo da variação mudou. Atualize e use Movimentar estoque.', 409, 'PRODUCT_STOCK_CONFLICT');
        }
        if (match) seen.add(match.id);
        variant.id = match?.id;
        variant.stockMil = match?.stockMil ?? 0;
      }
      // A stocked simple SKU cannot silently become a parent of new SKUs.
      if (existing.variants.length === 0 && collections.variants.length > 0 && existing.stockMil !== 0) {
        throw new AppError('Confira e zere o saldo por movimentação antes de converter o produto em grade.', 409, 'PRODUCT_VARIANT_CONVERSION_STOCK');
      }
      if (existing.variants.length > 0 && input.catalogType === 'simple' && collections.variants.length === 0) {
        throw new AppError('Uma grade existente deve ser preservada. Inative as variações sem removê-las.', 409, 'PRODUCT_VARIANT_IDENTITY_REQUIRED');
      }
      const data = this.toCreateOrUpdateData(companyId, input, categoryId, collections);
      // Quantity belongs to inventory; metadata requests never write stock.
      const { stockMil: _ignoredStock, ...metadata } = data;
      await tx.product.update({ where: { id: productId }, data: { ...metadata, catalogRevision: { increment: 1 } } });
      await this.replaceProductCollections(tx, productId, collections);
      if (existing.variants.length > 0 || collections.variants.length > 0) {
        const variants = await tx.productVariant.findMany({ where: { productId, isActive: true }, select: { stockMil: true } });
        await tx.product.update({ where: { id: productId }, data: { stockMil: variants.reduce((sum, v) => sum + v.stockMil, 0) } });
      }
      const persisted = await tx.product.findUniqueOrThrow({ where: { id: productId }, include: productInclude });
      return this.toProductDto(persisted, { includeSensitiveData: true });
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
        catalogRevision: { increment: 1 },
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

    // Serialize SKU claims across different product transactions in this tenant.
    for (const sku of [...payloadSkus].sort()) {
      await tx.$queryRaw`SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(${companyId + ':sku:' + sku}, 0))`;
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
    const retained: string[] = [];
    for (const [index, variant] of collections.variants.entries()) {
      const data = {
        sku: this.normalizeSku(variant.sku), colorLabel: variant.colorLabel.trim(),
        sizeLabel: variant.sizeLabel.trim(), priceAdditionalCents: variant.priceAdditionalCents,
        sortOrder: variant.sortOrder ?? index, isActive: variant.isActive,
      };
      if (variant.id) {
        await tx.productVariant.update({ where: { id: variant.id }, data });
        retained.push(variant.id);
      } else {
        const created = await tx.productVariant.create({ data: { productId, ...data, stockMil: variant.stockMil } });
        retained.push(created.id);
      }
    }
    await tx.productVariant.updateMany({ where: { productId, id: { notIn: retained } }, data: { isActive: false } });

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

  toProductDto(
    product: ProductWithRelations,
    options: ProductDtoOptions = {},
  ) {
    const dto = {
      id: product.id,
      catalogRevision: product.catalogRevision,
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
      stockRevision: product.stockRevision,
      minimumStockMil: product.minimumStockMil,
      reorderPointMil: product.reorderPointMil,
      isActive: product.isActive,
      deletedAt: product.deletedAt?.toISOString() ?? null,
      createdAt: product.createdAt.toISOString(),
      updatedAt: product.updatedAt.toISOString(),
      variants: product.variants.map((variant) => ({
        id: variant.id,
        stockRevision: variant.stockRevision,
        minimumStockMil: variant.minimumStockMil,
        reorderPointMil: variant.reorderPointMil,
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

    if (options.includeSensitiveData) {
      return dto;
    }

    const {
      costPriceCents: _costPriceCents,
      manualCostCents: _manualCostCents,
      costSource: _costSource,
      variableCostSnapshotCents: _variableCostSnapshotCents,
      estimatedGrossMarginCents: _estimatedGrossMarginCents,
      estimatedGrossMarginPercentBasisPoints:
        _estimatedGrossMarginPercentBasisPoints,
      lastCostUpdatedAt: _lastCostUpdatedAt,
      ...publicDto
    } = dto;

    return publicDto;
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
