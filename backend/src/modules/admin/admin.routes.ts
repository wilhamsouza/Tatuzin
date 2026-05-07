import { Router } from 'express';

import {
  requirePlatformAdmin,
} from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { createRateLimit } from '../../shared/http/rate-limit';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  type AdminBillingCompaniesQueryInput,
  type AdminBillingListQueryInput,
  adminBillingCancelLocalSchema,
  adminBillingCompaniesQuerySchema,
  adminBillingForcePlanSchema,
  adminBillingListQuerySchema,
  adminBillingRefreshSchema,
} from '../billing/billing-admin.schemas';
import { BillingAdminService } from '../billing/billing-admin.service';
import {
  type AdminAuditQueryInput,
  type AdminCompanySyncConflictsQueryInput,
  type AdminCompanySyncEventsQueryInput,
  type AdminCompanySyncIncidentsQueryInput,
  type AdminCompaniesQueryInput,
  type AdminLicensesQueryInput,
  type AdminSyncOperationalQueryInput,
  type AdminSyncQueryInput,
  adminCompanySyncConflictsQuerySchema,
  adminCompanySyncEventsQuerySchema,
  adminCompanySyncIncidentsQuerySchema,
  adminAuditQuerySchema,
  adminCompaniesQuerySchema,
  adminLicensePatchSchema,
  adminLicensesQuerySchema,
  adminSyncOperationalQuerySchema,
  adminSyncQuerySchema,
} from './admin.schemas';
import { AdminSyncHealthService } from './admin-sync-health.service';
import { AdminService } from './admin.service';

const adminService = new AdminService();
const adminSyncHealthService = new AdminSyncHealthService();
const billingAdminService = new BillingAdminService();

export const adminRouter = Router();

adminRouter.use(requirePlatformAdmin);
adminRouter.use(
  createRateLimit({
    name: 'platform_admin',
    windowMs: 60_000,
    max: 240,
    message:
      'Muitas operacoes administrativas em pouco tempo. Aguarde um instante e tente novamente.',
    code: 'ADMIN_RATE_LIMITED',
    keyGenerator(request) {
      return request.auth?.userId ?? request.ip ?? 'unknown-admin';
    },
  }),
);

adminRouter.get(
  '/billing/companies',
  validateQuery(adminBillingCompaniesQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await billingAdminService.listCompanies(
      request.query as unknown as AdminBillingCompaniesQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies',
  validateQuery(adminCompaniesQuerySchema),
  asyncHandler(async (request, response) => {
    const companies = await adminService.listCompanies(
      request.query as unknown as AdminCompaniesQueryInput,
    );
    response.json(companies);
  }),
);

adminRouter.get(
  '/companies/:id',
  asyncHandler(async (request, response) => {
    const companyId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await adminService.getCompany(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/sync/health',
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.getHealth(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/sync/events',
  validateQuery(adminCompanySyncEventsQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.listEvents(
      companyId,
      request.query as unknown as AdminCompanySyncEventsQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/sync/conflicts',
  validateQuery(adminCompanySyncConflictsQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.listConflicts(
      companyId,
      request.query as unknown as AdminCompanySyncConflictsQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/sync/incidents',
  validateQuery(adminCompanySyncIncidentsQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.listIncidents(
      companyId,
      request.query as unknown as AdminCompanySyncIncidentsQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/devices',
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.listDevices(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/billing/status',
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.getStatus(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/billing/events',
  validateQuery(adminBillingListQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.listEvents(
      companyId,
      request.query as unknown as AdminBillingListQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  '/companies/:companyId/billing/checkout-sessions',
  validateQuery(adminBillingListQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.listCheckoutSessions(
      companyId,
      request.query as unknown as AdminBillingListQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  '/companies/:companyId/billing/refresh',
  validateBody(adminBillingRefreshSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.refreshCompany({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get('user-agent') ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  '/companies/:companyId/billing/force-plan',
  validateBody(adminBillingForcePlanSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.forcePlan({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get('user-agent') ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  '/companies/:companyId/billing/cancel-local',
  validateBody(adminBillingCancelLocalSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.cancelLocal({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get('user-agent') ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  '/sessions/:sessionId/revoke',
  asyncHandler(async (request, response) => {
    const sessionId = Array.isArray(request.params.sessionId)
      ? request.params.sessionId[0]
      : request.params.sessionId;

    await adminService.revokeSession({
      sessionId,
      actorUserId: request.auth!.userId,
    });

    response.status(204).send();
  }),
);

adminRouter.patch(
  '/companies/:id/license',
  validateBody(adminLicensePatchSchema),
  asyncHandler(async (request, response) => {
    const companyId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const license = await adminService.updateLicense(
      companyId,
      request.body,
      request.auth!.userId,
    );
    response.json({ license });
  }),
);

adminRouter.get(
  '/licenses',
  validateQuery(adminLicensesQuerySchema),
  asyncHandler(async (request, response) => {
    const licenses = await adminService.listLicenses(
      request.query as unknown as AdminLicensesQueryInput,
    );
    response.json(licenses);
  }),
);

adminRouter.get(
  '/licenses/:companyId',
  asyncHandler(async (request, response) => {
    const companyId = Array.isArray(request.params.companyId)
      ? request.params.companyId[0]
      : request.params.companyId;
    const license = await adminService.getLicense(companyId);
    response.json({ license });
  }),
);

adminRouter.patch(
  '/licenses/:companyId',
  validateBody(adminLicensePatchSchema),
  asyncHandler(async (request, response) => {
    const companyId = Array.isArray(request.params.companyId)
      ? request.params.companyId[0]
      : request.params.companyId;
    const license = await adminService.updateLicense(
      companyId,
      request.body,
      request.auth!.userId,
    );
    response.json({ license });
  }),
);

adminRouter.get(
  '/audit/summary',
  validateQuery(adminAuditQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await adminService.getAuditSummary(
      request.query as unknown as AdminAuditQueryInput,
    );
    response.json(summary);
  }),
);

function readParam(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

adminRouter.get(
  '/sync/summary',
  validateQuery(adminSyncQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await adminService.getSyncSummary(
      request.query as unknown as AdminSyncQueryInput,
    );
    response.json(summary);
  }),
);

adminRouter.get(
  '/sync/operational-summary',
  validateQuery(adminSyncOperationalQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await adminService.getSyncOperationalSummary(
      request.query as unknown as AdminSyncOperationalQueryInput,
    );
    response.json(summary);
  }),
);
