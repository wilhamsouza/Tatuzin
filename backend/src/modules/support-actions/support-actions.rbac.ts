import { prisma } from "../../database/prisma";
import {
  isSupportActionPermissionKey,
} from "./support-actions.schemas";
import type {
  SupportActionPermissionContext,
  SupportActionPermissionKey,
} from "./support-actions.types";

type AdminPermissionRecord = {
  permissionKey: string;
  scope: string;
  scopeId: string;
  isActive: boolean;
};

type AdminPermissionClient = {
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

export class SupportActionRbacService {
  constructor(private readonly client: AdminPermissionClient = prisma) {}

  async getAdminPermissionKeys(
    actorAdminId: string,
  ): Promise<SupportActionPermissionKey[]> {
    const rows = await this.client.adminUserPermission.findMany({
      where: {
        actorUserId: actorAdminId,
        isActive: true,
      },
      select: {
        permissionKey: true,
        scope: true,
        scopeId: true,
        isActive: true,
      },
    });

    return [
      ...new Set(
        rows
          .map((row) => row.permissionKey)
          .filter(isSupportActionPermissionKey),
      ),
    ];
  }

  async hasSupportActionPermission(
    actorAdminId: string,
    permissionKey: SupportActionPermissionKey,
  ) {
    const permissionKeys = await this.getAdminPermissionKeys(actorAdminId);
    return permissionKeys.includes(permissionKey);
  }

  async getSupportActionPermissionContext(
    actorAdminId: string,
  ): Promise<SupportActionPermissionContext> {
    return {
      actorAdminId,
      permissionKeys: await this.getAdminPermissionKeys(actorAdminId),
      allowPlatformAdminFallback: false,
    };
  }
}
