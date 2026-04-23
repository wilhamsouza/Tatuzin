import { Router } from 'express';

import { requirePlatformAdmin } from '../../../shared/http/auth-middleware';
import { asyncHandler } from '../../../shared/http/async-handler';
import { validateQuery } from '../../../shared/http/validate';
import {
  analyticsReportQuerySchema,
  type AnalyticsReportQueryInput,
} from './analytics-reports.schemas';
import { AnalyticsReportsService } from './analytics-reports.service';

const analyticsReportsService = new AnalyticsReportsService();

export const analyticsReportsRouter = Router();

analyticsReportsRouter.use(requirePlatformAdmin);

analyticsReportsRouter.get(
  '/sales-by-day',
  validateQuery(analyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getSalesByDay(
      request.query as unknown as AnalyticsReportQueryInput,
    );
    response.json(payload);
  }),
);

analyticsReportsRouter.get(
  '/sales-by-product',
  validateQuery(analyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getSalesByProduct(
      request.query as unknown as AnalyticsReportQueryInput,
    );
    response.json(payload);
  }),
);

analyticsReportsRouter.get(
  '/sales-by-customer',
  validateQuery(analyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getSalesByCustomer(
      request.query as unknown as AnalyticsReportQueryInput,
    );
    response.json(payload);
  }),
);

analyticsReportsRouter.get(
  '/cash-consolidated',
  validateQuery(analyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getCashConsolidated(
      request.query as unknown as AnalyticsReportQueryInput,
    );
    response.json(payload);
  }),
);

analyticsReportsRouter.get(
  '/financial-summary',
  validateQuery(analyticsReportQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsReportsService.getFinancialSummary(
      request.query as unknown as AnalyticsReportQueryInput,
    );
    response.json(payload);
  }),
);
