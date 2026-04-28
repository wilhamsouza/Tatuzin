import { Router } from 'express';

import { requireCloudLicense } from '../../../shared/http/auth-middleware';
import { asyncHandler } from '../../../shared/http/async-handler';
import { validateQuery } from '../../../shared/http/validate';
import { AnalyticsReportsService } from './analytics-reports.service';
import {
  tenantAnalyticsReportQuerySchema,
  type TenantAnalyticsReportQueryInput,
} from './tenant-analytics-reports.schemas';

const analyticsReportsService = new AnalyticsReportsService();

export const tenantAnalyticsReportsRouter = Router();

tenantAnalyticsReportsRouter.use(requireCloudLicense);

tenantAnalyticsReportsRouter.get(
  '/cash-consolidated',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getCashConsolidated(
      withTenantCompany(request.query as unknown as TenantAnalyticsReportQueryInput, request.auth!.companyId),
    );
    response.json(withTenantMaterialization(payload));
  }),
);

tenantAnalyticsReportsRouter.get(
  '/financial-summary',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getFinancialSummary(
      withTenantCompany(request.query as unknown as TenantAnalyticsReportQueryInput, request.auth!.companyId),
    );
    response.json(withTenantMaterialization(payload));
  }),
);

tenantAnalyticsReportsRouter.get(
  '/sales-by-day',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as TenantAnalyticsReportQueryInput;
    const payload = await analyticsReportsService.getSalesByDay(
      withTenantCompany(query, request.auth!.companyId),
    );
    response.json(
      withTenantMaterialization({
        ...payload,
        series: groupSalesSeries(payload.series, query.grouping),
      }),
    );
  }),
);

tenantAnalyticsReportsRouter.get(
  '/sales-by-product',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as TenantAnalyticsReportQueryInput;
    const payload = await analyticsReportsService.getSalesByProductForTenant(
      withTenantCompany(query, request.auth!.companyId),
      {
        productId: query.productId,
        categoryId: query.categoryId,
      },
    );
    response.json(withTenantMaterialization(payload));
  }),
);

tenantAnalyticsReportsRouter.get(
  '/sales-by-customer',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as TenantAnalyticsReportQueryInput;
    const payload = await analyticsReportsService.getSalesByCustomerForTenant(
      withTenantCompany(query, request.auth!.companyId),
      { customerId: query.customerId },
    );
    response.json(withTenantMaterialization(payload));
  }),
);

tenantAnalyticsReportsRouter.get(
  '/top-variants',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (_request, response) => {
    response.json({
      partial: true,
      reason: 'variant_sales_snapshot_unavailable',
      totals: {
        salesCount: 0,
        quantityMil: 0,
        revenueCents: 0,
        costCents: 0,
        profitCents: 0,
      },
      items: [],
    });
  }),
);

tenantAnalyticsReportsRouter.get(
  '/profitability',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as TenantAnalyticsReportQueryInput;
    const payload = await analyticsReportsService.getProfitabilityForTenant(
      withTenantCompany(query, request.auth!.companyId),
      {
        productId: query.productId,
        categoryId: query.categoryId,
      },
    );
    response.json(withTenantMaterialization(payload));
  }),
);

tenantAnalyticsReportsRouter.get(
  '/purchases',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as TenantAnalyticsReportQueryInput;
    const payload = await analyticsReportsService.getPurchasesForTenant(
      withTenantCompany(query, request.auth!.companyId),
      { supplierId: query.supplierId },
    );
    response.json(withTenantMaterialization(payload));
  }),
);

tenantAnalyticsReportsRouter.get(
  '/inventory',
  validateQuery(tenantAnalyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getInventoryForTenant(
      request.auth!.companyId,
    );
    response.json(payload);
  }),
);

function withTenantCompany(
  query: TenantAnalyticsReportQueryInput,
  companyId: string,
) {
  return {
    companyId,
    startDate: query.startDate,
    endDate: query.endDate,
    topN: query.topN,
    force: query.force,
  };
}

function withTenantMaterialization<T extends Record<string, unknown>>(
  payload: T,
) {
  const materialization = payload.materialization;
  if (materialization == null || typeof materialization !== 'object') {
    return payload;
  }
  const materializedAt = (materialization as { materializedAt?: unknown })
    .materializedAt;
  return {
    ...payload,
    materialization: {
      ...materialization,
      source: 'snapshot_or_live',
      generatedAt:
        typeof materializedAt === 'string'
          ? materializedAt
          : new Date().toISOString(),
    },
  };
}

function groupSalesSeries(
  series: Array<{
    date: string;
    salesCount: number;
    salesAmountCents: number;
    salesCostCents: number;
    salesProfitCents: number;
  }>,
  grouping: TenantAnalyticsReportQueryInput['grouping'],
) {
  if (grouping === 'day') {
    return series;
  }

  const grouped = new Map<string, (typeof series)[number]>();
  for (const point of series) {
    const key = grouping === 'week' ? weekKey(point.date) : monthKey(point.date);
    const current = grouped.get(key) ?? {
      date: key,
      salesCount: 0,
      salesAmountCents: 0,
      salesCostCents: 0,
      salesProfitCents: 0,
    };
    current.salesCount += point.salesCount;
    current.salesAmountCents += point.salesAmountCents;
    current.salesCostCents += point.salesCostCents;
    current.salesProfitCents += point.salesProfitCents;
    grouped.set(key, current);
  }

  return [...grouped.values()].sort((left, right) =>
    left.date.localeCompare(right.date),
  );
}

function monthKey(date: string) {
  return `${date.slice(0, 7)}-01`;
}

function weekKey(date: string) {
  const value = new Date(`${date}T00:00:00.000Z`);
  const day = value.getUTCDay() === 0 ? 7 : value.getUTCDay();
  value.setUTCDate(value.getUTCDate() - day + 1);
  return value.toISOString().slice(0, 10);
}
