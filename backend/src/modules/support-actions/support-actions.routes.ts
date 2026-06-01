import { Router } from "express";

import { asyncHandler } from "../../shared/http/async-handler";
import { buildOperationalActionDryRun } from "./support-actions.service";
import { supportActionDryRunHttpBodySchema } from "./support-actions.schemas";
import { SupportActionAuditPersistenceService } from "./support-actions.audit-persistence";
import { SupportActionExecutionService } from "./support-actions.execution.service";
import { SupportActionRbacService } from "./support-actions.rbac";
import type { SupportActionExecutionResponse } from "./support-actions.execution.types";
import type { SupportActionPermissionContext } from "./support-actions.types";
import type { OperationalActionApiResponse } from "./support-actions.types";

type SupportActionsRouterDependencies = {
  rbacService?: {
    getSupportActionPermissionContext(
      actorAdminId: string,
    ): Promise<SupportActionPermissionContext>;
  };
  auditService?: {
    recordDryRun(action: NonNullable<OperationalActionApiResponse["action"]>): Promise<string>;
    recordDeniedAttempt(input: {
      actorAdminId: string | null | undefined;
      companyId?: unknown;
      actionType?: unknown;
      targetType?: unknown;
      targetId?: unknown;
      response: OperationalActionApiResponse;
      rawPayload: unknown;
    }): Promise<string | null>;
  };
  executionService?: {
    executeRevokeSession(
      rawInput: unknown,
      permissionContext?: SupportActionPermissionContext,
    ): Promise<SupportActionExecutionResponse>;
  };
  now?: () => Date;
};

export function createSupportActionsRouter(
  dependencies: SupportActionsRouterDependencies = {},
) {
  const router = Router();
  const rbacService = dependencies.rbacService ?? new SupportActionRbacService();
  const auditService =
    dependencies.auditService ?? new SupportActionAuditPersistenceService();
  const executionService =
    dependencies.executionService ?? new SupportActionExecutionService();
  const now = dependencies.now ?? (() => new Date());

  router.post(
    "/dry-run",
    asyncHandler(async (request, response) => {
    const parsedBody = supportActionDryRunHttpBodySchema.safeParse(request.body);

    if (!parsedBody.success) {
      const payload = buildOperationalActionDryRun({
        ...readObject(request.body),
        actorAdminId: request.auth?.userId,
      });
      await auditDeniedAttempt(auditService, request.auth?.userId, request.body, payload);
      response.status(statusCodeFor(payload)).json(payload);
      return;
    }

    const body = parsedBody.data;
    const actionPayload = {
      actionType: body.actionType,
      companyId: body.companyId,
      targetType: body.targetType,
      targetId: body.targetId,
      reason: body.reason,
      dryRun: true,
      metadata: body.metadata,
      ...(request.auth?.userId == null
        ? {}
        : { actorAdminId: request.auth.userId }),
    };
    const permissionContext =
      request.auth?.userId == null
        ? {
            actorAdminId: null,
            permissionKeys: [],
          }
        : await rbacService.getSupportActionPermissionContext(
            request.auth.userId,
          );

    const payload = buildOperationalActionDryRun(actionPayload, now(), {
      ...permissionContext,
      isPlatformAdmin: request.auth?.isPlatformAdmin === true,
      allowPlatformAdminFallback:
        permissionContext.allowPlatformAdminFallback === true,
    });

    if (payload.ok && payload.action != null) {
      const auditEventId = await auditService.recordDryRun(payload.action);
      payload.action.auditEventId = auditEventId;
    } else {
      await auditDeniedAttempt(auditService, request.auth?.userId, request.body, payload);
    }

    response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/revoke-session/execute",
    asyncHandler(async (request, response) => {
      const actorAdminId = request.auth?.userId;
      const permissionContext =
        actorAdminId == null
          ? {
              actorAdminId: null,
              permissionKeys: [],
            }
          : await rbacService.getSupportActionPermissionContext(actorAdminId);
      const payload = await executionService.executeRevokeSession(
        {
          ...readObject(request.body),
          actorAdminId,
        },
        {
          ...permissionContext,
          isPlatformAdmin: request.auth?.isPlatformAdmin === true,
          allowPlatformAdminFallback:
            permissionContext.allowPlatformAdminFallback === true,
        },
      );

      response.status(statusCodeForExecution(payload)).json(payload);
    }),
  );

  return router;
}

export const supportActionsRouter = createSupportActionsRouter();

function statusCodeFor(payload: OperationalActionApiResponse) {
  if (payload.ok) {
    return 200;
  }

  switch (payload.code) {
    case "OPERATIONAL_ACTION_VALIDATION_ERROR":
      return 422;
    case "OPERATIONAL_ACTION_ACTOR_REQUIRED":
      return 401;
    case "OPERATIONAL_ACTION_PERMISSION_REQUIRED":
    case "OPERATIONAL_ACTION_PERMISSION_DENIED":
    case "OPERATIONAL_ACTION_MISSING_PERMISSION":
      return 403;
    case "OPERATIONAL_ACTION_TARGET_NOT_FOUND":
      return 404;
    case "OPERATIONAL_ACTION_STATE_CONFLICT":
      return 409;
    case "OPERATIONAL_ACTION_UNSUPPORTED":
      return 400;
    default:
      return 500;
  }
}

function statusCodeForExecution(payload: SupportActionExecutionResponse) {
  if (payload.ok) {
    return 200;
  }

  switch (payload.code) {
    case "SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR":
      return 422;
    case "SUPPORT_ACTION_EXECUTION_ACTOR_REQUIRED":
      return 401;
    case "SUPPORT_ACTION_EXECUTION_DISABLED":
      return 503;
    case "SUPPORT_ACTION_EXECUTION_PERMISSION_DENIED":
      return 403;
    case "SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND":
      return 404;
    case "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT":
      return 409;
    case "SUPPORT_ACTION_EXECUTION_DRY_RUN_REQUIRED":
    case "SUPPORT_ACTION_EXECUTION_DRY_RUN_EXPIRED":
    case "SUPPORT_ACTION_EXECUTION_DRY_RUN_MISMATCH":
      return 409;
    case "SUPPORT_ACTION_EXECUTION_UNSUPPORTED":
      return 400;
    default:
      return 500;
  }
}

function readObject(value: unknown): Record<string, unknown> {
  if (value != null && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

async function auditDeniedAttempt(
  auditService: NonNullable<SupportActionsRouterDependencies["auditService"]>,
  actorAdminId: string | null | undefined,
  rawPayload: unknown,
  payload: OperationalActionApiResponse,
) {
  const body = readObject(rawPayload);
  await auditService.recordDeniedAttempt({
    actorAdminId,
    companyId: body.companyId,
    actionType: body.actionType,
    targetType: body.targetType,
    targetId: body.targetId,
    response: payload,
    rawPayload,
  });
}
