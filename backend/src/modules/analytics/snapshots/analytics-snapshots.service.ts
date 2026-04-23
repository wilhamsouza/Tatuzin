import type { Prisma } from '@prisma/client';

import { prisma } from '../../../database/prisma';
import { AppError } from '../../../shared/http/app-error';
import {
  formatUtcDateOnly,
  listUtcDaysInclusive,
  nextUtcDay,
  normalizeAnalyticsDateRange,
  startOfUtcDay,
  type AnalyticsDateRange,
} from '../analytics-period';
import type {
  AnalyticsSnapshotsMaterializeInput,
  AnalyticsSnapshotsQueryInput,
} from './analytics-snapshots.schemas';

type MaterializeInput = AnalyticsSnapshotsMaterializeInput | AnalyticsSnapshotsQueryInput;

type CompanySnapshotRow = Prisma.AnalyticsCompanyDailySnapshotGetPayload<object>;
type ProductSnapshotRow = Prisma.AnalyticsProductDailySnapshotGetPayload<object>;
type CustomerSnapshotRow = Prisma.AnalyticsCustomerDailySnapshotGetPayload<object>;

type SaleWithRelations = Prisma.SaleGetPayload<{
  select: {
    id: true;
    customerId: true;
    paymentType: true;
    status: true;
    totalAmountCents: true;
    totalCostCents: true;
    soldAt: true;
    customer: {
      select: {
        name: true;
      };
    };
    items: {
      select: {
        productId: true;
        productNameSnapshot: true;
        quantityMil: true;
        totalPriceCents: true;
        totalCostCents: true;
      };
    };
  };
}>;

type FiadoPaymentWithRelations = Prisma.FiadoPaymentGetPayload<{
  select: {
    amountCents: true;
    createdAt: true;
    sale: {
      select: {
        customerId: true;
        customer: {
          select: {
            name: true;
          };
        };
      };
    };
  };
}>;

type PurchaseSnapshotSource = {
  status: string;
  finalAmountCents: number;
  purchasedAt: Date;
};

type CashEventSnapshotSource = {
  eventType: string;
  amountCents: number;
  createdAt: Date;
};

type FinancialEventSnapshotSource = {
  eventType: string;
  amountCents: number;
  createdAt: Date;
};

type DailyAccumulator = {
  salesCount: number;
  customerIds: Set<string>;
  salesAmountCents: number;
  salesCostCents: number;
  salesProfitCents: number;
  fiadoSalesCount: number;
  fiadoPaymentsCount: number;
  fiadoPaymentsAmountCents: number;
  purchasesCount: number;
  purchasesAmountCents: number;
  cashInflowCents: number;
  cashOutflowCents: number;
  financialAdjustmentsCents: number;
};

type ProductAccumulator = {
  snapshotDate: Date;
  productKey: string;
  productId: string | null;
  productNameSnapshot: string;
  quantityMil: number;
  saleIds: Set<string>;
  revenueCents: number;
  costCents: number;
  profitCents: number;
};

type CustomerAccumulator = {
  snapshotDate: Date;
  customerKey: string;
  customerId: string | null;
  customerNameSnapshot: string;
  saleIds: Set<string>;
  revenueCents: number;
  costCents: number;
  profitCents: number;
  fiadoPaymentsCents: number;
};

export type AnalyticsSnapshotPeriodMeta = {
  startDate: string;
  endDate: string;
  dayCount: number;
};

export type AnalyticsSnapshotCoverage = {
  companyDailyRows: number;
  productDailyRows: number;
  customerDailyRows: number;
};

export type AnalyticsSnapshotMaterializationResult = {
  company: {
    id: string;
    name: string;
    slug: string;
  };
  period: AnalyticsSnapshotPeriodMeta;
  materializedAt: string;
  coverage: AnalyticsSnapshotCoverage;
};

export class AnalyticsSnapshotsService {
  async materializeCompanyRange(input: MaterializeInput) {
    const scope = await this.resolveScope(input);
    const shouldRebuild = await this.shouldRebuildRange(
      scope.company.id,
      scope.period,
      input.force === true,
    );

    if (shouldRebuild) {
      await this.rebuildRange(scope.company.id, scope.period);
    }

    const [companyDailyRows, productDailyRows, customerDailyRows, latestRow] =
      await Promise.all([
        prisma.analyticsCompanyDailySnapshot.count({
          where: {
            companyId: scope.company.id,
            snapshotDate: {
              gte: scope.period.startDate,
              lt: nextUtcDay(scope.period.endDate),
            },
          },
        }),
        prisma.analyticsProductDailySnapshot.count({
          where: {
            companyId: scope.company.id,
            snapshotDate: {
              gte: scope.period.startDate,
              lt: nextUtcDay(scope.period.endDate),
            },
          },
        }),
        prisma.analyticsCustomerDailySnapshot.count({
          where: {
            companyId: scope.company.id,
            snapshotDate: {
              gte: scope.period.startDate,
              lt: nextUtcDay(scope.period.endDate),
            },
          },
        }),
        prisma.analyticsCompanyDailySnapshot.findFirst({
          where: {
            companyId: scope.company.id,
            snapshotDate: {
              gte: scope.period.startDate,
              lt: nextUtcDay(scope.period.endDate),
            },
          },
          orderBy: [{ materializedAt: 'desc' }],
          select: {
            materializedAt: true,
          },
        }),
      ]);

    return {
      company: scope.company,
      period: this.toPeriodMeta(scope.period),
      materializedAt:
        latestRow?.materializedAt.toISOString() ?? new Date().toISOString(),
      coverage: {
        companyDailyRows,
        productDailyRows,
        customerDailyRows,
      },
    } satisfies AnalyticsSnapshotMaterializationResult;
  }

  async listCompanyDailySnapshots(input: AnalyticsSnapshotsQueryInput) {
    const materialization = await this.materializeCompanyRange(input);
    const snapshots = await prisma.analyticsCompanyDailySnapshot.findMany({
      where: {
        companyId: materialization.company.id,
        snapshotDate: {
          gte: parseSnapshotDate(materialization.period.startDate),
          lt: nextUtcDay(parseSnapshotDate(materialization.period.endDate)),
        },
      },
      orderBy: [{ snapshotDate: 'asc' }],
    });

    return {
      ...materialization,
      snapshots: snapshots.map((snapshot) => this.toCompanyDailySnapshotDto(snapshot)),
    };
  }

  async loadCompanyDailySnapshotRows(
    companyId: string,
    period: AnalyticsDateRange,
  ) {
    return prisma.analyticsCompanyDailySnapshot.findMany({
      where: {
        companyId,
        snapshotDate: {
          gte: period.startDate,
          lt: nextUtcDay(period.endDate),
        },
      },
      orderBy: [{ snapshotDate: 'asc' }],
    });
  }

  async loadProductDailySnapshotRows(
    companyId: string,
    period: AnalyticsDateRange,
  ) {
    return prisma.analyticsProductDailySnapshot.findMany({
      where: {
        companyId,
        snapshotDate: {
          gte: period.startDate,
          lt: nextUtcDay(period.endDate),
        },
      },
      orderBy: [{ revenueCents: 'desc' }, { productNameSnapshot: 'asc' }],
    });
  }

  async loadCustomerDailySnapshotRows(
    companyId: string,
    period: AnalyticsDateRange,
  ) {
    return prisma.analyticsCustomerDailySnapshot.findMany({
      where: {
        companyId,
        snapshotDate: {
          gte: period.startDate,
          lt: nextUtcDay(period.endDate),
        },
      },
      orderBy: [{ revenueCents: 'desc' }, { customerNameSnapshot: 'asc' }],
    });
  }

  resolvePeriod(input: Pick<MaterializeInput, 'startDate' | 'endDate'>) {
    return normalizeAnalyticsDateRange({
      startDate: input.startDate,
      endDate: input.endDate,
      defaultDays: 30,
      maxDays: 180,
    });
  }

  toCompanyDailySnapshotDto(snapshot: CompanySnapshotRow) {
    return {
      date: formatUtcDateOnly(snapshot.snapshotDate),
      salesCount: snapshot.salesCount,
      customersServedCount: snapshot.customersServedCount,
      salesAmountCents: snapshot.salesAmountCents,
      salesCostCents: snapshot.salesCostCents,
      salesProfitCents: snapshot.salesProfitCents,
      fiadoSalesCount: snapshot.fiadoSalesCount,
      fiadoPaymentsCount: snapshot.fiadoPaymentsCount,
      fiadoPaymentsAmountCents: snapshot.fiadoPaymentsAmountCents,
      purchasesCount: snapshot.purchasesCount,
      purchasesAmountCents: snapshot.purchasesAmountCents,
      cashInflowCents: snapshot.cashInflowCents,
      cashOutflowCents: snapshot.cashOutflowCents,
      cashNetCents: snapshot.cashNetCents,
      financialAdjustmentsCents: snapshot.financialAdjustmentsCents,
      materializedAt: snapshot.materializedAt.toISOString(),
    };
  }

  toProductDailySnapshotDto(snapshot: ProductSnapshotRow) {
    return {
      date: formatUtcDateOnly(snapshot.snapshotDate),
      productKey: snapshot.productKey,
      productId: snapshot.productId,
      productName: snapshot.productNameSnapshot,
      quantityMil: snapshot.quantityMil,
      salesCount: snapshot.salesCount,
      revenueCents: snapshot.revenueCents,
      costCents: snapshot.costCents,
      profitCents: snapshot.profitCents,
      materializedAt: snapshot.materializedAt.toISOString(),
    };
  }

  toCustomerDailySnapshotDto(snapshot: CustomerSnapshotRow) {
    return {
      date: formatUtcDateOnly(snapshot.snapshotDate),
      customerKey: snapshot.customerKey,
      customerId: snapshot.customerId,
      customerName: snapshot.customerNameSnapshot,
      salesCount: snapshot.salesCount,
      revenueCents: snapshot.revenueCents,
      costCents: snapshot.costCents,
      profitCents: snapshot.profitCents,
      fiadoPaymentsCents: snapshot.fiadoPaymentsCents,
      materializedAt: snapshot.materializedAt.toISOString(),
    };
  }

  private async resolveScope(input: MaterializeInput) {
    const company = await prisma.company.findUnique({
      where: { id: input.companyId },
      select: {
        id: true,
        name: true,
        slug: true,
      },
    });

    if (!company) {
      throw new AppError(
        'Empresa nao encontrada para analytics.',
        404,
        'ANALYTICS_COMPANY_NOT_FOUND',
      );
    }

    try {
      const period = this.resolvePeriod(input);
      return { company, period };
    } catch (error) {
      if (error instanceof RangeError) {
        if (error.message === 'ANALYTICS_INVALID_DATE_RANGE') {
          throw new AppError(
            'O intervalo solicitado para analytics e invalido.',
            400,
            'ANALYTICS_INVALID_DATE_RANGE',
          );
        }
        if (error.message === 'ANALYTICS_RANGE_TOO_LARGE') {
          throw new AppError(
            'O intervalo solicitado para analytics excede o limite desta versao.',
            400,
            'ANALYTICS_RANGE_TOO_LARGE',
          );
        }
      }

      throw error;
    }
  }

  private async shouldRebuildRange(
    companyId: string,
    period: AnalyticsDateRange,
    force: boolean,
  ) {
    if (force) {
      return true;
    }

    const summary = await prisma.analyticsCompanyDailySnapshot.aggregate({
      where: {
        companyId,
        snapshotDate: {
          gte: period.startDate,
          lt: nextUtcDay(period.endDate),
        },
      },
      _count: {
        _all: true,
      },
      _max: {
        materializedAt: true,
      },
    });

    const today = formatUtcDateOnly(startOfUtcDay(new Date()));
    const includesToday =
      period.startDateLabel <= today && period.endDateLabel >= today;
    const lastMaterializedAt = summary._max.materializedAt;
    const isFreshEnough =
      lastMaterializedAt != null &&
      Date.now() - lastMaterializedAt.getTime() < 15 * 60 * 1000;

    if (summary._count._all !== period.dayCount) {
      return true;
    }

    if (includesToday) {
      return true;
    }

    return !isFreshEnough;
  }

  private async rebuildRange(companyId: string, period: AnalyticsDateRange) {
    const endExclusive = nextUtcDay(period.endDate);
    const [sales, purchases, cashEvents, financialEvents, fiadoPayments] =
      await Promise.all([
        prisma.sale.findMany({
          where: {
            companyId,
            soldAt: {
              gte: period.startDate,
              lt: endExclusive,
            },
          },
          select: {
            id: true,
            customerId: true,
            paymentType: true,
            status: true,
            totalAmountCents: true,
            totalCostCents: true,
            soldAt: true,
            customer: {
              select: {
                name: true,
              },
            },
            items: {
              select: {
                productId: true,
                productNameSnapshot: true,
                quantityMil: true,
                totalPriceCents: true,
                totalCostCents: true,
              },
            },
          },
        }),
        prisma.purchase.findMany({
          where: {
            companyId,
            purchasedAt: {
              gte: period.startDate,
              lt: endExclusive,
            },
          },
          select: {
            status: true,
            finalAmountCents: true,
            purchasedAt: true,
          },
        }),
        prisma.cashEvent.findMany({
          where: {
            companyId,
            createdAt: {
              gte: period.startDate,
              lt: endExclusive,
            },
          },
          select: {
            eventType: true,
            amountCents: true,
            createdAt: true,
          },
        }),
        prisma.financialEvent.findMany({
          where: {
            companyId,
            createdAt: {
              gte: period.startDate,
              lt: endExclusive,
            },
          },
          select: {
            eventType: true,
            amountCents: true,
            createdAt: true,
          },
        }),
        prisma.fiadoPayment.findMany({
          where: {
            companyId,
            createdAt: {
              gte: period.startDate,
              lt: endExclusive,
            },
          },
          select: {
            amountCents: true,
            createdAt: true,
            sale: {
              select: {
                customerId: true,
                customer: {
                  select: {
                    name: true,
                  },
                },
              },
            },
          },
        }),
      ]);

    const materializedAt = new Date();
    const dailyAccumulators = new Map<string, DailyAccumulator>();
    const productAccumulators = new Map<string, ProductAccumulator>();
    const customerAccumulators = new Map<string, CustomerAccumulator>();

    for (const finalDate of listUtcDaysInclusive(period.startDate, period.endDate)) {
      dailyAccumulators.set(formatUtcDateOnly(finalDate), createDailyAccumulator());
    }

    for (const sale of sales) {
      if (sale.status !== 'active') {
        continue;
      }

      const dayKey = formatUtcDateOnly(sale.soldAt);
      const daily = dailyAccumulators.get(dayKey);
      if (!daily) {
        continue;
      }

      daily.salesCount += 1;
      daily.salesAmountCents += sale.totalAmountCents;
      daily.salesCostCents += sale.totalCostCents;
      daily.salesProfitCents += sale.totalAmountCents - sale.totalCostCents;
      if (sale.paymentType === 'fiado') {
        daily.fiadoSalesCount += 1;
      }
      if (sale.customerId != null) {
        daily.customerIds.add(sale.customerId);
        const customerKey = sale.customerId;
        const snapshotDate = parseSnapshotDate(dayKey);
        const accumulatorKey = `${dayKey}:${customerKey}`;
        const customer = ensureCustomerAccumulator(
          customerAccumulators,
          accumulatorKey,
          {
            snapshotDate,
            customerKey,
            customerId: sale.customerId,
            customerNameSnapshot:
              normalizeSnapshotName(sale.customer?.name) ?? 'Cliente identificado',
          },
        );
        customer.saleIds.add(sale.id);
        customer.revenueCents += sale.totalAmountCents;
        customer.costCents += sale.totalCostCents;
        customer.profitCents += sale.totalAmountCents - sale.totalCostCents;
      }

      for (const item of sale.items) {
        const snapshotDate = parseSnapshotDate(dayKey);
        const productKey =
          item.productId ?? buildNameKey('product', item.productNameSnapshot);
        const accumulatorKey = `${dayKey}:${productKey}`;
        const product = ensureProductAccumulator(
          productAccumulators,
          accumulatorKey,
          {
            snapshotDate,
            productKey,
            productId: item.productId,
            productNameSnapshot: normalizeSnapshotName(item.productNameSnapshot) ?? 'Produto',
          },
        );
        product.saleIds.add(sale.id);
        product.quantityMil += item.quantityMil;
        product.revenueCents += item.totalPriceCents;
        product.costCents += item.totalCostCents;
        product.profitCents += item.totalPriceCents - item.totalCostCents;
      }
    }

    for (const purchase of purchases) {
      if (purchase.status === 'cancelada') {
        continue;
      }

      const daily = dailyAccumulators.get(formatUtcDateOnly(purchase.purchasedAt));
      if (!daily) {
        continue;
      }

      daily.purchasesCount += 1;
      daily.purchasesAmountCents += purchase.finalAmountCents;
    }

    for (const cashEvent of cashEvents) {
      const daily = dailyAccumulators.get(formatUtcDateOnly(cashEvent.createdAt));
      if (!daily) {
        continue;
      }

      switch (cashEvent.eventType) {
        case 'entrada':
        case 'fiado_pagamento':
          daily.cashInflowCents += cashEvent.amountCents;
          break;
        case 'saida':
        case 'retirada':
          daily.cashOutflowCents += cashEvent.amountCents;
          break;
        default:
          break;
      }
    }

    for (const financialEvent of financialEvents) {
      const daily = dailyAccumulators.get(
        formatUtcDateOnly(financialEvent.createdAt),
      );
      if (!daily) {
        continue;
      }

      switch (financialEvent.eventType) {
        case 'fiado_payment':
          daily.financialAdjustmentsCents += financialEvent.amountCents;
          break;
        case 'sale_canceled':
          daily.financialAdjustmentsCents -= financialEvent.amountCents;
          break;
        default:
          break;
      }
    }

    for (const payment of fiadoPayments) {
      const dayKey = formatUtcDateOnly(payment.createdAt);
      const daily = dailyAccumulators.get(dayKey);
      if (!daily) {
        continue;
      }

      daily.fiadoPaymentsCount += 1;
      daily.fiadoPaymentsAmountCents += payment.amountCents;

      if (payment.sale.customerId != null) {
        const customerKey = payment.sale.customerId;
        const snapshotDate = parseSnapshotDate(dayKey);
        const accumulatorKey = `${dayKey}:${customerKey}`;
        const customer = ensureCustomerAccumulator(
          customerAccumulators,
          accumulatorKey,
          {
            snapshotDate,
            customerKey,
            customerId: payment.sale.customerId,
            customerNameSnapshot:
              normalizeSnapshotName(payment.sale.customer?.name) ??
              'Cliente identificado',
          },
        );
        customer.fiadoPaymentsCents += payment.amountCents;
      }
    }

    const companyRows = listUtcDaysInclusive(period.startDate, period.endDate).map(
      (date) => {
        const dayKey = formatUtcDateOnly(date);
        const daily = dailyAccumulators.get(dayKey) ?? createDailyAccumulator();
        return {
          companyId,
          snapshotDate: date,
          salesCount: daily.salesCount,
          customersServedCount: daily.customerIds.size,
          salesAmountCents: daily.salesAmountCents,
          salesCostCents: daily.salesCostCents,
          salesProfitCents: daily.salesProfitCents,
          fiadoSalesCount: daily.fiadoSalesCount,
          fiadoPaymentsCount: daily.fiadoPaymentsCount,
          fiadoPaymentsAmountCents: daily.fiadoPaymentsAmountCents,
          purchasesCount: daily.purchasesCount,
          purchasesAmountCents: daily.purchasesAmountCents,
          cashInflowCents: daily.cashInflowCents,
          cashOutflowCents: daily.cashOutflowCents,
          cashNetCents: daily.cashInflowCents - daily.cashOutflowCents,
          financialAdjustmentsCents: daily.financialAdjustmentsCents,
          materializedAt,
        };
      },
    );

    const productRows = [...productAccumulators.values()].map((row) => ({
      companyId,
      snapshotDate: row.snapshotDate,
      productKey: row.productKey,
      productId: row.productId,
      productNameSnapshot: row.productNameSnapshot,
      quantityMil: row.quantityMil,
      salesCount: row.saleIds.size,
      revenueCents: row.revenueCents,
      costCents: row.costCents,
      profitCents: row.profitCents,
      materializedAt,
    }));

    const customerRows = [...customerAccumulators.values()].map((row) => ({
      companyId,
      snapshotDate: row.snapshotDate,
      customerKey: row.customerKey,
      customerId: row.customerId,
      customerNameSnapshot: row.customerNameSnapshot,
      salesCount: row.saleIds.size,
      revenueCents: row.revenueCents,
      costCents: row.costCents,
      profitCents: row.profitCents,
      fiadoPaymentsCents: row.fiadoPaymentsCents,
      materializedAt,
    }));

    await prisma.$transaction(async (tx) => {
      const rangeWhere = {
        companyId,
        snapshotDate: {
          gte: period.startDate,
          lt: endExclusive,
        },
      };

      await tx.analyticsCompanyDailySnapshot.deleteMany({
        where: rangeWhere,
      });
      await tx.analyticsProductDailySnapshot.deleteMany({
        where: rangeWhere,
      });
      await tx.analyticsCustomerDailySnapshot.deleteMany({
        where: rangeWhere,
      });

      if (companyRows.length > 0) {
        await tx.analyticsCompanyDailySnapshot.createMany({
          data: companyRows,
        });
      }
      if (productRows.length > 0) {
        await tx.analyticsProductDailySnapshot.createMany({
          data: productRows,
        });
      }
      if (customerRows.length > 0) {
        await tx.analyticsCustomerDailySnapshot.createMany({
          data: customerRows,
        });
      }
    });
  }

  private toPeriodMeta(period: AnalyticsDateRange): AnalyticsSnapshotPeriodMeta {
    return {
      startDate: period.startDateLabel,
      endDate: period.endDateLabel,
      dayCount: period.dayCount,
    };
  }
}

function createDailyAccumulator(): DailyAccumulator {
  return {
    salesCount: 0,
    customerIds: new Set<string>(),
    salesAmountCents: 0,
    salesCostCents: 0,
    salesProfitCents: 0,
    fiadoSalesCount: 0,
    fiadoPaymentsCount: 0,
    fiadoPaymentsAmountCents: 0,
    purchasesCount: 0,
    purchasesAmountCents: 0,
    cashInflowCents: 0,
    cashOutflowCents: 0,
    financialAdjustmentsCents: 0,
  };
}

function ensureProductAccumulator(
  map: Map<string, ProductAccumulator>,
  key: string,
  seed: Pick<
    ProductAccumulator,
    'snapshotDate' | 'productKey' | 'productId' | 'productNameSnapshot'
  >,
) {
  let accumulator = map.get(key);
  if (accumulator == null) {
    accumulator = {
      ...seed,
      quantityMil: 0,
      saleIds: new Set<string>(),
      revenueCents: 0,
      costCents: 0,
      profitCents: 0,
    };
    map.set(key, accumulator);
  }
  return accumulator;
}

function ensureCustomerAccumulator(
  map: Map<string, CustomerAccumulator>,
  key: string,
  seed: Pick<
    CustomerAccumulator,
    'snapshotDate' | 'customerKey' | 'customerId' | 'customerNameSnapshot'
  >,
) {
  let accumulator = map.get(key);
  if (accumulator == null) {
    accumulator = {
      ...seed,
      saleIds: new Set<string>(),
      revenueCents: 0,
      costCents: 0,
      profitCents: 0,
      fiadoPaymentsCents: 0,
    };
    map.set(key, accumulator);
  }
  return accumulator;
}

function normalizeSnapshotName(value: string | null | undefined) {
  const normalized = value?.trim();
  return normalized == null || normalized.length === 0 ? null : normalized;
}

function buildNameKey(prefix: string, rawName: string) {
  const normalized = rawName
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
  return `${prefix}:${normalized.length === 0 ? 'sem-nome' : normalized}`;
}

function parseSnapshotDate(value: string) {
  return new Date(`${value}T00:00:00.000Z`);
}
