import { Prisma } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { userAdminAuditActor } from "../admin/admin-audit-actor";
import {
  mapSupportActionAuditToAdminAuditLog,
} from "./support-actions.audit";
import {
  sanitizeOperationalActionPayload,
} from "./support-actions.service";
import type {
  OperationalActionApiResponse,
  OperationalActionContract,
} from "./support-actions.types";

type AdminAuditClient = {
  adminAuditLog: {
    create(input: {
      data: {
        actorType: "USER";
        actorUserId: string;
        actorLabel?: string | null;
        targetCompanyId?: string | null;
        action: string;
        details?: Prisma.InputJsonValue;
      };
      select: { id: true };
    }): Promise<{ id: string }>;
  };
};

export class SupportActionAuditPersistenceService {
  constructor(private readonly client: AdminAuditClient = prisma) {}

  async recordDryRun(action: OperationalActionContract) {
    const mapped = mapSupportActionAuditToAdminAuditLog(action.auditDraft);
    const audit = await this.client.adminAuditLog.create({
      data: {
        actorType: mapped.actorType,
        actorUserId: mapped.actorUserId,
        actorLabel: mapped.actorLabel,
        targetCompanyId: mapped.targetCompanyId,
        action: mapped.action,
        details: sanitizeOperationalActionPayload(
          mapped.details,
        ) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return audit.id;
  }

  async recordDeniedAttempt(input: {
    actorAdminId: string | null | undefined;
    companyId?: unknown;
    actionType?: unknown;
    targetType?: unknown;
    targetId?: unknown;
    response: OperationalActionApiResponse;
    rawPayload: unknown;
  }) {
    const actorAdminId = input.actorAdminId?.trim();
    if (actorAdminId == null || actorAdminId.length === 0) {
      return null;
    }

    const actionType =
      typeof input.actionType === "string" && input.actionType.trim().length > 0
        ? input.actionType.trim()
        : "unknown";
    const companyId =
      typeof input.companyId === "string" && input.companyId.trim().length > 0
        ? input.companyId.trim()
        : null;

    const audit = await this.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(actorAdminId),
        targetCompanyId: companyId,
        action: `support.${actionType}.dry_run.denied`,
        details: sanitizeOperationalActionPayload({
          actionType,
          targetType: input.targetType,
          targetId: input.targetId,
          result: {
            ok: input.response.ok,
            code: input.response.code,
            message: input.response.message,
          },
          rawPayload: input.rawPayload,
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return audit.id;
  }
}
