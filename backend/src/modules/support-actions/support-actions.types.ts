export const operationalActionTypes = [
  "revoke_session",
  "block_user",
  "unblock_user",
  "force_sync",
  "resolve_conflict",
  "update_license",
  "update_android_version_policy",
  "send_push_notification",
] as const;

export type OperationalActionType = (typeof operationalActionTypes)[number];

export const operationalActionTargetTypes = [
  "session",
  "user",
  "device",
  "sync",
  "conflict",
  "license",
  "android_version_policy",
  "push_notification",
  "company",
] as const;

export type OperationalActionTargetType =
  (typeof operationalActionTargetTypes)[number];

export type OperationalActionResultCode =
  | "OPERATIONAL_ACTION_DRY_RUN_READY"
  | "OPERATIONAL_ACTION_VALIDATION_ERROR"
  | "OPERATIONAL_ACTION_PERMISSION_REQUIRED"
  | "OPERATIONAL_ACTION_PERMISSION_DENIED"
  | "OPERATIONAL_ACTION_MISSING_PERMISSION"
  | "OPERATIONAL_ACTION_TARGET_NOT_FOUND"
  | "OPERATIONAL_ACTION_UNSUPPORTED"
  | "OPERATIONAL_ACTION_STATE_CONFLICT"
  | "OPERATIONAL_ACTION_AUDIT_REQUIRED"
  | "OPERATIONAL_ACTION_AUDIT_PAYLOAD_INVALID"
  | "OPERATIONAL_ACTION_ACTOR_REQUIRED"
  | "OPERATIONAL_ACTION_INTERNAL_ERROR";

export type OperationalActionResultStatus =
  | "dry_run_ready"
  | "validation_error"
  | "permission_required"
  | "permission_denied"
  | "missing_permission"
  | "target_not_found"
  | "unsupported_action"
  | "state_conflict"
  | "audit_required"
  | "audit_payload_invalid"
  | "actor_required"
  | "internal_error";

export type SupportActionPermissionKey =
  (typeof supportActionPermissionKeys)[number];

export const supportActionPermissionKeys = [
  "support.session.revoke",
  "support.user.block",
  "support.user.unblock",
  "support.sync.force",
  "support.sync.conflict.resolve",
  "support.license.update",
  "support.androidVersionPolicy.update",
  "support.push.send",
] as const;

export type SupportActionScope =
  | "platform"
  | "company"
  | "user"
  | "device"
  | "billing"
  | "sync"
  | "fcm"
  | "android_version";

export type SupportActionRiskLevel = "medium" | "high" | "critical";

export type SupportActionPermission = {
  actionType: OperationalActionType;
  permissionKey: SupportActionPermissionKey;
  description: string;
  riskLevel: SupportActionRiskLevel;
  scopes: SupportActionScope[];
  requiresDryRun: true;
  requiresExplicitConfirmation: true;
  requiresReason: true;
  requiresPersistentAudit: true;
};

export type SupportActionPermissionContext = {
  actorAdminId: string | null;
  permissionKeys?: readonly SupportActionPermissionKey[];
  isPlatformAdmin?: boolean;
  allowPlatformAdminFallback?: boolean;
};

export type SupportActionPermissionDecision = {
  allowed: boolean;
  denied: boolean;
  reason: string;
  missingPermission?: SupportActionPermissionKey;
  requiredPermission: SupportActionPermission;
  actionType: OperationalActionType;
};

export type OperationalActionAffectedEntity = {
  type: OperationalActionTargetType | "audit" | "permission" | "unknown";
  id: string;
  label?: string;
};

export type OperationalActionExpectedImpact = {
  summary: string;
  risks: string[];
  affectedEntities: OperationalActionAffectedEntity[];
  confirmationRequired: boolean;
};

export type OperationalActionResult = {
  status: OperationalActionResultStatus;
  code: OperationalActionResultCode;
  message: string;
};

export type OperationalActionAuditDraft = {
  actorAdminId: string;
  companyId: string;
  actionType: OperationalActionType;
  permissionKey: SupportActionPermissionKey;
  targetType: OperationalActionTargetType;
  targetId: string;
  dryRun: boolean;
  confirmationRequired: boolean;
  reason: string;
  result: OperationalActionResult;
  safePayload: Record<string, unknown>;
  riskLevel: SupportActionRiskLevel;
  affectedEntities: OperationalActionAffectedEntity[];
  createdAt: string;
  errorCode?: OperationalActionResultCode;
  errorMessage?: string;
};

export type OperationalActionContract = {
  actionType: OperationalActionType;
  permissionKey: SupportActionPermissionKey;
  companyId: string;
  targetType: OperationalActionTargetType;
  targetId: string;
  actorAdminId: string;
  reason: string;
  dryRun: boolean;
  confirmationRequired: boolean;
  expectedImpact: OperationalActionExpectedImpact;
  result: OperationalActionResult;
  permissionDecision: SupportActionPermissionDecision;
  auditRequired: boolean;
  auditPrepared: boolean;
  auditEventId: string | null;
  auditDraft: OperationalActionAuditDraft;
  createdAt: string;
};

export type OperationalActionApiResponse = {
  ok: boolean;
  code: OperationalActionResultCode;
  message: string;
  action?: OperationalActionContract;
  details?: unknown;
  error?: {
    code: OperationalActionResultCode;
    message: string;
    details?: unknown;
  };
};
