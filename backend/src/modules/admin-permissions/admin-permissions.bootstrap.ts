import { Prisma } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { bootstrapAdminAuditActor } from "../admin/admin-audit-actor";
import { sanitizeOperationalActionPayload } from "../support-actions/support-actions.service";
import { adminPermissionManagementKey } from "./admin-permissions.types";

export const adminPermissionBootstrapEnvKey =
  "ADMIN_PERMISSION_BOOTSTRAP_ENABLED" as const;

export const adminPermissionBootstrapAllowedPermissions = [
  adminPermissionManagementKey,
] as const;

export type AdminPermissionBootstrapAllowedPermission =
  (typeof adminPermissionBootstrapAllowedPermissions)[number];

export type AdminPermissionBootstrapCode =
  | "ADMIN_PERMISSION_BOOTSTRAP_GRANTED"
  | "ADMIN_PERMISSION_BOOTSTRAP_DISABLED"
  | "ADMIN_PERMISSION_BOOTSTRAP_REASON_REQUIRED"
  | "ADMIN_PERMISSION_BOOTSTRAP_TARGET_REQUIRED"
  | "ADMIN_PERMISSION_BOOTSTRAP_TARGET_NOT_FOUND"
  | "ADMIN_PERMISSION_BOOTSTRAP_TARGET_NOT_ADMIN"
  | "ADMIN_PERMISSION_BOOTSTRAP_PERMISSION_UNSUPPORTED"
  | "ADMIN_PERMISSION_BOOTSTRAP_ALREADY_CONFIGURED";

export type AdminPermissionBootstrapResult = {
  ok: boolean;
  code: AdminPermissionBootstrapCode;
  message: string;
  auditEventIds: string[];
  permission?: {
    id: string;
    actorUserId: string;
    permissionKey: string;
    scope: string;
    scopeId: string;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
  } | null;
  details?: unknown;
};

type BootstrapTarget = {
  id: string;
  email: string;
  name: string;
  isActive: boolean;
  isPlatformAdmin: boolean;
};

type BootstrapPermissionRecord = {
  id: string;
  actorUserId: string;
  permissionKey: string;
  scope: string;
  scopeId: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
};

type AdminPermissionBootstrapClient = {
  user: {
    findFirst(input: {
      where: {
        OR: Array<{ id: string } | { email: string }>;
      };
      select: {
        id: true;
        email: true;
        name: true;
        isActive: true;
        isPlatformAdmin: true;
      };
    }): Promise<BootstrapTarget | null>;
  };
  adminUserPermission: {
    findMany(input: {
      where: {
        permissionKey: string;
        isActive: boolean;
      };
    }): Promise<BootstrapPermissionRecord[]>;
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
    }): Promise<BootstrapPermissionRecord>;
  };
  adminAuditLog: {
    create(input: {
      data: {
        actorType: "BOOTSTRAP";
        actorUserId: string | null;
        actorLabel: string;
        targetCompanyId?: string | null;
        action: string;
        details?: Prisma.InputJsonValue;
      };
      select: { id: true };
    }): Promise<{ id: string }>;
  };
};

export type AdminPermissionBootstrapInput = {
  targetAdminId?: string | null;
  targetEmail?: string | null;
  permissionKey?: string | null;
  reason?: string | null;
  env?: Record<string, string | undefined>;
};

type DenialInput = {
  code: Exclude<
    AdminPermissionBootstrapCode,
    "ADMIN_PERMISSION_BOOTSTRAP_GRANTED"
  >;
  message: string;
  target: BootstrapTarget | null;
  targetIdentifier: Record<string, string | null>;
  permissionKey: string;
  reason: string | null;
  attemptedAuditId: string;
  details?: Record<string, unknown>;
};

export class AdminPermissionBootstrapService {
  constructor(private readonly client: AdminPermissionBootstrapClient = prisma) {}

  async bootstrapManagePermission(
    input: AdminPermissionBootstrapInput,
  ): Promise<AdminPermissionBootstrapResult> {
    const targetAdminId = normalizeOptional(input.targetAdminId);
    const targetEmail = normalizeOptional(input.targetEmail)?.toLowerCase() ?? null;
    const targetIdentifier = { targetAdminId, targetEmail };
    const permissionKey =
      normalizeOptional(input.permissionKey) ?? adminPermissionManagementKey;
    const reason = normalizeOptional(input.reason);

    if (targetAdminId == null && targetEmail == null) {
      const attemptedAuditId = await this.audit({
        action: "admin_permissions.bootstrap.attempted",
        target: null,
        targetIdentifier,
        permissionKey,
        reason,
        result: {
          ok: false,
          code: "ADMIN_PERMISSION_BOOTSTRAP_ATTEMPTED",
          message: "Tentativa de bootstrap registrada.",
        },
      });
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_TARGET_REQUIRED",
        message: "Informe adminUserId ou email do AdminUser alvo.",
        target: null,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
      });
    }

    const target = await this.findTarget(targetAdminId, targetEmail);
    const attemptedAuditId = await this.audit({
      action: "admin_permissions.bootstrap.attempted",
      target,
      targetIdentifier,
      permissionKey,
      reason,
      result: {
        ok: false,
        code: "ADMIN_PERMISSION_BOOTSTRAP_ATTEMPTED",
        message: "Tentativa de bootstrap registrada.",
      },
    });

    if (target == null) {
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_TARGET_NOT_FOUND",
        message: "AdminUser alvo nao encontrado.",
        target,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
      });
    }

    if (!isBootstrapEnabled(input.env ?? process.env)) {
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_DISABLED",
        message:
          "Bootstrap bloqueado. Defina ADMIN_PERMISSION_BOOTSTRAP_ENABLED=true em ambiente controlado.",
        target,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
      });
    }

    if (reason == null || reason.length < 12) {
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_REASON_REQUIRED",
        message: "Informe um motivo com pelo menos 12 caracteres.",
        target,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
      });
    }

    if (!isBootstrapAllowedPermission(permissionKey)) {
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_PERMISSION_UNSUPPORTED",
        message:
          "Bootstrap permite somente permissoes administrativas explicitamente liberadas.",
        target,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
        details: {
          allowedPermissions: [...adminPermissionBootstrapAllowedPermissions],
        },
      });
    }

    if (!target.isPlatformAdmin || !target.isActive) {
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_TARGET_NOT_ADMIN",
        message:
          "Bootstrap exige AdminUser alvo ativo com isPlatformAdmin=true.",
        target,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
        details: {
          isPlatformAdmin: target.isPlatformAdmin,
          isActive: target.isActive,
        },
      });
    }

    const existingManagers = await this.client.adminUserPermission.findMany({
      where: {
        permissionKey: adminPermissionManagementKey,
        isActive: true,
      },
    });

    if (existingManagers.length > 0) {
      return this.deny({
        code: "ADMIN_PERMISSION_BOOTSTRAP_ALREADY_CONFIGURED",
        message:
          "Bootstrap bloqueado porque ja existe admin-permissions.manage ativo.",
        target,
        targetIdentifier,
        permissionKey,
        reason,
        attemptedAuditId,
        details: {
          activeManagers: existingManagers.map((permission) => ({
            actorUserId: permission.actorUserId,
            scope: permission.scope,
            scopeId: permission.scopeId,
          })),
        },
      });
    }

    const permission = await this.client.adminUserPermission.upsert({
      where: {
        actorUserId_permissionKey_scope_scopeId: {
          actorUserId: target.id,
          permissionKey,
          scope: "platform",
          scopeId: "*",
        },
      },
      create: {
        actorUserId: target.id,
        permissionKey,
        scope: "platform",
        scopeId: "*",
        isActive: true,
      },
      update: {
        isActive: true,
      },
    });
    const grantedAuditId = await this.audit({
      action: "admin_permissions.bootstrap.granted",
      target,
      targetIdentifier,
      permissionKey,
      reason,
      result: {
        ok: true,
        code: "ADMIN_PERMISSION_BOOTSTRAP_GRANTED",
        message: "Bootstrap concedido.",
      },
    });

    return {
      ok: true,
      code: "ADMIN_PERMISSION_BOOTSTRAP_GRANTED",
      message: "Permissao admin-permissions.manage concedida por bootstrap.",
      auditEventIds: [attemptedAuditId, grantedAuditId],
      permission,
    };
  }

  private async deny(input: DenialInput): Promise<AdminPermissionBootstrapResult> {
    const deniedAuditId = await this.audit({
      action: "admin_permissions.bootstrap.denied",
      target: input.target,
      targetIdentifier: input.targetIdentifier,
      permissionKey: input.permissionKey,
      reason: input.reason,
      result: {
        ok: false,
        code: input.code,
        message: input.message,
      },
      details: input.details,
    });

    return {
      ok: false,
      code: input.code,
      message: input.message,
      auditEventIds: [input.attemptedAuditId, deniedAuditId],
      details: input.details,
    };
  }

  private async findTarget(targetAdminId: string | null, targetEmail: string | null) {
    const OR: Array<{ id: string } | { email: string }> = [];
    if (targetAdminId != null) {
      OR.push({ id: targetAdminId });
    }
    if (targetEmail != null) {
      OR.push({ email: targetEmail });
    }

    return this.client.user.findFirst({
      where: { OR },
      select: {
        id: true,
        email: true,
        name: true,
        isActive: true,
        isPlatformAdmin: true,
      },
    });
  }

  private async audit(input: {
    action: string;
    target: BootstrapTarget | null;
    targetIdentifier: Record<string, string | null>;
    permissionKey: string;
    reason: string | null;
    result: Record<string, unknown>;
    details?: Record<string, unknown>;
  }) {
    const audit = await this.client.adminAuditLog.create({
      data: {
        ...bootstrapAdminAuditActor(),
        targetCompanyId: null,
        action: input.action,
        details: sanitizeOperationalActionPayload({
          systemActor: "SYSTEM_BOOTSTRAP",
          target:
            input.target == null
              ? null
              : {
                  id: input.target.id,
                  email: input.target.email,
                  name: input.target.name,
                  isActive: input.target.isActive,
                  isPlatformAdmin: input.target.isPlatformAdmin,
                },
          targetIdentifier: input.targetIdentifier,
          permissionKey: input.permissionKey,
          reason: input.reason,
          result: input.result,
          details: input.details ?? {},
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return audit.id;
  }
}

export function isBootstrapEnabled(env: Record<string, string | undefined>) {
  return env[adminPermissionBootstrapEnvKey]?.trim().toLowerCase() === "true";
}

export function isBootstrapAllowedPermission(
  permissionKey: string,
): permissionKey is AdminPermissionBootstrapAllowedPermission {
  return adminPermissionBootstrapAllowedPermissions.includes(
    permissionKey as AdminPermissionBootstrapAllowedPermission,
  );
}

function normalizeOptional(value: string | null | undefined) {
  const normalized = value?.trim();
  return normalized == null || normalized.length === 0 ? null : normalized;
}
