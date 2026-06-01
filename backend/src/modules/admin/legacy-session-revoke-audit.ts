import { Prisma } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";
import { logger } from "../../shared/observability/logger";
import { sanitizeOperationalActionPayload } from "../support-actions/support-actions.service";
import { userAdminAuditActor } from "./admin-audit-actor";

const legacySessionRevokeAuditAction = "admin.sessions.legacy_revoke.used";

type LegacySessionRevokeResult = "requested" | "succeeded" | "failed";

type LegacySessionRevokeAuditClient = {
  deviceSession: {
    findUnique(input: {
      where: { id: string };
      select: { companyId: true };
    }): Promise<{ companyId: string } | null>;
  };
  adminAuditLog: {
    create(input: {
      data: {
        actorType: "USER";
        actorUserId: string;
        actorLabel: null;
        targetCompanyId: string | null;
        action: string;
        details: Prisma.InputJsonValue;
      };
      select: { id: true };
    }): Promise<{ id: string }>;
  };
};

type LegacySessionRevokeLogger = Pick<typeof logger, "warn" | "error">;

type LegacySessionRevokeDependencies = {
  client: LegacySessionRevokeAuditClient;
  operationalLogger: LegacySessionRevokeLogger;
  now: () => Date;
  revokeSession(input: {
    sessionId: string;
    actorUserId: string;
  }): Promise<void>;
};

export type LegacySessionRevokeInput = {
  sessionId: string;
  actorUserId: string;
};

export function legacySessionRevokeLogContext(input: LegacySessionRevokeInput) {
  return sanitizeOperationalActionPayload(input);
}

export async function revokeLegacyAdminSession(
  input: LegacySessionRevokeInput,
  overrides: Pick<LegacySessionRevokeDependencies, "revokeSession"> &
    Partial<Omit<LegacySessionRevokeDependencies, "revokeSession">>,
) {
  const dependencies: LegacySessionRevokeDependencies = {
    client: prisma,
    operationalLogger: logger,
    now: () => new Date(),
    ...overrides,
  };
  const targetCompanyId = await resolveTargetCompanyId(input, dependencies);

  await recordLegacyRevokeAudit(input, targetCompanyId, "requested", dependencies);

  try {
    await dependencies.revokeSession(input);
    await recordLegacyRevokeAudit(
      input,
      targetCompanyId,
      "succeeded",
      dependencies,
    );
  } catch (error) {
    await recordLegacyRevokeAudit(input, targetCompanyId, "failed", dependencies, {
      errorCode: safeErrorCode(error),
    });
    throw error;
  }
}

async function resolveTargetCompanyId(
  input: LegacySessionRevokeInput,
  dependencies: LegacySessionRevokeDependencies,
) {
  try {
    const session = await dependencies.client.deviceSession.findUnique({
      where: { id: input.sessionId },
      select: { companyId: true },
    });
    return session?.companyId ?? null;
  } catch (error) {
    dependencies.operationalLogger.error(
      "admin.sessions.legacy_revoke.company_resolution_failed",
      sanitizeOperationalActionPayload({
        ...legacySessionRevokeLogContext(input),
        errorCode: safeErrorCode(error),
      }),
    );
    return null;
  }
}

async function recordLegacyRevokeAudit(
  input: LegacySessionRevokeInput,
  targetCompanyId: string | null,
  result: LegacySessionRevokeResult,
  dependencies: LegacySessionRevokeDependencies,
  extraDetails: Record<string, unknown> = {},
) {
  try {
    await dependencies.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorUserId),
        targetCompanyId,
        action: legacySessionRevokeAuditAction,
        details: sanitizeOperationalActionPayload({
          targetType: "session",
          targetId: input.sessionId,
          result,
          origin: "legacy_route",
          recommendation: "migrate_to_support_actions_revoke_session",
          timestamp: dependencies.now().toISOString(),
          ...extraDetails,
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });
  } catch (error) {
    dependencies.operationalLogger.error(
      "admin.sessions.legacy_revoke.audit_persistence_failed",
      sanitizeOperationalActionPayload({
        ...legacySessionRevokeLogContext(input),
        result,
        errorCode: safeErrorCode(error),
      }),
    );
  }
}

function safeErrorCode(error: unknown) {
  if (error instanceof AppError) {
    return error.code;
  }

  if (error instanceof Error) {
    return error.name;
  }

  return "UNKNOWN_ERROR";
}
