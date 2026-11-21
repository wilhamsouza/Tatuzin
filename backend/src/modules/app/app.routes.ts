import { CashWorkspaceService, workspaceOpenSchema, workspaceJoinSchema, workspaceCloseSchema, workspaceAckSchema } from "../cash/cash-workspace.service";
import { z } from "zod";
import { Router } from 'express';

import {
  requireAppContext,
  requireTenantOperational,
} from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { appSnapshotQuerySchema } from '../sync/sync.schemas';
import { AppBootstrapService } from './app-bootstrap.service';
import { AppContextService } from './app-context.service';
import { AppSnapshotService } from './app-snapshot.service';
import { deviceRegisterSchema } from './app.schemas';
import { companyReceiptSettingsPatchSchema } from './company-settings.schemas';
import { CompanySettingsService } from './company-settings.service';
import { CompanyDeviceService } from './company-device.service';
import { CompanyOnboardingService } from './company-onboarding.service';

const appBootstrapService = new AppBootstrapService();
const appContextService = new AppContextService();
const appSnapshotService = new AppSnapshotService();
const companySettingsService = new CompanySettingsService();
const companyDeviceService = new CompanyDeviceService();
const companyOnboardingService = new CompanyOnboardingService();

export const appRouter = Router();

appRouter.post('/onboarding/reconcile', requireAppContext,
  asyncHandler(async (request, response) => {
    response.json(await companyOnboardingService.reconcile(request.appContext!));
  }));

appRouter.post(
  '/device',
  requireTenantOperational,
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
  '/company/settings',
  requireAppContext,
  asyncHandler(async (request, response) => {
    response.json(
      await companySettingsService.getReceiptSettings(request.appContext!),
    );
  }),
);

appRouter.patch(
  '/company/settings',
  requireAppContext,
  validateBody(companyReceiptSettingsPatchSchema),
  asyncHandler(async (request, response) => {
    response.json(
      await companySettingsService.updateReceiptSettings(
        request.appContext!,
        request.body,
      ),
    );
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

const cashWorkspaceService = new CashWorkspaceService();
const cashUuid = (value: unknown) => z.string().uuid().parse(value);
appRouter.get('/cash/workspace', requireAppContext, asyncHandler(async(request,response)=>{response.json(await cashWorkspaceService.get(request.appContext!));}));
appRouter.post('/cash/sessions/open', requireAppContext, validateBody(workspaceOpenSchema), asyncHandler(async(request,response)=>{response.json(await cashWorkspaceService.open(request.appContext!,request.body));}));
appRouter.post('/cash/sessions/:uuid/join', requireAppContext, validateBody(workspaceJoinSchema), asyncHandler(async(request,response)=>{response.json(await cashWorkspaceService.join(request.appContext!,cashUuid(request.params.uuid),request.body));}));
appRouter.post('/cash/sessions/:uuid/closure-requests', requireAppContext, validateBody(workspaceCloseSchema), asyncHandler(async(request,response)=>{response.json(await cashWorkspaceService.requestClosure(request.appContext!,cashUuid(request.params.uuid),request.body));}));
appRouter.post('/cash/sessions/:uuid/closure-requests/:requestId/ack', requireAppContext, validateBody(workspaceAckSchema), asyncHandler(async(request,response)=>{response.json(await cashWorkspaceService.acknowledge(request.appContext!,cashUuid(request.params.uuid),cashUuid(request.params.requestId),request.body));}));
appRouter.post('/cash/sessions/:uuid/closure-requests/:requestId/reconfirm', requireAppContext, validateBody(workspaceCloseSchema), asyncHandler(async(request,response)=>{response.json(await cashWorkspaceService.requestClosure(request.appContext!,cashUuid(request.params.uuid),request.body,cashUuid(request.params.requestId)));}));
