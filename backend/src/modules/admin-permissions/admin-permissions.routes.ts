import { Router } from "express";

import { asyncHandler } from "../../shared/http/async-handler";
import type { AdminPermissionOperationResult } from "./admin-permissions.types";
import { AdminPermissionsService } from "./admin-permissions.service";
import {
  adminPermissionMutationBodySchema,
  type AdminPermissionMutationBodyInput,
} from "./admin-permissions.schemas";

type AdminPermissionsRouterDependencies = {
  service?: Pick<
    AdminPermissionsService,
    | "listKnownPermissions"
    | "listAdminPermissions"
    | "grantPermission"
    | "revokePermission"
    | "recordRouteDeniedAttempt"
  >;
};

export function createAdminPermissionsRouter(
  dependencies: AdminPermissionsRouterDependencies = {},
) {
  const router = Router();
  const service = dependencies.service ?? new AdminPermissionsService();

  router.use((request, response, next) => {
    if (request.auth?.userId == null || request.auth.userId.trim() === "") {
      response.status(401).json({
        ok: false,
        code: "ADMIN_PERMISSION_ACTOR_REQUIRED",
        message: "Ator administrativo obrigatorio para gerenciar permissoes.",
        auditEventId: null,
      });
      return;
    }

    next();
  });

  router.get(
    "/catalog",
    asyncHandler(async (_request, response) => {
      const payload = service.listKnownPermissions();
      response.json({
        ...payload,
        catalog: payload.knownPermissions ?? [],
      });
    }),
  );

  router.get(
    "/users/:adminUserId",
    asyncHandler(async (request, response) => {
      const targetAdminId = readRequiredParam(request.params.adminUserId);
      if (targetAdminId == null) {
        response.status(422).json(validationResponse("adminUserId obrigatorio."));
        return;
      }

      const payload = await service.listAdminPermissions({
        actorAdminId: request.auth!.userId,
        targetAdminId,
      });
      response.status(statusCodeFor(payload)).json(payload);
    }),
  );

  router.post(
    "/users/:adminUserId/grant",
    asyncHandler(async (request, response) => {
      await handlePermissionMutation({
        operation: "grant",
        service,
        actorAdminId: request.auth!.userId,
        targetAdminId: readRequiredParam(request.params.adminUserId),
        rawBody: request.body,
        response,
      });
    }),
  );

  router.post(
    "/users/:adminUserId/revoke",
    asyncHandler(async (request, response) => {
      await handlePermissionMutation({
        operation: "revoke",
        service,
        actorAdminId: request.auth!.userId,
        targetAdminId: readRequiredParam(request.params.adminUserId),
        rawBody: request.body,
        response,
      });
    }),
  );

  return router;
}

export const adminPermissionsRouter = createAdminPermissionsRouter();

async function handlePermissionMutation(input: {
  operation: "grant" | "revoke";
  service: NonNullable<AdminPermissionsRouterDependencies["service"]>;
  actorAdminId: string;
  targetAdminId: string | null;
  rawBody: unknown;
  response: {
    status(code: number): { json(payload: unknown): unknown };
    json(payload: unknown): unknown;
  };
}) {
  if (input.targetAdminId == null) {
    const payload = validationResponse("adminUserId obrigatorio.");
    await auditInvalidPayload(input, payload);
    input.response.status(422).json(payload);
    return;
  }

  const parsedBody = adminPermissionMutationBodySchema.safeParse(input.rawBody);
  if (!parsedBody.success) {
    const payload = validationResponse("Payload de permissao administrativa invalido.", {
      issues: parsedBody.error.flatten(),
    });
    await auditInvalidPayload(input, payload);
    input.response.status(422).json(payload);
    return;
  }

  const body = parsedBody.data;
  const payload =
    input.operation === "grant"
      ? await input.service.grantPermission({
          actorAdminId: input.actorAdminId,
          targetAdminId: input.targetAdminId,
          ...body,
        })
      : await input.service.revokePermission({
          actorAdminId: input.actorAdminId,
          targetAdminId: input.targetAdminId,
          ...body,
        });

  if (!payload.ok && payload.auditEventId == null) {
    const auditEventId = await input.service.recordRouteDeniedAttempt({
      actorAdminId: input.actorAdminId,
      action: `admin.permission.${input.operation}.denied`,
      targetAdminId: input.targetAdminId,
      permissionKey: body.permissionKey,
      reason: body.reason,
      resultCode: payload.code,
      message: payload.message,
      rawPayload: input.rawBody,
    });
    payload.auditEventId = auditEventId;
  }

  input.response.status(statusCodeFor(payload)).json(payload);
}

async function auditInvalidPayload(
  input: {
    operation: "grant" | "revoke";
    service: NonNullable<AdminPermissionsRouterDependencies["service"]>;
    actorAdminId: string;
    targetAdminId: string | null;
    rawBody: unknown;
  },
  payload: AdminPermissionOperationResult,
) {
  if (input.targetAdminId == null) {
    return;
  }

  const rawBody = readObject(input.rawBody);
  const auditEventId = await input.service.recordRouteDeniedAttempt({
    actorAdminId: input.actorAdminId,
    action: `admin.permission.${input.operation}.denied`,
    targetAdminId: input.targetAdminId,
    permissionKey: rawBody.permissionKey,
    reason: rawBody.reason,
    resultCode: payload.code,
    message: payload.message,
    rawPayload: input.rawBody,
  });
  payload.auditEventId = auditEventId;
}

function statusCodeFor(payload: AdminPermissionOperationResult) {
  if (payload.ok) {
    return 200;
  }

  switch (payload.code) {
    case "ADMIN_PERMISSION_ACTOR_REQUIRED":
      return 401;
    case "ADMIN_PERMISSION_MANAGE_REQUIRED":
    case "ADMIN_PERMISSION_SELF_GRANT_BLOCKED":
      return 403;
    case "ADMIN_PERMISSION_UNSUPPORTED":
    case "ADMIN_PERMISSION_VALIDATION_ERROR":
      return 422;
    default:
      return 400;
  }
}

function validationResponse(
  message: string,
  details?: unknown,
): AdminPermissionOperationResult {
  return {
    ok: false,
    code: "ADMIN_PERMISSION_VALIDATION_ERROR",
    message,
    auditEventId: null,
    details,
  };
}

function readRequiredParam(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;
  const normalized = raw?.trim();
  return normalized == null || normalized.length === 0 ? null : normalized;
}

function readObject(value: unknown): Record<string, unknown> {
  if (value != null && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}
