import type { Product } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { ProductUpsertInput } from './products.schemas';

export class ProductsService {
  async listForCompany(companyId: string, includeDeleted = false) {
    const products = await prisma.product.findMany({
      where: {
        companyId,
        ...(includeDeleted ? {} : { deletedAt: null }),
      },
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
    });

    if (!product) {
      throw new AppError('Produto nao encontrado.', 404, 'PRODUCT_NOT_FOUND');
    }

    return this.toProductDto(product);
  }

  async create(companyId: string, input: ProductUpsertInput) {
    const categoryId = await this.resolveCategoryId(companyId, input.categoryId);

    const product = await prisma.product.upsert({
      where: {
        companyId_localUuid: {
          companyId,
          localUuid: input.localUuid,
        },
      },
      update: this.toCreateOrUpdateData(companyId, input, categoryId),
      create: this.toCreateOrUpdateData(companyId, input, categoryId),
    });

    return this.toProductDto(product);
  }

  async update(companyId: string, productId: string, input: ProductUpsertInput) {
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

    await this.ensureLocalUuidAvailable(companyId, input.localUuid, productId);
    const categoryId = await this.resolveCategoryId(companyId, input.categoryId);

    const product = await prisma.product.update({
      where: { id: productId },
      data: this.toCreateOrUpdateData(companyId, input, categoryId),
    });

    return this.toProductDto(product);
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
    });

    return this.toProductDto(product);
  }

  private async resolveCategoryId(
    companyId: string,
    categoryId: string | null,
  ) {
    if (categoryId == null) {
      return null;
    }

    const category = await prisma.category.findFirst({
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
    companyId: string,
    localUuid: string,
    currentId: string,
  ) {
    const conflicting = await prisma.product.findFirst({
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

  private toCreateOrUpdateData(
    companyId: string,
    input: ProductUpsertInput,
    categoryId: string | null,
  ) {
    const catalogData = this.resolveCatalogData(input);
    const resolvedName = this.resolveDisplayName(input, catalogData);

    return {
      companyId,
      localUuid: input.localUuid,
      categoryId,
      name: resolvedName,
      description: input.description,
      barcode: input.barcode,
      productType: input.productType,
      catalogType: catalogData.catalogType,
      modelName: catalogData.modelName,
      variantLabel: catalogData.variantLabel,
      unitMeasure: input.unitMeasure,
      costPriceCents: input.costPriceCents,
      salePriceCents: input.salePriceCents,
      stockMil: input.stockMil,
      isActive: input.deletedAt == null ? input.isActive : false,
      deletedAt: input.deletedAt,
    };
  }

  private toProductDto(product: Product) {
    return {
      id: product.id,
      companyId: product.companyId,
      localUuid: product.localUuid,
      categoryId: product.categoryId,
      name: product.name,
      description: product.description,
      barcode: product.barcode,
      productType: product.productType,
      catalogType: product.catalogType,
      modelName: product.modelName,
      variantLabel: product.variantLabel,
      unitMeasure: product.unitMeasure,
      costPriceCents: product.costPriceCents,
      salePriceCents: product.salePriceCents,
      stockMil: product.stockMil,
      isActive: product.isActive,
      deletedAt: product.deletedAt?.toISOString() ?? null,
      createdAt: product.createdAt.toISOString(),
      updatedAt: product.updatedAt.toISOString(),
    };
  }

  private resolveCatalogData(input: ProductUpsertInput) {
    if (input.catalogType !== 'variant') {
      return {
        catalogType: 'simple',
        modelName: null,
        variantLabel: null,
      } as const;
    }

    return {
      catalogType: 'variant',
      modelName: input.modelName,
      variantLabel: input.variantLabel,
    } as const;
  }

  private resolveDisplayName(
    input: ProductUpsertInput,
    catalogData: {
      catalogType: string;
      modelName: string | null;
      variantLabel: string | null;
    },
  ) {
    if (
      catalogData.catalogType === 'variant' &&
      catalogData.modelName &&
      catalogData.variantLabel
    ) {
      return `${catalogData.modelName} — ${catalogData.variantLabel}`;
    }

    return input.name;
  }
}
