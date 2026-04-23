import { AnalyticsSnapshotsService } from '../snapshots/analytics-snapshots.service';
import type { AnalyticsDashboardQueryInput } from './analytics-dashboard.schemas';

type AggregatedProduct = {
  productKey: string;
  productId: string | null;
  productName: string;
  quantityMil: number;
  salesCount: number;
  revenueCents: number;
  costCents: number;
  profitCents: number;
};

type AggregatedCustomer = {
  customerKey: string;
  customerId: string | null;
  customerName: string;
  salesCount: number;
  revenueCents: number;
  costCents: number;
  profitCents: number;
  fiadoPaymentsCents: number;
};

export class AnalyticsDashboardService {
  constructor(
    private readonly snapshotsService = new AnalyticsSnapshotsService(),
  ) {}

  async getDashboard(query: AnalyticsDashboardQueryInput) {
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

    const totals = companyRows.reduce(
      (accumulator, row) => {
        accumulator.salesCount += row.salesCount;
        accumulator.salesAmountCents += row.salesAmountCents;
        accumulator.salesProfitCents += row.salesProfitCents;
        accumulator.cashNetCents += row.cashNetCents;
        accumulator.purchasesAmountCents += row.purchasesAmountCents;
        accumulator.fiadoPaymentsAmountCents += row.fiadoPaymentsAmountCents;
        return accumulator;
      },
      {
        salesCount: 0,
        salesAmountCents: 0,
        salesProfitCents: 0,
        cashNetCents: 0,
        purchasesAmountCents: 0,
        fiadoPaymentsAmountCents: 0,
      },
    );

    const topProducts = aggregateProducts(productRows)
      .sort((left, right) => right.revenueCents - left.revenueCents)
      .slice(0, query.topN)
      .map((product) => ({
        productKey: product.productKey,
        productId: product.productId,
        productName: product.productName,
        quantityMil: product.quantityMil,
        salesCount: product.salesCount,
        revenueCents: product.revenueCents,
        costCents: product.costCents,
        profitCents: product.profitCents,
      }));

    const aggregatedCustomers = aggregateCustomers(customerRows);
    const topCustomers = aggregatedCustomers
      .sort((left, right) => right.revenueCents - left.revenueCents)
      .slice(0, query.topN)
      .map((customer) => ({
        customerKey: customer.customerKey,
        customerId: customer.customerId,
        customerName: customer.customerName,
        salesCount: customer.salesCount,
        revenueCents: customer.revenueCents,
        costCents: customer.costCents,
        profitCents: customer.profitCents,
        fiadoPaymentsCents: customer.fiadoPaymentsCents,
      }));

    const identifiedCustomersCount = aggregatedCustomers.length;

    return {
      company: materialization.company,
      period: materialization.period,
      materialization: {
        materializedAt: materialization.materializedAt,
        coverage: materialization.coverage,
      },
      headline: {
        salesAmountCents: totals.salesAmountCents,
        salesProfitCents: totals.salesProfitCents,
        cashNetCents: totals.cashNetCents,
        purchasesAmountCents: totals.purchasesAmountCents,
        fiadoPaymentsAmountCents: totals.fiadoPaymentsAmountCents,
        salesCount: totals.salesCount,
        identifiedCustomersCount,
        averageTicketCents:
          totals.salesCount === 0
            ? 0
            : Math.round(totals.salesAmountCents / totals.salesCount),
      },
      salesSeries: companyRows.map((row) => ({
        date: this.snapshotsService.toCompanyDailySnapshotDto(row).date,
        salesCount: row.salesCount,
        salesAmountCents: row.salesAmountCents,
        salesProfitCents: row.salesProfitCents,
        cashNetCents: row.cashNetCents,
      })),
      topProducts,
      topCustomers,
    };
  }
}

function aggregateProducts(
  rows: Awaited<
    ReturnType<AnalyticsSnapshotsService['loadProductDailySnapshotRows']>
  >,
) {
  const aggregated = new Map<string, AggregatedProduct>();

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
  const aggregated = new Map<string, AggregatedCustomer>();

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
