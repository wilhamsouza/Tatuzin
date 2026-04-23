import { Router } from 'express';

import { requirePlatformAdmin } from '../../../shared/http/auth-middleware';
import { asyncHandler } from '../../../shared/http/async-handler';
import { validateQuery } from '../../../shared/http/validate';
import {
  analyticsDashboardQuerySchema,
  type AnalyticsDashboardQueryInput,
} from './analytics-dashboard.schemas';
import { AnalyticsDashboardService } from './analytics-dashboard.service';

const analyticsDashboardService = new AnalyticsDashboardService();

export const analyticsDashboardRouter = Router();

analyticsDashboardRouter.use(requirePlatformAdmin);

analyticsDashboardRouter.get(
  '/',
  validateQuery(analyticsDashboardQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsDashboardService.getDashboard(
      request.query as unknown as AnalyticsDashboardQueryInput,
    );
    response.json(payload);
  }),
);
