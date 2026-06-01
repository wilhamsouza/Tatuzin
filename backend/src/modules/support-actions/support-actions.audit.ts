import {
  type OperationalActionAffectedEntity,
  type OperationalActionAuditDraft,
  type OperationalActionResult,
  type OperationalActionResultCode,
  type OperationalActionTargetType,
  type OperationalActionType,
  type SupportActionPermissionDecision,
} from "./support-actions.types";

export type SupportActionAuditDraftInput = {
  actorAdminId: string;
  companyId: string;
  actionType: OperationalActionType;
  targetType: OperationalActionTargetType;
  targetId: string;
  dryRun: boolean;
  confirmationRequired: boolean;
  reason: string;
  result: OperationalActionResult;
  safePayload: Record<string, unknown>;
  affectedEntities: OperationalActionAffectedEntity[];
  permissionDecision: SupportActionPermissionDecision;
  createdAt: string;
  errorCode?: OperationalActionResultCode;
  errorMessage?: string;
};

export type AdminAuditLogDraft = {
  actorType: "USER";
  actorUserId: string;
  actorLabel: null;
  targetCompanyId: string;
  action: string;
  details: Record<string, unknown>;
};

export function buildSupportActionAuditDraft(
  input: SupportActionAuditDraftInput,
): OperationalActionAuditDraft {
  return {
    actorAdminId: input.actorAdminId,
    companyId: input.companyId,
    actionType: input.actionType,
    permissionKey: input.permissionDecision.requiredPermission.permissionKey,
    targetType: input.targetType,
    targetId: input.targetId,
    dryRun: input.dryRun,
    confirmationRequired: input.confirmationRequired,
    reason: input.reason,
    result: input.result,
    safePayload: input.safePayload,
    riskLevel: input.permissionDecision.requiredPermission.riskLevel,
    affectedEntities: input.affectedEntities,
    createdAt: input.createdAt,
    errorCode: input.errorCode,
    errorMessage: input.errorMessage,
  };
}

export function mapSupportActionAuditToAdminAuditLog(
  draft: OperationalActionAuditDraft,
): AdminAuditLogDraft {
  return {
    actorType: "USER",
    actorUserId: draft.actorAdminId,
    actorLabel: null,
    targetCompanyId: draft.companyId,
    action: `support.${draft.actionType}.dry_run`,
    details: {
      actionType: draft.actionType,
      permissionKey: draft.permissionKey,
      targetType: draft.targetType,
      targetId: draft.targetId,
      dryRun: draft.dryRun,
      confirmationRequired: draft.confirmationRequired,
      reason: draft.reason,
      result: draft.result,
      safePayload: draft.safePayload,
      riskLevel: draft.riskLevel,
      affectedEntities: draft.affectedEntities,
      errorCode: draft.errorCode ?? null,
      errorMessage: draft.errorMessage ?? null,
      createdAt: draft.createdAt,
    },
  };
}
