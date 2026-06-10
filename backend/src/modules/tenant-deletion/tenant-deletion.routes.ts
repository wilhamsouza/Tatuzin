import { Router } from "express";

import { asyncHandler } from "../../shared/http/async-handler";
import { validateBody, validateQuery } from "../../shared/http/validate";
import {
  tenantDeletionCreateRequestSchema,
  tenantDeletionDryRunSchema,
  tenantDeletionListQuerySchema,
  tenantDeletionQuarantineSchema,
  tenantDeletionReasonSchema,
  type TenantDeletionCreateRequestInput,
  type TenantDeletionDryRunInput,
  type TenantDeletionListQueryInput,
  type TenantDeletionQuarantineInput,
  type TenantDeletionReasonInput,
} from "./tenant-deletion.schemas";
import { TenantDeletionService } from "./tenant-deletion.service";
import type { TenantDeletionOperationResult } from "./tenant-deletion.types";

type TenantDeletionRouterDependencies = {
  service?: Pick<
    TenantDeletionService,
    | "listRequests"
    | "getRequest"
    | "createRequest"
    | "markIdentityPending"
    | "verifyIdentity"
    | "quarantineRequest"
    | "cancelRequest"
    | "rejectRequest"
    | "dryRun"
  >;
};

export function createTenantDeletionRouter(
  dependencies: TenantDeletionRouterDependencies = {},
) {
  const router = Router();
  const service = dependencies.service ?? new TenantDeletionService();

  router.use((request, response, next) => {
    if (request.auth?.userId == null || request.auth.userId.trim() === "") {
      response.status(401).json({
        ok: false,
        code: "TENANT_DELETION_ACTOR_REQUIRED",
        message: "Ator administrativo obrigatorio.",
        auditEventId: null,
      });
      return;
    }
    next();
  });

  router.get(
    "/requests",
    validateQuery(tenantDeletionListQuerySchema),
    asyncHandler(async (request, response) => {
      const payload = await service.listRequests({
        actorAdminId: request.auth!.userId,
        ...(request.query as unknown as TenantDeletionListQueryInput),
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/requests",
    validateBody(tenantDeletionCreateRequestSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionCreateRequestInput;
      const payload = await service.createRequest({
        ...body,
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.get(
    "/requests/:requestId",
    asyncHandler(async (request, response) => {
      const payload = await service.getRequest({
        actorAdminId: request.auth!.userId,
        requestId: readParam(request.params.requestId),
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/requests/:requestId/identity-pending",
    validateBody(tenantDeletionReasonSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionReasonInput;
      const payload = await service.markIdentityPending({
        ...body,
        requestId: readParam(request.params.requestId),
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/requests/:requestId/verify-identity",
    validateBody(tenantDeletionReasonSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionReasonInput;
      const payload = await service.verifyIdentity({
        ...body,
        requestId: readParam(request.params.requestId),
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/requests/:requestId/quarantine",
    validateBody(tenantDeletionQuarantineSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionQuarantineInput;
      const payload = await service.quarantineRequest({
        ...body,
        requestId: readParam(request.params.requestId),
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/requests/:requestId/cancel",
    validateBody(tenantDeletionReasonSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionReasonInput;
      const payload = await service.cancelRequest({
        ...body,
        requestId: readParam(request.params.requestId),
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/requests/:requestId/reject",
    validateBody(tenantDeletionReasonSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionReasonInput;
      const payload = await service.rejectRequest({
        ...body,
        requestId: readParam(request.params.requestId),
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/companies/:companyId/dry-run",
    validateBody(tenantDeletionDryRunSchema),
    asyncHandler(async (request, response) => {
      const body = request.body as TenantDeletionDryRunInput;
      const payload = await service.dryRun({
        ...body,
        companyId: readParam(request.params.companyId),
        actorAdminId: request.auth!.userId,
        ipAddress: request.ip,
        userAgent: request.get("user-agent") ?? null,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  return router;
}

export const tenantDeletionRouter = createTenantDeletionRouter();

function statusCodeFor(payload: TenantDeletionOperationResult) {
  if (payload.ok) {
    return 200;
  }
  switch (payload.code) {
    case "TENANT_DELETION_ACTOR_REQUIRED":
      return 401;
    case "TENANT_DELETION_PERMISSION_REQUIRED":
      return 403;
    case "TENANT_DELETION_COMPANY_NOT_FOUND":
    case "TENANT_DELETION_REQUEST_NOT_FOUND":
      return 404;
    case "TENANT_DELETION_STATE_CONFLICT":
      return 409;
    case "TENANT_DELETION_COMPANY_REQUIRED":
    case "TENANT_DELETION_REASON_REQUIRED":
    case "TENANT_DELETION_REQUEST_REQUIRED":
    case "TENANT_DELETION_VALIDATION_ERROR":
      return 422;
    default:
      return 400;
  }
}

function readParam(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;
  return raw?.trim() ?? "";
}
