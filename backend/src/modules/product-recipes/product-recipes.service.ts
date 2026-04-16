import { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type {
  ProductRecipeItemInput,
  ProductRecipeUpsertInput,
} from './product-recipes.schemas';

const productRecipeInclude = {
  recipeItems: {
    orderBy: [{ createdAt: 'asc' }],
    include: {
      supply: {
        select: {
          id: true,
          localUuid: true,
          name: true,
          unitType: true,
          purchaseUnitType: true,
        },
      },
    },
  },
} satisfies Prisma.ProductInclude;

type ProductWithRecipe = Prisma.ProductGetPayload<{
  include: typeof productRecipeInclude;
}>;

export class ProductRecipesService {
  async listForCompany(companyId: string) {
    const products = await prisma.product.findMany({
      where: {
        companyId,
        recipeItems: {
          some: {},
        },
      },
      include: productRecipeInclude,
      orderBy: [{ name: 'asc' }, { updatedAt: 'desc' }],
    });

    return products.map((product) => this.toRecipeDto(product));
  }

  async getByProductId(companyId: string, productId: string) {
    const product = await prisma.product.findFirst({
      where: {
        id: productId,
        companyId,
      },
      include: productRecipeInclude,
    });

    if (!product) {
      throw new AppError(
        'Produto nao encontrado para a ficha tecnica.',
        404,
        'PRODUCT_RECIPE_PRODUCT_NOT_FOUND',
      );
    }

    return this.toRecipeDto(product);
  }

  async upsertForProduct(
    companyId: string,
    productId: string,
    input: ProductRecipeUpsertInput,
  ) {
    return prisma.$transaction(async (tx) => {
      const product = await tx.product.findFirst({
        where: {
          id: productId,
          companyId,
        },
        select: {
          id: true,
          localUuid: true,
        },
      });

      if (!product) {
        throw new AppError(
          'Produto nao encontrado para a ficha tecnica.',
          404,
          'PRODUCT_RECIPE_PRODUCT_NOT_FOUND',
        );
      }

      await this.ensureSuppliesBelongToCompany(tx, companyId, input.items);

      await tx.productRecipeItem.deleteMany({
        where: {
          companyId,
          productId: product.id,
        },
      });

      if (input.items.length > 0) {
        await tx.productRecipeItem.createMany({
          data: input.items.map((item) => ({
            companyId,
            localUuid: item.localUuid,
            productId: product.id,
            supplyId: item.supplyId,
            quantityUsedMil: item.quantityUsedMil,
            unitType: item.unitType,
            wasteBasisPoints: item.wasteBasisPoints,
            notes: item.notes,
          })),
        });
      }

      const persisted = await tx.product.findUnique({
        where: { id: product.id },
        include: productRecipeInclude,
      });

      if (!persisted) {
        throw new AppError(
          'Ficha tecnica nao encontrada apos persistencia.',
          500,
          'PRODUCT_RECIPE_UPDATE_INCONSISTENT',
        );
      }

      return this.toRecipeDto(persisted);
    });
  }

  async deleteForProduct(companyId: string, productId: string) {
    const product = await prisma.product.findFirst({
      where: {
        id: productId,
        companyId,
      },
      select: {
        id: true,
        localUuid: true,
        name: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!product) {
      throw new AppError(
        'Produto nao encontrado para a ficha tecnica.',
        404,
        'PRODUCT_RECIPE_PRODUCT_NOT_FOUND',
      );
    }

    await prisma.productRecipeItem.deleteMany({
      where: {
        companyId,
        productId: product.id,
      },
    });

    return {
      productId: product.id,
      productLocalUuid: product.localUuid,
      productName: product.name,
      updatedAt: product.updatedAt.toISOString(),
      items: [],
    };
  }

  private async ensureSuppliesBelongToCompany(
    tx: Prisma.TransactionClient,
    companyId: string,
    items: ProductRecipeItemInput[],
  ) {
    if (items.length == 0) {
      return;
    }

    const uniqueSupplyIds = Array.from(new Set(items.map((item) => item.supplyId)));
    const count = await tx.supply.count({
      where: {
        companyId,
        id: { in: uniqueSupplyIds },
      },
    });

    if (count !== uniqueSupplyIds.length) {
      throw new AppError(
        'Um ou mais insumos remotos da ficha tecnica nao pertencem a este tenant.',
        400,
        'PRODUCT_RECIPE_SUPPLY_INVALID',
      );
    }
  }

  private toRecipeDto(product: ProductWithRecipe) {
    const latestUpdatedAt = product.recipeItems.reduce<Date>(
      (latest, item) => (item.updatedAt > latest ? item.updatedAt : latest),
      product.updatedAt,
    );

    return {
      productId: product.id,
      productLocalUuid: product.localUuid,
      productName: product.name,
      updatedAt: latestUpdatedAt.toISOString(),
      items: product.recipeItems.map((item) => ({
        id: item.id,
        localUuid: item.localUuid,
        productId: item.productId,
        supplyId: item.supplyId,
        supplyLocalUuid: item.supply.localUuid,
        supplyName: item.supply.name,
        quantityUsedMil: item.quantityUsedMil,
        unitType: item.unitType,
        wasteBasisPoints: item.wasteBasisPoints,
        notes: item.notes,
        createdAt: item.createdAt.toISOString(),
        updatedAt: item.updatedAt.toISOString(),
      })),
    };
  }
}
