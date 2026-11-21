import type {
  OperationalActionType,
  SupportActionPermissionKey,
  SupportActionRiskLevel,
  SupportActionScope,
} from "../support-actions/support-actions.types";

export const adminPermissionManagementKey = "admin-permissions.manage" as const;

export type AdminPermissionManagementKey = typeof adminPermissionManagementKey;

export const tenantDeletionPermissionKeys = [
  "tenant.deletion.read",
  "tenant.deletion.request.manage",
  "tenant.deletion.identity.verify",
  "tenant.deletion.cancel",
  "tenant.deletion.quarantine",
  "tenant.deletion.execute",
] as const;

export type TenantDeletionPermissionKey =
  (typeof tenantDeletionPermissionKeys)[number];

export const adminPlatformPermissionKeys = [
  "admin.overview.read", "admin.companies.read", "admin.support.read",
  "admin.support.manage", "admin.sync.read", "admin.billing.read", "admin.billing.manage",
  "admin.devices.read", "admin.usage.read", "admin.audit.read",
] as const;

export type AdminPlatformPermissionKey = typeof adminPlatformPermissionKeys[number];

export type AdminPermissionKey =
  | AdminPlatformPermissionKey
  | SupportActionPermissionKey
  | TenantDeletionPermissionKey
  | AdminPermissionManagementKey;

export type AdminPermissionDefinition = {
  permissionKey: AdminPermissionKey;
  description: string;
  riskLevel: SupportActionRiskLevel;
  scopes: SupportActionScope[];
  category: "support-action" | "admin-permissions" | "tenant-deletion" | "platform";
  actionType?: OperationalActionType;
  requiresDryRun: boolean;
  requiresReason: boolean;
  requiresPersistentAudit: boolean;
  requiresExplicitConfirmation: boolean;
};

export type PersistedAdminPermission = {
  id: string;
  actorUserId: string;
  permissionKey: string;
  scope: string;
  scopeId: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
};

export type AdminPermissionOperationCode =
  | "ADMIN_PERMISSION_LISTED"
  | "ADMIN_PERMISSION_GRANTED"
  | "ADMIN_PERMISSION_REVOKED"
  | "ADMIN_PERMISSION_ACTOR_REQUIRED"
  | "ADMIN_PERMISSION_MANAGE_REQUIRED"
  | "ADMIN_PERMISSION_SELF_GRANT_BLOCKED"
  | "ADMIN_PERMISSION_UNSUPPORTED"
  | "ADMIN_PERMISSION_VALIDATION_ERROR";

export type AdminPermissionOperationResult = {
  ok: boolean;
  code: AdminPermissionOperationCode;
  message: string;
  auditEventId: string | null;
  permission?: PersistedAdminPermission | null;
  permissions?: PersistedAdminPermission[];
  knownPermissions?: AdminPermissionDefinition[];
  details?: unknown;
};
