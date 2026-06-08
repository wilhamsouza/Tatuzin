import {
  supportActionPermissionMatrix,
} from "../support-actions/support-actions.permissions";
import {
  adminPermissionManagementKey,
  type AdminPermissionDefinition,
  type AdminPermissionKey,
  tenantDeletionPermissionKeys,
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

const tenantDeletionPermissionDefinitions: AdminPermissionDefinition[] = [
  {
    permissionKey: tenantDeletionPermissionKeys[0],
    description:
      "Permite consultar solicitacoes e inventarios read-only de exclusao de tenant.",
    riskLevel: "high",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: false,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[1],
    description:
      "Permite registrar e rejeitar solicitacoes de exclusao de tenant sem executar exclusao real.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[2],
    description:
      "Permite registrar validacao de identidade e autoridade sobre a empresa.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[3],
    description:
      "Permite cancelar solicitacao de exclusao de tenant sem alterar dados da empresa.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
];

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
  ...tenantDeletionPermissionDefinitions,
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
