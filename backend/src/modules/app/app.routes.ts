import { Router } from 'express';

import {
  requireAppContext,
  requireAuth,
} from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { appSnapshotQuerySchema } from '../sync/sync.schemas';
import { AppBootstrapService } from './app-bootstrap.service';
import { AppContextService } from './app-context.service';
import { AppSnapshotService } from './app-snapshot.service';
import { deviceRegisterSchema } from './app.schemas';
import { CompanyDeviceService } from './company-device.service';

const appBootstrapService = new AppBootstrapService();
const appContextService = new AppContextService();
const appSnapshotService = new AppSnapshotService();
const companyDeviceService = new CompanyDeviceService();

export const appRouter = Router();

appRouter.post(
  '/device',
  requireAuth,
  validateBody(deviceRegisterSchema),
  asyncHandler(async (request, response) => {
    const auth = request.auth!;
    const device = await companyDeviceService.resolveForAuthenticatedUser({
      userId: auth.userId,
      companyId: auth.companyId,
      membershipId: auth.membershipId,
      membershipRole: auth.membershipRole,
      clientInstanceId: request.body.clientInstanceId,
      deviceLabel: request.body.deviceLabel,
      platform: request.body.platform,
      appVersion: request.body.appVersion,
    });

    response.json({
      device: {
        id: device.id,
        clientInstanceId: device.clientInstanceId,
        status: device.status,
        deviceLabel: device.deviceLabel,
        platform: device.platform,
        appVersion: device.appVersion,
        lastSeenAt: device.lastSeenAt,
      },
    });
  }),
);

appRouter.get(
  '/bootstrap',
  requireAppContext,
  asyncHandler(async (request, response) => {
    const payload = appBootstrapService.buildPayload(request.appContext!);
    appContextService.logBootstrapOutcome({
      appContext: request.appContext!,
    });
    response.json(payload);
  }),
);

appRouter.get(
  '/snapshot',
  requireAppContext,
  validateQuery(appSnapshotQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await appSnapshotService.buildSnapshot({
      context: request.appContext!,
      features: (request.query as unknown as { features: string[] }).features,
    });
    response.json(payload);
  }),
);
