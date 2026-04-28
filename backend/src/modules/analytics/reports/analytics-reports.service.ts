import { prisma } from '../../../database/prisma';
import { AnalyticsSnapshotsService } from '../snapshots/analytics-snapshots.service';
import type { AnalyticsReportQueryInput } from './analytics-reports.schemas';

type ProductAggregate = {
  productKey: string;
  productId: string | null;
  productName: string;
  quantityMil: number;
  salesCount: number;
  revenueCents: number;
  costCents: number;
  profitCents: number;
};

type CustomerAggregate = {
  customerKey: string;
  customerId: string | null;
  customerName: string;
  salesCount: number;
  revenueCents: number;
  costCents: number;
  profitCents: number;
  fiadoPaymentsCents: number;
};

type InventoryReportItem = {
  itemType: string;
  productId?: string;
  productVariantId?: string | null;
  supplyId?: string;
  name: string;
  sku?: string | null;
  variantColorLabel?: string;
  variantSizeLabel?: string;
  unitMeasure: string;
  currentStockMil: number;
  minimumStockMil: number | null;
  costPriceCents: number;
  salePriceCents: number;
  isActive: boolean;
};

export class AnalyticsReportsService {
  constructor(
    private readonly snapshotsService = new AnalyticsSnapshotsService(),
  ) {}

  async getSalesByDay(query: AnalyticsReportQueryInput) {
    const { materialization, companyRows } = await this.loadRange(query);

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      totals: companyRows.reduce(
        (accumulator, row) => {
          accumulator.salesCount += row.salesCount;
          accumulator.salesAmountCents += row.salesAmountCents;
          accumulator.salesProfitCents += row.salesProfitCents;
          return accumulator;
        },
        {
          salesCount: 0,
          salesAmountCents: 0,
          salesProfitCents: 0,
        },
      ),
      series: companyRows.map((row) => ({
        date: this.snapshotsService.toCompanyDailySnapshotDto(row).date,
        salesCount: row.salesCount,
        salesAmountCents: row.salesAmountCents,
        salesCostCents: row.salesCostCents,
        salesProfitCents: row.salesProfitCents,
      })),
    };
  }

  async getSalesByProduct(query: AnalyticsReportQueryInput) {
    const { materialization, productRows } = await this.loadRange(query);
    const items = aggregateProducts(productRows)
      .sort((left, right) => right.revenueCents - left.revenueCents)
      .slice(0, query.topN)
      .map((item) => ({
        productKey: item.productKey,
        productId: item.productId,
        productName: item.productName,
        quantityMil: item.quantityMil,
        salesCount: item.salesCount,
        revenueCents: item.revenueCents,
        costCents: item.costCents,
        profitCents: item.profitCents,
      }));

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      totals: items.reduce(
        (accumulator, item) => {
          accumulator.quantityMil += item.quantityMil;
          accumulator.salesCount += item.salesCount;
          accumulator.revenueCents += item.revenueCents;
          accumulator.costCents += item.costCents;
          accumulator.profitCents += item.profitCents;
          return accumulator;
        },
        {
          quantityMil: 0,
          salesCount: 0,
          revenueCents: 0,
          costCents: 0,
          profitCents: 0,
        },
      ),
      items,
    };
  }

  async getSalesByProductForTenant(
    query: AnalyticsReportQueryInput,
    filters: { productId?: string; categoryId?: string } = {},
  ) {
    const payload = await this.getSalesByProduct(query);
    const allowedProductIds = await this.resolveAllowedProductIds(
      query.companyId,
      filters,
    );
    const items = payload.items.filter((item) => {
      if (filters.productId != null) {
        return item.productId === filters.productId;
      }
      if (allowedProductIds != null) {
        return item.productId != null && allowedProductIds.has(item.productId);
      }
      return true;
    });

    return {
      ...payload,
      totals: sumProductItems(items),
      items,
    };
  }

  async getSalesByCustomer(query: AnalyticsReportQueryInput) {
    const { materialization, customerRows } = await this.loadRange(query);
    const items = aggregateCustomers(customerRows)
      .sort((left, right) => right.revenueCents - left.revenueCents)
      .slice(0, query.topN)
      .map((item) => ({
        customerKey: item.customerKey,
        customerId: item.customerId,
        customerName: item.customerName,
        salesCount: item.salesCount,
        revenueCents: item.revenueCents,
        costCents: item.costCents,
        profitCents: item.profitCents,
        fiadoPaymentsCents: item.fiadoPaymentsCents,
      }));

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      totals: items.reduce(
        (accumulator, item) => {
          accumulator.salesCount += item.salesCount;
          accumulator.revenueCents += item.revenueCents;
          accumulator.costCents += item.costCents;
          accumulator.profitCents += item.profitCents;
          accumulator.fiadoPaymentsCents += item.fiadoPaymentsCents;
          return accumulator;
        },
        {
          salesCount: 0,
          revenueCents: 0,
          costCents: 0,
          profitCents: 0,
          fiadoPaymentsCents: 0,
        },
      ),
      items,
    };
  }

  async getSalesByCustomerForTenant(
    query: AnalyticsReportQueryInput,
    filters: { customerId?: string } = {},
  ) {
    const payload = await this.getSalesByCustomer(query);
    const items =
      filters.customerId == null
        ? payload.items
        : payload.items.filter((item) => item.customerId === filters.customerId);

    return {
      ...payload,
      totals: sumCustomerItems(items),
      items,
    };
  }

  async getCashConsolidated(query: AnalyticsReportQueryInput) {
    const { materialization, companyRows } = await this.loadRange(query);

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      totals: companyRows.reduce(
        (accumulator, row) => {
          accumulator.cashInflowCents += row.cashInflowCents;
          accumulator.cashOutflowCents += row.cashOutflowCents;
          accumulator.cashNetCents += row.cashNetCents;
          return accumulator;
        },
        {
          cashInflowCents: 0,
          cashOutflowCents: 0,
          cashNetCents: 0,
        },
      ),
      series: companyRows.map((row) => ({
        date: this.snapshotsService.toCompanyDailySnapshotDto(row).date,
        cashInflowCents: row.cashInflowCents,
        cashOutflowCents: row.cashOutflowCents,
        cashNetCents: row.cashNetCents,
      })),
    };
  }

  async getFinancialSummary(query: AnalyticsReportQueryInput) {
    const { materialization, companyRows } = await this.loadRange(query);
    const totals = companyRows.reduce(
      (accumulator, row) => {
        accumulator.salesAmountCents += row.salesAmountCents;
        accumulator.salesCostCents += row.salesCostCents;
        accumulator.salesProfitCents += row.salesProfitCents;
        accumulator.purchasesAmountCents += row.purchasesAmountCents;
        accumulator.fiadoPaymentsAmountCents += row.fiadoPaymentsAmountCents;
        accumulator.cashNetCents += row.cashNetCents;
        accumulator.financialAdjustmentsCents += row.financialAdjustmentsCents;
        return accumulator;
      },
      {
        salesAmountCents: 0,
        salesCostCents: 0,
        salesProfitCents: 0,
        purchasesAmountCents: 0,
        fiadoPaymentsAmountCents: 0,
        cashNetCents: 0,
        financialAdjustmentsCents: 0,
      },
    );

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      summary: {
        ...totals,
        operatingMarginBasisPoints:
          totals.salesAmountCents === 0
            ? 0
            : Math.round(
                (totals.salesProfitCents / totals.salesAmountCents) * 10_000,
              ),
      },
      series: companyRows.map((row) => ({
        date: this.snapshotsService.toCompanyDailySnapshotDto(row).date,
        salesAmountCents: row.salesAmountCents,
        salesProfitCents: row.salesProfitCents,
        purchasesAmountCents: row.purchasesAmountCents,
        fiadoPaymentsAmountCents: row.fiadoPaymentsAmountCents,
        cashNetCents: row.cashNetCents,
        financialAdjustmentsCents: row.financialAdjustmentsCents,
      })),
    };
  }

  async getProfitabilityForTenant(
    query: AnalyticsReportQueryInput,
    filters: { productId?: string; categoryId?: string } = {},
  ) {
    const salesByProduct = await this.getSalesByProductForTenant(query, filters);
    return {
      company: salesByProduct.company,
      period: salesByProduct.period,
      materialization: salesByProduct.materialization,
      totals: salesByProduct.totals,
      items: salesByProduct.items.map((item) => ({
        key: item.productKey,
        label: item.productName,
        productId: item.productId,
        variantId: null,
        categoryId: null,
        quantityMil: item.quantityMil,
        revenueCents: item.revenueCents,
        costCents: item.costCents,
        profitCents: item.profitCents,
        marginBasisPoints:
          item.revenueCents === 0
            ? 0
            : Math.round((item.profitCents / item.revenueCents) * 10_000),
      })),
    };
  }

  async getPurchasesForTenant(
    query: AnalyticsReportQueryInput,
    filters: { supplierId?: string } = {},
  ) {
    const { materialization, companyRows } = await this.loadRange(query);
    const period = this.snapshotsService.resolvePeriod(query);
    const purchases = await prisma.purchase.findMany({
      where: {
        companyId: query.companyId,
        purchasedAt: {
          gte: period.startDate,
          lt: nextUtcDate(period.endDate),
        },
        ...(filters.supplierId == null
          ? {}
          : {
              supplierId: filters.supplierId,
            }),
      },
      select: {
        supplierId: true,
        finalAmountCents: true,
        paidAmountCents: true,
        pendingAmountCents: true,
        supplier: {
          select: {
            name: true,
            tradeName: true,
          },
        },
      },
    });

    const suppliers = new Map<
      string,
      {
        supplierId: string;
        supplierName: string;
        purchasesCount: number;
        totalPurchasedCents: number;
        totalPaidCents: number;
        totalPendingCents: number;
      }
    >();

    for (const purchase of purchases) {
      const current = suppliers.get(purchase.supplierId) ?? {
        supplierId: purchase.supplierId,
        supplierName:
          purchase.supplier.tradeName?.trim() || purchase.supplier.name,
        purchasesCount: 0,
        totalPurchasedCents: 0,
        totalPaidCents: 0,
        totalPendingCents: 0,
      };
      current.purchasesCount += 1;
      current.totalPurchasedCents += purchase.finalAmountCents;
      current.totalPaidCents += purchase.paidAmountCents;
      current.totalPendingCents += purchase.pendingAmountCents;
      suppliers.set(purchase.supplierId, current);
    }

    const summary = purchases.reduce(
      (accumulator, purchase) => {
        accumulator.purchasesCount += 1;
        accumulator.totalPurchasedCents += purchase.finalAmountCents;
        accumulator.totalPaidCents += purchase.paidAmountCents;
        accumulator.totalPendingCents += purchase.pendingAmountCents;
        return accumulator;
      },
      {
        purchasesCount: 0,
        totalPurchasedCents: 0,
        totalPaidCents: 0,
        totalPendingCents: 0,
      },
    );

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      summary: {
        ...summary,
        snapshotPurchasesAmountCents: companyRows.reduce(
          (total, row) => total + row.purchasesAmountCents,
          0,
        ),
      },
      suppliers: [...suppliers.values()].sort(
        (left, right) => right.totalPurchasedCents - left.totalPurchasedCents,
      ),
      items: [],
    };
  }

  async getInventoryForTenant(companyId: string) {
    const [products, supplies] = await Promise.all([
      prisma.product.findMany({
        where: {
          companyId,
          deletedAt: null,
        },
        select: {
          id: true,
          name: true,
          unitMeasure: true,
          stockMil: true,
          costPriceCents: true,
          salePriceCents: true,
          isActive: true,
          variants: {
            select: {
              id: true,
              sku: true,
              colorLabel: true,
              sizeLabel: true,
              stockMil: true,
              isActive: true,
            },
          },
        },
      }),
      prisma.supply.findMany({
        where: {
          companyId,
          deletedAt: null,
        },
        select: {
          id: true,
          name: true,
          unitType: true,
          currentStockMil: true,
          minimumStockMil: true,
          lastPurchasePriceCents: true,
          isActive: true,
        },
      }),
    ]);

    const productItems: InventoryReportItem[] = [];
    for (const product of products) {
      if (product.variants.length === 0) {
        productItems.push({
          itemType: 'product',
          productId: product.id,
          productVariantId: null,
          name: product.name,
          sku: null,
          unitMeasure: product.unitMeasure,
          currentStockMil: product.stockMil,
          minimumStockMil: null,
          costPriceCents: product.costPriceCents,
          salePriceCents: product.salePriceCents,
          isActive: product.isActive,
        });
        continue;
      }

      for (const variant of product.variants) {
        productItems.push({
          itemType: 'product_variant',
          productId: product.id,
          productVariantId: variant.id,
          name: product.name,
          sku: variant.sku,
          variantColorLabel: variant.colorLabel,
          variantSizeLabel: variant.sizeLabel,
          unitMeasure: product.unitMeasure,
          currentStockMil: variant.stockMil,
          minimumStockMil: null,
          costPriceCents: product.costPriceCents,
          salePriceCents: product.salePriceCents,
          isActive: product.isActive && variant.isActive,
        });
      }
    }

    const supplyItems: InventoryReportItem[] = supplies.map((supply) => ({
      itemType: 'supply',
      supplyId: supply.id,
      name: supply.name,
      unitMeasure: supply.unitType,
      currentStockMil: supply.currentStockMil ?? 0,
      minimumStockMil: supply.minimumStockMil,
      costPriceCents: supply.lastPurchasePriceCents,
      salePriceCents: 0,
      isActive: supply.isActive,
    }));

    const items: InventoryReportItem[] = [...productItems, ...supplyItems];
    const summary = items.reduce(
      (accumulator, item) => {
        accumulator.totalItemsCount += 1;
        if (item.currentStockMil <= 0) {
          accumulator.zeroedItemsCount += 1;
        }
        if (
          item.minimumStockMil != null &&
          item.currentStockMil < item.minimumStockMil
        ) {
          accumulator.belowMinimumItemsCount += 1;
        }
        accumulator.inventoryCostValueCents += Math.round(
          (item.currentStockMil * item.costPriceCents) / 1000,
        );
        accumulator.inventorySaleValueCents += Math.round(
          (item.currentStockMil * item.salePriceCents) / 1000,
        );
        return accumulator;
      },
      {
        totalItemsCount: 0,
        zeroedItemsCount: 0,
        belowMinimumItemsCount: 0,
        inventoryCostValueCents: 0,
        inventorySaleValueCents: 0,
        divergenceItemsCount: 0,
      },
    );

    return {
      partial: true,
      reason: 'inventory_movements_and_physical_counts_contract_absent',
      generatedAt: new Date().toISOString(),
      summary,
      items,
    };
  }

  private async loadRange(query: AnalyticsReportQueryInput) {
    const materialization = await this.snapshotsService.materializeCompanyRange(
      query,
    );
    const period = this.snapshotsService.resolvePeriod(query);
    const [companyRows, productRows, customerRows] = await Promise.all([
      this.snapshotsService.loadCompanyDailySnapshotRows(
        materialization.company.id,
        period,
      ),
      this.snapshotsService.loadProductDailySnapshotRows(
        materialization.company.id,
        period,
      ),
      this.snapshotsService.loadCustomerDailySnapshotRows(
        materialization.company.id,
        period,
      ),
    ]);

    return { materialization, companyRows, productRows, customerRows };
  }

  private async resolveAllowedProductIds(
    companyId: string,
    filters: { productId?: string; categoryId?: string },
  ) {
    if (filters.categoryId == null) {
      return null;
    }

    const products = await prisma.product.findMany({
      where: {
        companyId,
        categoryId: filters.categoryId,
      },
      select: {
        id: true,
      },
    });
    return new Set(products.map((product) => product.id));
  }
}

function sumProductItems(
  items: Array<{
    quantityMil: number;
    salesCount: number;
    revenueCents: number;
    costCents: number;
    profitCents: number;
  }>,
) {
  return items.reduce(
    (accumulator, item) => {
      accumulator.quantityMil += item.quantityMil;
      accumulator.salesCount += item.salesCount;
      accumulator.revenueCents += item.revenueCents;
      accumulator.costCents += item.costCents;
      accumulator.profitCents += item.profitCents;
      return accumulator;
    },
    {
      quantityMil: 0,
      salesCount: 0,
      revenueCents: 0,
      costCents: 0,
      profitCents: 0,
    },
  );
}

function sumCustomerItems(
  items: Array<{
    salesCount: number;
    revenueCents: number;
    costCents: number;
    profitCents: number;
    fiadoPaymentsCents: number;
  }>,
) {
  return items.reduce(
    (accumulator, item) => {
      accumulator.salesCount += item.salesCount;
      accumulator.revenueCents += item.revenueCents;
      accumulator.costCents += item.costCents;
      accumulator.profitCents += item.profitCents;
      accumulator.fiadoPaymentsCents += item.fiadoPaymentsCents;
      return accumulator;
    },
    {
      salesCount: 0,
      revenueCents: 0,
      costCents: 0,
      profitCents: 0,
      fiadoPaymentsCents: 0,
    },
  );
}

function nextUtcDate(date: Date) {
  return new Date(date.getTime() + 24 * 60 * 60 * 1000);
}

function aggregateProducts(
  rows: Awaited<
    ReturnType<AnalyticsSnapshotsService['loadProductDailySnapshotRows']>
  >,
) {
  const aggregated = new Map<string, ProductAggregate>();

  for (const row of rows) {
    const current = aggregated.get(row.productKey) ?? {
      productKey: row.productKey,
      productId: row.productId,
      productName: row.productNameSnapshot,
      quantityMil: 0,
      salesCount: 0,
      revenueCents: 0,
      costCents: 0,
      profitCents: 0,
    };

    current.quantityMil += row.quantityMil;
    current.salesCount += row.salesCount;
    current.revenueCents += row.revenueCents;
    current.costCents += row.costCents;
    current.profitCents += row.profitCents;

    aggregated.set(row.productKey, current);
  }

  return [...aggregated.values()];
}

function aggregateCustomers(
  rows: Awaited<
    ReturnType<AnalyticsSnapshotsService['loadCustomerDailySnapshotRows']>
  >,
) {
  const aggregated = new Map<string, CustomerAggregate>();

  for (const row of rows) {
    const current = aggregated.get(row.customerKey) ?? {
      customerKey: row.customerKey,
      customerId: row.customerId,
      customerName: row.customerNameSnapshot,
      salesCount: 0,
      revenueCents: 0,
      costCents: 0,
      profitCents: 0,
      fiadoPaymentsCents: 0,
    };

    current.salesCount += row.salesCount;
    current.revenueCents += row.revenueCents;
    current.costCents += row.costCents;
    current.profitCents += row.profitCents;
    current.fiadoPaymentsCents += row.fiadoPaymentsCents;

    aggregated.set(row.customerKey, current);
  }

  return [...aggregated.values()];
}
