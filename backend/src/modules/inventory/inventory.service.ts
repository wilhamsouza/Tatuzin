import { prisma } from '../../database/prisma';
import { toPaginationParams } from '../../shared/http/pagination';
import type { InventoryListQueryInput } from './inventory.schemas';

type InventoryStatus = 'active' | 'zeroed' | 'belowMinimum' | 'inactive';

type InventoryItemDto = {
  productId: string;
  productVariantId: string | null;
  name: string;
  variantName: string | null;
  sku: string | null;
  unitMeasure: string;
  currentStockMil: number;
  minimumStockMil: number;
  costPriceCents: number;
  salePriceCents: number;
  status: InventoryStatus;
};

export class InventoryService {
  async listForCompany(companyId: string, query: InventoryListQueryInput) {
    const items = await this.loadItems(companyId);
    const filtered = this.applyFilters(items, query);
    const { skip, take } = toPaginationParams(query);

    return {
      items: filtered.slice(skip, skip + take),
      total: filtered.length,
    };
  }

  async summaryForCompany(companyId: string) {
    const items = await this.loadItems(companyId);

    return {
      totalItemsCount: items.length,
      activeItemsCount: items.filter((item) => item.status === 'active').length,
      zeroedItemsCount: items.filter((item) => item.status === 'zeroed').length,
      belowMinimumItemsCount: items.filter(
        (item) => item.status === 'belowMinimum',
      ).length,
      inventoryCostValueCents: items.reduce(
        (total, item) =>
          total + Math.round((item.currentStockMil * item.costPriceCents) / 1000),
        0,
      ),
      inventorySaleValueCents: items.reduce(
        (total, item) =>
          total + Math.round((item.currentStockMil * item.salePriceCents) / 1000),
        0,
      ),
      divergenceItemsCount: 0,
    };
  }

  private async loadItems(companyId: string): Promise<InventoryItemDto[]> {
    const products = await prisma.product.findMany({
      where: {
        companyId,
        deletedAt: null,
      },
      include: {
        variants: {
          orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
        },
      },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
    });

    const items: InventoryItemDto[] = [];

    for (const product of products) {
      if (product.variants.length > 0) {
        for (const variant of product.variants) {
          items.push({
            productId: product.id,
            productVariantId: variant.id,
            name: product.name,
            variantName: this.variantName(variant.colorLabel, variant.sizeLabel),
            sku: this.clean(variant.sku) ?? this.clean(product.barcode),
            unitMeasure: product.unitMeasure,
            currentStockMil: variant.stockMil,
            minimumStockMil: 0,
            costPriceCents: product.costPriceCents,
            salePriceCents:
              product.salePriceCents + variant.priceAdditionalCents,
            status: this.resolveStatus({
              productActive: product.isActive && product.deletedAt == null,
              itemActive: variant.isActive,
              currentStockMil: variant.stockMil,
              minimumStockMil: 0,
            }),
          });
        }
        continue;
      }

      items.push({
        productId: product.id,
        productVariantId: null,
        name: product.name,
        variantName: null,
        sku: this.clean(product.barcode),
        unitMeasure: product.unitMeasure,
        currentStockMil: product.stockMil,
        minimumStockMil: 0,
        costPriceCents: product.costPriceCents,
        salePriceCents: product.salePriceCents,
        status: this.resolveStatus({
          productActive: product.isActive && product.deletedAt == null,
          itemActive: true,
          currentStockMil: product.stockMil,
          minimumStockMil: 0,
        }),
      });
    }

    return items;
  }

  private applyFilters(
    items: InventoryItemDto[],
    query: InventoryListQueryInput,
  ) {
    const search = query.query.trim().toLocaleLowerCase('pt-BR');
    return items.filter((item) => {
      if (query.filter !== 'all' && item.status !== query.filter) {
        return false;
      }

      if (search.length === 0) {
        return true;
      }

      const haystack = [
        item.name,
        item.variantName,
        item.sku,
        item.unitMeasure,
      ]
        .filter((value): value is string => value != null)
        .join(' ')
        .toLocaleLowerCase('pt-BR');
      return haystack.includes(search);
    });
  }

  private resolveStatus(input: {
    productActive: boolean;
    itemActive: boolean;
    currentStockMil: number;
    minimumStockMil: number;
  }): InventoryStatus {
    if (!input.productActive || !input.itemActive) {
      return 'inactive';
    }
    if (input.currentStockMil <= 0) {
      return 'zeroed';
    }
    if (
      input.minimumStockMil > 0 &&
      input.currentStockMil <= input.minimumStockMil
    ) {
      return 'belowMinimum';
    }
    return 'active';
  }

  private variantName(color: string, size: string) {
    const name = [this.clean(color), this.clean(size)]
      .filter((value): value is string => value != null)
      .join(' / ');
    return name.length === 0 ? null : name;
  }

  private clean(value: string | null | undefined) {
    const trimmed = value?.trim();
    return trimmed == null || trimmed.length === 0 ? null : trimmed;
  }
}
