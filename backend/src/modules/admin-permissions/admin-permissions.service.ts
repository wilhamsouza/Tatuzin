import { Prisma } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { userAdminAuditActor } from "../admin/admin-audit-actor";
import { sanitizeOperationalActionPayload } from "../support-actions/support-actions.service";
import {
  adminPermissionManagementKey,
  type AdminPermissionKey,
  type AdminPermissionOperationResult,
  type PersistedAdminPermission,
} from "./admin-permissions.types";
import {
  getAdminPermissionDefinition,
  isCriticalAdminPermission,
  isKnownAdminPermissionKey,
  listKnownAdminPermissions,
} from "./admin-permissions.catalog";

type AdminPermissionRecord = {
  id: string;
  actorUserId: string;
  permissionKey: string;
  scope: string;
  scopeId: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
};

type AdminPermissionsClient = {
  adminUserPermission: {
    findMany(input: {
      where: Partial<{
        actorUserId: string;
        isActive: boolean;
      }>;
      orderBy?: Array<Record<string, "asc" | "desc">>;
    }): Promise<AdminPermissionRecord[]>;
    upsert(input: {
      where: {
        actorUserId_permissionKey_scope_scopeId: {
          actorUserId: string;
          permissionKey: string;
          scope: string;
          scopeId: string;
        };
      };
      create: {
        actorUserId: string;
        permissionKey: string;
        scope: string;
        scopeId: string;
        isActive: boolean;
      };
      update: {
        isActive: boolean;
      };
    }): Promise<AdminPermissionRecord>;
    updateMany(input: {
      where: {
        actorUserId: string;
        permissionKey: string;
        scope: string;
        scopeId: string;
        isActive: boolean;
      };
      data: {
        isActive: boolean;
      };
    }): Promise<{ count: number }>;
  };
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

type AdminPermissionMutationInput = {
  actorAdminId: string | null | undefined;
  targetAdminId: string;
  permissionKey: string;
  reason: string;
  scope?: string;
  scopeId?: string;
};

type ListAdminPermissionsInput = {
  actorAdminId: string | null | undefined;
  targetAdminId: string;
};

export class AdminPermissionsService {
  constructor(private readonly client: AdminPermissionsClient = prisma) {}

  listKnownPermissions(): AdminPermissionOperationResult {
    return {
      ok: true,
      code: "ADMIN_PERMISSION_LISTED",
      message: "Permissoes administrativas conhecidas.",
      auditEventId: null,
      knownPermissions: listKnownAdminPermissions(),
    };
  }

  async listAdminPermissions(
    input: ListAdminPermissionsInput,
  ): Promise<AdminPermissionOperationResult> {
    const actor = this.normalizeActor(input.actorAdminId);
    if (actor == null) {
      return this.actorRequired();
    }

    const manageDecision = await this.ensureManagePermission(actor);
    if (!manageDecision.ok) {
      const auditEventId = await this.auditDenied({
        actorAdminId: actor,
        action: "admin.permission.list.denied",
        targetAdminId: input.targetAdminId,
        result: manageDecision,
      });
      return { ...manageDecision, auditEventId };
    }

    const permissions = await this.client.adminUserPermission.findMany({
      where: {
        actorUserId: input.targetAdminId,
        isActive: true,
      },
      orderBy: [{ permissionKey: "asc" }, { scope: "asc" }, { scopeId: "asc" }],
    });
    const auditEventId = await this.auditSuccess({
      actorAdminId: actor,
      action: "admin.permission.list",
      targetAdminId: input.targetAdminId,
      permissionKey: null,
      reason: null,
      resultCode: "ADMIN_PERMISSION_LISTED",
      metadata: { count: permissions.length },
    });

    return {
      ok: true,
      code: "ADMIN_PERMISSION_LISTED",
      message: "Permissoes administrativas persistidas listadas.",
      auditEventId,
      permissions,
    };
  }

  async grantPermission(
    input: AdminPermissionMutationInput,
  ): Promise<AdminPermissionOperationResult> {
    const normalized = this.normalizeMutation(input);
    if (!normalized.ok) {
      return normalized.result;
    }

    const manageDecision = await this.ensureManagePermission(
      normalized.actorAdminId,
    );
    if (!manageDecision.ok) {
      const auditEventId = await this.auditDenied({
        actorAdminId: normalized.actorAdminId,
        action: "admin.permission.grant.denied",
        targetAdminId: normalized.targetAdminId,
        permissionKey: normalized.permissionKey,
        result: manageDecision,
      });
      return { ...manageDecision, auditEventId };
    }

    if (
      normalized.actorAdminId === normalized.targetAdminId &&
      isCriticalAdminPermission(normalized.permissionKey)
    ) {
      const result = this.selfGrantBlocked(normalized.permissionKey);
      const auditEventId = await this.auditDenied({
        actorAdminId: normalized.actorAdminId,
        action: "admin.permission.grant.denied",
        targetAdminId: normalized.targetAdminId,
        permissionKey: normalized.permissionKey,
        reason: normalized.reason,
        result,
      });
      return { ...result, auditEventId };
    }

    const permission = await this.client.adminUserPermission.upsert({
      where: {
        actorUserId_permissionKey_scope_scopeId: {
          actorUserId: normalized.targetAdminId,
          permissionKey: normalized.permissionKey,
          scope: normalized.scope,
          scopeId: normalized.scopeId,
        },
      },
      create: {
        actorUserId: normalized.targetAdminId,
        permissionKey: normalized.permissionKey,
        scope: normalized.scope,
        scopeId: normalized.scopeId,
        isActive: true,
      },
      update: {
        isActive: true,
      },
    });
    const auditEventId = await this.auditSuccess({
      actorAdminId: normalized.actorAdminId,
      action: "admin.permission.grant",
      targetAdminId: normalized.targetAdminId,
      permissionKey: normalized.permissionKey,
      reason: normalized.reason,
      resultCode: "ADMIN_PERMISSION_GRANTED",
      metadata: { scope: normalized.scope, scopeId: normalized.scopeId },
    });

    return {
      ok: true,
      code: "ADMIN_PERMISSION_GRANTED",
      message: "Permissao administrativa concedida.",
      auditEventId,
      permission,
    };
  }

  async revokePermission(
    input: AdminPermissionMutationInput,
  ): Promise<AdminPermissionOperationResult> {
    const normalized = this.normalizeMutation(input);
    if (!normalized.ok) {
      return normalized.result;
    }

    const manageDecision = await this.ensureManagePermission(
      normalized.actorAdminId,
    );
    if (!manageDecision.ok) {
      const auditEventId = await this.auditDenied({
        actorAdminId: normalized.actorAdminId,
        action: "admin.permission.revoke.denied",
        targetAdminId: normalized.targetAdminId,
        permissionKey: normalized.permissionKey,
        result: manageDecision,
      });
      return { ...manageDecision, auditEventId };
    }

    const mutation = await this.client.adminUserPermission.updateMany({
      where: {
        actorUserId: normalized.targetAdminId,
        permissionKey: normalized.permissionKey,
        scope: normalized.scope,
        scopeId: normalized.scopeId,
        isActive: true,
      },
      data: {
        isActive: false,
      },
    });
    const auditEventId = await this.auditSuccess({
      actorAdminId: normalized.actorAdminId,
      action: "admin.permission.revoke",
      targetAdminId: normalized.targetAdminId,
      permissionKey: normalized.permissionKey,
      reason: normalized.reason,
      resultCode: "ADMIN_PERMISSION_REVOKED",
      metadata: {
        scope: normalized.scope,
        scopeId: normalized.scopeId,
        revokedCount: mutation.count,
        existed: mutation.count > 0,
      },
    });

    return {
      ok: true,
      code: "ADMIN_PERMISSION_REVOKED",
      message: "Permissao administrativa revogada.",
      auditEventId,
      permission: null,
      details: { revokedCount: mutation.count },
    };
  }

  async recordRouteDeniedAttempt(input: {
    actorAdminId: string;
    action: string;
    targetAdminId: string;
    permissionKey?: unknown;
    reason?: unknown;
    resultCode: string;
    message: string;
    rawPayload?: unknown;
  }) {
    const audit = await this.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorAdminId),
        targetCompanyId: null,
        action: input.action,
        details: sanitizeOperationalActionPayload({
          actorAdminId: input.actorAdminId,
          targetAdminId: input.targetAdminId,
          permissionKey: input.permissionKey ?? null,
          reason: input.reason ?? null,
          result: {
            ok: false,
            code: input.resultCode,
            message: input.message,
          },
          rawPayload: input.rawPayload ?? null,
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return audit.id;
  }

  private async ensureManagePermission(
    actorAdminId: string,
  ): Promise<AdminPermissionOperationResult> {
    const permissions = await this.client.adminUserPermission.findMany({
      where: {
        actorUserId: actorAdminId,
        isActive: true,
      },
    });
    const hasManagePermission = permissions.some(
      (permission) => permission.permissionKey === adminPermissionManagementKey,
    );

    if (hasManagePermission) {
      return {
        ok: true,
        code: "ADMIN_PERMISSION_LISTED",
        message: "Permissao de gestao administrativa concedida.",
        auditEventId: null,
      };
    }

    return {
      ok: false,
      code: "ADMIN_PERMISSION_MANAGE_REQUIRED",
      message:
        "Permissao admin-permissions.manage obrigatoria para gerenciar permissoes administrativas.",
      auditEventId: null,
      details: { requiredPermission: adminPermissionManagementKey },
    };
  }

  private normalizeMutation(input: AdminPermissionMutationInput):
    | {
        ok: true;
        actorAdminId: string;
        targetAdminId: string;
        permissionKey: AdminPermissionKey;
        reason: string;
        scope: string;
        scopeId: string;
      }
    | { ok: false; result: AdminPermissionOperationResult } {
    const actorAdminId = this.normalizeActor(input.actorAdminId);
    if (actorAdminId == null) {
      return { ok: false, result: this.actorRequired() };
    }

    const targetAdminId = input.targetAdminId.trim();
    if (targetAdminId.length === 0) {
      return {
        ok: false,
        result: this.validationError("targetAdminId obrigatorio."),
      };
    }

    const permissionKey = input.permissionKey.trim();
    if (!isKnownAdminPermissionKey(permissionKey)) {
      return {
        ok: false,
        result: {
          ok: false,
          code: "ADMIN_PERMISSION_UNSUPPORTED",
          message: "Permissao administrativa nao suportada.",
          auditEventId: null,
          details: { permissionKey },
        },
      };
    }

    const reason = input.reason.trim();
    if (reason.length < 12) {
      return {
        ok: false,
        result: this.validationError(
          "Informe um motivo com pelo menos 12 caracteres.",
        ),
      };
    }

    return {
      ok: true,
      actorAdminId,
      targetAdminId,
      permissionKey,
      reason,
      scope: input.scope?.trim() || "platform",
      scopeId: input.scopeId?.trim() || "*",
    };
  }

  private normalizeActor(actorAdminId: string | null | undefined) {
    const normalized = actorAdminId?.trim();
    return normalized == null || normalized.length === 0 ? null : normalized;
  }

  private actorRequired(): AdminPermissionOperationResult {
    return {
      ok: false,
      code: "ADMIN_PERMISSION_ACTOR_REQUIRED",
      message: "Ator administrativo obrigatorio para gerenciar permissoes.",
      auditEventId: null,
    };
  }

  private validationError(message: string): AdminPermissionOperationResult {
    return {
      ok: false,
      code: "ADMIN_PERMISSION_VALIDATION_ERROR",
      message,
      auditEventId: null,
    };
  }

  private selfGrantBlocked(permissionKey: string): AdminPermissionOperationResult {
    return {
      ok: false,
      code: "ADMIN_PERMISSION_SELF_GRANT_BLOCKED",
      message:
        "Autoconcessao de permissao critica bloqueada por padrao.",
      auditEventId: null,
      details: { permissionKey },
    };
  }

  private async auditSuccess(input: {
    actorAdminId: string;
    action: string;
    targetAdminId: string;
    permissionKey: string | null;
    reason: string | null;
    resultCode: string;
    metadata?: Record<string, unknown>;
  }) {
    const audit = await this.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorAdminId),
        targetCompanyId: null,
        action: input.action,
        details: sanitizeOperationalActionPayload({
          actorAdminId: input.actorAdminId,
          targetAdminId: input.targetAdminId,
          permissionKey: input.permissionKey,
          permissionDefinition:
            input.permissionKey == null
              ? null
              : getAdminPermissionDefinition(input.permissionKey),
          reason: input.reason,
          result: {
            ok: true,
            code: input.resultCode,
          },
          metadata: input.metadata ?? {},
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return audit.id;
  }

  private async auditDenied(input: {
    actorAdminId: string;
    action: string;
    targetAdminId: string;
    permissionKey?: string;
    reason?: string;
    result: AdminPermissionOperationResult;
  }) {
    const audit = await this.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorAdminId),
        targetCompanyId: null,
        action: input.action,
        details: sanitizeOperationalActionPayload({
          actorAdminId: input.actorAdminId,
          targetAdminId: input.targetAdminId,
          permissionKey: input.permissionKey ?? null,
          reason: input.reason ?? null,
          result: {
            ok: input.result.ok,
            code: input.result.code,
            message: input.result.message,
          },
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return audit.id;
  }
}
