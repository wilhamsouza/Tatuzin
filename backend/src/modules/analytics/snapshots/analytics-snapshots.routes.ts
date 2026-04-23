import { Router } from 'express';

import { requirePlatformAdmin } from '../../../shared/http/auth-middleware';
import { asyncHandler } from '../../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../../shared/http/validate';
import {
  analyticsSnapshotsMaterializeSchema,
  analyticsSnapshotsQuerySchema,
  type AnalyticsSnapshotsMaterializeInput,
  type AnalyticsSnapshotsQueryInput,
} from './analytics-snapshots.schemas';
import { AnalyticsSnapshotsService } from './analytics-snapshots.service';

const analyticsSnapshotsService = new AnalyticsSnapshotsService();

export const analyticsSnapshotsRouter = Router();

analyticsSnapshotsRouter.use(requirePlatformAdmin);

analyticsSnapshotsRouter.get(
  '/',
  validateQuery(analyticsSnapshotsQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsSnapshotsService.listCompanyDailySnapshots(
      request.query as unknown as AnalyticsSnapshotsQueryInput,
    );
    response.json(payload);
  }),
);

analyticsSnapshotsRouter.post(
  '/materialize',
  validateBody(analyticsSnapshotsMaterializeSchema),
  asyncHandler(async (request, response) => {
    const payload = await analyticsSnapshotsService.materializeCompanyRange(
      request.body as AnalyticsSnapshotsMaterializeInput,
    );
    response.status(202).json(payload);
  }),
);
