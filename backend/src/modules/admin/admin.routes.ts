import { Router } from 'express';

import {
  requirePlatformAdmin,
} from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { createRateLimit } from '../../shared/http/rate-limit';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  type AdminAuditQueryInput,
  type AdminCompaniesQueryInput,
  type AdminLicensesQueryInput,
  type AdminSyncQueryInput,
  adminAuditQuerySchema,
  adminCompaniesQuerySchema,
  adminLicensePatchSchema,
  adminLicensesQuerySchema,
  adminSyncQuerySchema,
} from './admin.schemas';
import { AdminService } from './admin.service';

const adminService = new AdminService();

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
