import { prisma } from "../../database/prisma";
import type { TenantDeletionPermissionKey } from "../admin-permissions/admin-permissions.types";

type AdminPermissionRecord = {
  permissionKey: string;
  scope: string;
  scopeId: string;
  isActive: boolean;
};

type TenantDeletionRbacClient = {
  adminUserPermission: {
    findMany(input: {
      where: { actorUserId: string; isActive: boolean };
      select: {
        permissionKey: true;
        scope: true;
        scopeId: true;
        isActive: true;
      };
    }): Promise<AdminPermissionRecord[]>;
  };
};

export class TenantDeletionRbacService {
  constructor(private readonly client: TenantDeletionRbacClient = prisma) {}

  async hasPermission(input: {
    actorAdminId: string;
    permissionKey: TenantDeletionPermissionKey;
    companyId?: string | null;
  }) {
    const permissions = await this.client.adminUserPermission.findMany({
      where: {
        actorUserId: input.actorAdminId,
        isActive: true,
      },
      select: {
        permissionKey: true,
        scope: true,
        scopeId: true,
        isActive: true,
      },
    });

    return permissions.some((permission) => {
      if (permission.permissionKey !== input.permissionKey) {
        return false;
      }
      if (permission.scope === "platform" && permission.scopeId === "*") {
        return true;
      }
      if (input.companyId == null || input.companyId.trim() === "") {
        return false;
      }
      return (
        permission.scope === "company" && permission.scopeId === input.companyId
      );
    });
  }
}
