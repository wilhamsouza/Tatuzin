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
