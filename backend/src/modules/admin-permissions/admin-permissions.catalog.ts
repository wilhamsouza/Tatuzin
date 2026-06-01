import {
  supportActionPermissionMatrix,
} from "../support-actions/support-actions.permissions";
import {
  adminPermissionManagementKey,
  type AdminPermissionDefinition,
  type AdminPermissionKey,
} from "./admin-permissions.types";

const supportActionPermissionDefinitions: AdminPermissionDefinition[] =
  Object.values(supportActionPermissionMatrix).map((permission) => ({
    permissionKey: permission.permissionKey,
    description: permission.description,
    riskLevel: permission.riskLevel,
    scopes: permission.scopes,
    category: "support-action",
    actionType: permission.actionType,
    requiresDryRun: permission.requiresDryRun,
    requiresReason: permission.requiresReason,
    requiresPersistentAudit: permission.requiresPersistentAudit,
    requiresExplicitConfirmation: permission.requiresExplicitConfirmation,
  }));

export const adminPermissionDefinitions: AdminPermissionDefinition[] = [
  {
    permissionKey: adminPermissionManagementKey,
    description:
      "Permite conceder, revogar e consultar permissoes administrativas persistidas.",
    riskLevel: "critical",
    scopes: ["platform"],
    category: "admin-permissions",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: true,
  },
  ...supportActionPermissionDefinitions,
];

export function listKnownAdminPermissions() {
  return adminPermissionDefinitions;
}

export function getAdminPermissionDefinition(permissionKey: string) {
  return adminPermissionDefinitions.find(
    (permission) => permission.permissionKey === permissionKey,
  );
}

export function isKnownAdminPermissionKey(
  permissionKey: string,
): permissionKey is AdminPermissionKey {
  return getAdminPermissionDefinition(permissionKey) != null;
}

export function isCriticalAdminPermission(permissionKey: string) {
  const definition = getAdminPermissionDefinition(permissionKey);
  return (
    definition?.riskLevel === "critical" || definition?.riskLevel === "high"
  );
}
