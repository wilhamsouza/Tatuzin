import { Router } from "express";

import { requirePlatformAdmin } from "../../shared/http/auth-middleware";
import { asyncHandler } from "../../shared/http/async-handler";
import { createRateLimit } from "../../shared/http/rate-limit";
import { logger } from "../../shared/observability/logger";
import { validateBody, validateQuery } from "../../shared/http/validate";
import {
  type AdminBillingCompaniesQueryInput,
  type AdminBillingListQueryInput,
  adminBillingCancelLocalSchema,
  adminBillingCompaniesQuerySchema,
  adminBillingForcePlanSchema,
  adminBillingListQuerySchema,
  adminBillingReconcileDryRunSchema,
  adminBillingReconcileSchema,
  adminBillingRefreshSchema,
  adminLicenseEmergencyExtensionDryRunSchema,
  adminLicenseEmergencyExtensionSchema,
  adminLicenseStatusActionDryRunSchema,
  adminLicenseStatusActionSchema,
} from "../billing/billing-admin.schemas";
import { BillingAdminService } from "../billing/billing-admin.service";
import {
  type AdminAuditQueryInput,
  type AdminAccessActionDryRunInput,
  type AdminAccessActionInput,
  type AdminCompanySyncConflictsQueryInput,
  type AdminCompanySyncEventsQueryInput,
  type AdminCompanySyncIncidentsQueryInput,
  type AdminCompaniesQueryInput,
  type AdminDevicesQueryInput,
  type AdminLicensesQueryInput,
  type AdminSyncCenterArchiveBodyInput,
  type AdminSyncCenterCompaniesQueryInput,
  type AdminSyncCenterConflictsQueryInput,
  type AdminSyncCenterDetailQueryInput,
  type AdminSyncCenterDryRunBodyInput,
  type AdminSyncCenterEventsQueryInput,
  type AdminSyncCenterManualStockAdjustmentBodyInput,
  type AdminSyncCenterReprocessBodyInput,
  type AdminSyncSupportActionInput,
  type AdminSyncSupportDryRunInput,
  type AdminSyncOperationalQueryInput,
  type AdminSyncQueryInput,
  adminSyncSupportActionSchema,
  adminSyncSupportDryRunSchema,
  adminSyncCenterArchiveBodySchema,
  adminSyncCenterCompaniesQuerySchema,
  adminSyncCenterConflictsQuerySchema,
  adminSyncCenterDetailQuerySchema,
  adminSyncCenterDryRunBodySchema,
  adminSyncCenterEventsQuerySchema,
  adminSyncCenterManualStockAdjustmentBodySchema,
  adminSyncCenterReprocessBodySchema,
  adminCompanySyncConflictsQuerySchema,
  adminCompanySyncEventsQuerySchema,
  adminCompanySyncIncidentsQuerySchema,
  adminAuditQuerySchema,
  adminAccessActionDryRunSchema,
  adminAccessActionSchema,
  adminCompaniesQuerySchema,
  adminDevicesQuerySchema,
  adminLicensePatchSchema,
  adminLicensesQuerySchema,
  adminSyncOperationalQuerySchema,
  adminSyncQuerySchema,
} from "./admin.schemas";
import { AdminSyncCenterService } from "./admin-sync-center.service";
import { AdminSyncHealthService } from "./admin-sync-health.service";
import { AdminService } from "./admin.service";
import { SyncSupportService } from "../sync/sync-support.service";
import { supportActionsRouter } from "../support-actions/support-actions.routes";
import { adminPermissionsRouter } from "../admin-permissions/admin-permissions.routes";
import {
  legacySessionRevokeLogContext,
  revokeLegacyAdminSession,
} from "./legacy-session-revoke-audit";

const adminService = new AdminService();
const adminSyncHealthService = new AdminSyncHealthService();
const adminSyncCenterService = new AdminSyncCenterService();
const syncSupportService = new SyncSupportService();
const billingAdminService = new BillingAdminService();

export const adminRouter = Router();

adminRouter.use(requirePlatformAdmin);
adminRouter.use(
  createRateLimit({
    name: "platform_admin",
    windowMs: 60_000,
    max: 240,
    message:
      "Muitas operacoes administrativas em pouco tempo. Aguarde um instante e tente novamente.",
    code: "ADMIN_RATE_LIMITED",
    keyGenerator(request) {
      return request.auth?.userId ?? request.ip ?? "unknown-admin";
    },
  }),
);

adminRouter.use("/support-actions", supportActionsRouter);
adminRouter.use("/permissions", adminPermissionsRouter);

adminRouter.get(
  "/billing/companies",
  validateQuery(adminBillingCompaniesQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await billingAdminService.listCompanies(
      request.query as unknown as AdminBillingCompaniesQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/plans",
  asyncHandler(async (_request, response) => {
    const payload = await adminService.getPlansOverview();
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies",
  validateQuery(adminCompaniesQuerySchema),
  asyncHandler(async (request, response) => {
    const companies = await adminService.listCompanies(
      request.query as unknown as AdminCompaniesQueryInput,
    );
    response.json(companies);
  }),
);

adminRouter.get(
  "/companies/:id",
  asyncHandler(async (request, response) => {
    const companyId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await adminService.getCompany(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies/:companyId/access-summary",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminService.getCompanyAccessSummary(companyId);
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/access/:targetId/block/dry-run",
  validateBody(adminAccessActionDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const targetId = readParam(request.params.targetId);
    const payload = await adminService.dryRunAccessBlock({
      ...(request.body as AdminAccessActionDryRunInput),
      companyId,
      targetId,
      actorUserId: request.auth!.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/access/:targetId/block",
  validateBody(adminAccessActionSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const targetId = readParam(request.params.targetId);
    const payload = await adminService.applyAccessBlock({
      ...(request.body as AdminAccessActionInput),
      companyId,
      targetId,
      actorUserId: request.auth!.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/access/:targetId/reactivate/dry-run",
  validateBody(adminAccessActionDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const targetId = readParam(request.params.targetId);
    const payload = await adminService.dryRunAccessReactivate({
      ...(request.body as AdminAccessActionDryRunInput),
      companyId,
      targetId,
      actorUserId: request.auth!.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/access/:targetId/reactivate",
  validateBody(adminAccessActionSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const targetId = readParam(request.params.targetId);
    const payload = await adminService.applyAccessReactivate({
      ...(request.body as AdminAccessActionInput),
      companyId,
      targetId,
      actorUserId: request.auth!.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies/:companyId/sync/health",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.getHealth(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies/:companyId/sync/events",
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
  "/companies/:companyId/sync/conflicts",
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
  "/companies/:companyId/sync/incidents",
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
  "/companies/:companyId/devices",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncHealthService.listDevices(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies/:companyId/sessions",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminService.listCompanySessions(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies/:companyId/billing/status",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.getStatus(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/companies/:companyId/billing/events",
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
  "/companies/:companyId/billing/checkout-sessions",
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

adminRouter.get(
  "/companies/:companyId/billing/audit-logs",
  validateQuery(adminBillingListQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.listAuditLogs(
      companyId,
      request.query as unknown as AdminBillingListQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/billing/refresh",
  validateBody(adminBillingRefreshSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.refreshCompany({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/billing/reconcile/dry-run",
  validateBody(adminBillingReconcileDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.dryRunBillingReconcile({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/billing/reconcile",
  validateBody(adminBillingReconcileSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.applyBillingReconcile({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/billing/force-plan",
  validateBody(adminBillingForcePlanSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.forcePlan({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/billing/cancel-local",
  validateBody(adminBillingCancelLocalSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.cancelLocal({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/license/extension/dry-run",
  validateBody(adminLicenseEmergencyExtensionDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.dryRunEmergencyExtension({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/license/extension",
  validateBody(adminLicenseEmergencyExtensionSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.applyEmergencyExtension({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/sessions/:sessionId/revoke",
  asyncHandler(async (request, response) => {
    const sessionId = Array.isArray(request.params.sessionId)
      ? request.params.sessionId[0]
      : request.params.sessionId;

    logger.warn(
      "admin.sessions.legacy_revoke.used",
      legacySessionRevokeLogContext({
        actorUserId: request.auth!.userId,
        sessionId,
      }),
    );

    await revokeLegacyAdminSession(
      {
        sessionId,
        actorUserId: request.auth!.userId,
      },
      {
        revokeSession: (input) => adminService.revokeSession(input),
      },
    );

    response.status(204).send();
  }),
);

adminRouter.patch(
  "/companies/:id/license",
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
  "/devices",
  validateQuery(adminDevicesQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await adminService.listDevices(
      request.query as unknown as AdminDevicesQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/licenses",
  validateQuery(adminLicensesQuerySchema),
  asyncHandler(async (request, response) => {
    const licenses = await adminService.listLicenses(
      request.query as unknown as AdminLicensesQueryInput,
    );
    response.json(licenses);
  }),
);

adminRouter.get(
  "/licenses/:companyId",
  asyncHandler(async (request, response) => {
    const companyId = Array.isArray(request.params.companyId)
      ? request.params.companyId[0]
      : request.params.companyId;
    const license = await adminService.getLicense(companyId);
    response.json({ license });
  }),
);

adminRouter.patch(
  "/licenses/:companyId",
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

adminRouter.post(
  "/companies/:companyId/license/suspend/dry-run",
  validateBody(adminLicenseStatusActionDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.dryRunLicenseSuspend({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/license/suspend",
  validateBody(adminLicenseStatusActionSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.applyLicenseSuspend({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/license/reactivate/dry-run",
  validateBody(adminLicenseStatusActionDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.dryRunLicenseReactivate({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.post(
  "/companies/:companyId/license/reactivate",
  validateBody(adminLicenseStatusActionSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await billingAdminService.applyLicenseReactivate({
      ...request.body,
      companyId,
      actorUserId: request.auth?.userId,
      ipAddress: request.ip,
      userAgent: request.get("user-agent") ?? null,
    });
    response.json(payload);
  }),
);

adminRouter.get(
  "/audit",
  validateQuery(adminAuditQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await adminService.getAuditLogs(
      request.query as unknown as AdminAuditQueryInput,
    );
    response.json(summary);
  }),
);

adminRouter.get(
  "/audit/summary",
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
  "/sync/companies",
  validateQuery(adminSyncCenterCompaniesQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await adminSyncCenterService.listCompanies(
      request.query as unknown as AdminSyncCenterCompaniesQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/companies/:companyId/summary",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncCenterService.getCompanySummary(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/companies/:companyId/devices",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await syncSupportService.listAdminDevices(companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/companies/:companyId/devices/:deviceId/diagnostics",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const deviceId = readParam(request.params.deviceId);
    const payload = await syncSupportService.getAdminDeviceDiagnostics(
      companyId,
      deviceId,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/companies/:companyId/devices/:deviceId/support-commands",
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const deviceId = readParam(request.params.deviceId);
    const payload = await syncSupportService.listAdminCommands(
      companyId,
      deviceId,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/companies/:companyId/devices/:deviceId/support-actions/dry-run",
  validateBody(adminSyncSupportDryRunSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const deviceId = readParam(request.params.deviceId);
    const payload = await syncSupportService.adminDryRun(
      companyId,
      deviceId,
      request.body as AdminSyncSupportDryRunInput,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/companies/:companyId/devices/:deviceId/support-actions",
  validateBody(adminSyncSupportActionSchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const deviceId = readParam(request.params.deviceId);
    const payload = await syncSupportService.createAdminCommand(
      companyId,
      deviceId,
      request.body as AdminSyncSupportActionInput,
      {
        actorUserId: request.auth!.userId,
        ipAddress: request.ip ?? null,
        userAgent: request.get("user-agent") ?? null,
      },
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/companies/:companyId/events",
  validateQuery(adminSyncCenterEventsQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncCenterService.listEvents(
      companyId,
      request.query as unknown as AdminSyncCenterEventsQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/events/:eventId",
  validateQuery(adminSyncCenterDetailQuerySchema),
  asyncHandler(async (request, response) => {
    const eventId = readParam(request.params.eventId);
    const { companyId } =
      request.query as unknown as AdminSyncCenterDetailQueryInput;
    const payload = await adminSyncCenterService.getEvent(eventId, companyId);
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/companies/:companyId/conflicts",
  validateQuery(adminSyncCenterConflictsQuerySchema),
  asyncHandler(async (request, response) => {
    const companyId = readParam(request.params.companyId);
    const payload = await adminSyncCenterService.listConflicts(
      companyId,
      request.query as unknown as AdminSyncCenterConflictsQueryInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/conflicts/:conflictId",
  validateQuery(adminSyncCenterDetailQuerySchema),
  asyncHandler(async (request, response) => {
    const conflictId = readParam(request.params.conflictId);
    const { companyId } =
      request.query as unknown as AdminSyncCenterDetailQueryInput;
    const payload = await adminSyncCenterService.getConflict(
      conflictId,
      companyId,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/events/:eventId/reprocess-dry-run",
  validateBody(adminSyncCenterDryRunBodySchema),
  asyncHandler(async (request, response) => {
    const eventId = readParam(request.params.eventId);
    const payload = await adminSyncCenterService.reprocessDryRun(
      eventId,
      request.body as AdminSyncCenterDryRunBodyInput,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/events/:eventId/reprocess",
  validateBody(adminSyncCenterReprocessBodySchema),
  asyncHandler(async (request, response) => {
    const eventId = readParam(request.params.eventId);
    const payload = await adminSyncCenterService.reprocessEvent(
      eventId,
      request.body as AdminSyncCenterReprocessBodyInput,
      {
        actorUserId: request.auth!.userId,
        ipAddress: request.ip ?? null,
        userAgent: request.get("user-agent") ?? null,
      },
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/conflicts/:conflictId/archive-dry-run",
  validateBody(adminSyncCenterDryRunBodySchema),
  asyncHandler(async (request, response) => {
    const conflictId = readParam(request.params.conflictId);
    const payload = await adminSyncCenterService.archiveDryRun(
      conflictId,
      request.body as AdminSyncCenterDryRunBodyInput,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/conflicts/:conflictId/archive",
  validateBody(adminSyncCenterArchiveBodySchema),
  asyncHandler(async (request, response) => {
    const conflictId = readParam(request.params.conflictId);
    const payload = await adminSyncCenterService.archiveConflict(
      conflictId,
      request.body as AdminSyncCenterArchiveBodyInput,
      {
        actorUserId: request.auth!.userId,
        ipAddress: request.ip ?? null,
        userAgent: request.get("user-agent") ?? null,
      },
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/conflicts/:conflictId/manual-stock-adjustment-dry-run",
  validateBody(adminSyncCenterDryRunBodySchema),
  asyncHandler(async (request, response) => {
    const conflictId = readParam(request.params.conflictId);
    const payload = await adminSyncCenterService.manualStockAdjustmentDryRun(
      conflictId,
      request.body as AdminSyncCenterDryRunBodyInput,
    );
    response.json(payload);
  }),
);

adminRouter.post(
  "/sync/conflicts/:conflictId/manual-stock-adjustment",
  validateBody(adminSyncCenterManualStockAdjustmentBodySchema),
  asyncHandler(async (request, response) => {
    const conflictId = readParam(request.params.conflictId);
    const payload = await adminSyncCenterService.manualStockAdjustment(
      conflictId,
      request.body as AdminSyncCenterManualStockAdjustmentBodyInput,
    );
    response.json(payload);
  }),
);

adminRouter.get(
  "/sync/summary",
  validateQuery(adminSyncQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await adminService.getSyncSummary(
      request.query as unknown as AdminSyncQueryInput,
    );
    response.json(summary);
  }),
);

adminRouter.get(
  "/sync/operational-summary",
  validateQuery(adminSyncOperationalQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await adminService.getSyncOperationalSummary(
      request.query as unknown as AdminSyncOperationalQueryInput,
    );
    response.json(summary);
  }),
);
