export const revokeSessionExecutionActionType = "revoke_session" as const;
export const revokeSessionExecutionTargetType = "session" as const;
export const revokeSessionConfirmationText = "REVOGAR_SESSAO" as const;

export type SupportActionExecutionCode =
  | "SUPPORT_ACTION_EXECUTED"
  | "SUPPORT_ACTION_IDEMPOTENT_REPLAY"
  | "SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR"
  | "SUPPORT_ACTION_EXECUTION_ACTOR_REQUIRED"
  | "SUPPORT_ACTION_EXECUTION_DISABLED"
  | "SUPPORT_ACTION_EXECUTION_PERMISSION_DENIED"
  | "SUPPORT_ACTION_EXECUTION_DRY_RUN_REQUIRED"
  | "SUPPORT_ACTION_EXECUTION_DRY_RUN_EXPIRED"
  | "SUPPORT_ACTION_EXECUTION_DRY_RUN_MISMATCH"
  | "SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND"
  | "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT"
  | "SUPPORT_ACTION_EXECUTION_UNSUPPORTED"
  | "SUPPORT_ACTION_EXECUTION_INTERNAL_ERROR";

export type RevokeSessionExecutionContract = {
  id: string;
  actionType: typeof revokeSessionExecutionActionType;
  companyId: string;
  targetType: typeof revokeSessionExecutionTargetType;
  targetId: string;
  target: {
    type: typeof revokeSessionExecutionTargetType;
    id: string;
    companyId: string;
  };
  actorAdminId: string;
  dryRunAuditEventId: string;
  correlationId: string;
  idempotencyKey: string;
  status: "succeeded" | "idempotent_replay";
  result: {
    status: "succeeded" | "idempotent_replay";
    effectApplied: true;
  };
  auditBeforeId: string | null;
  auditAfterId: string | null;
  beforeAuditEventId: string | null;
  afterAuditEventId: string | null;
  executedAt: string | null;
};

export type SupportActionExecutionResponse = {
  ok: boolean;
  code: SupportActionExecutionCode;
  message: string;
  execution?: RevokeSessionExecutionContract;
  details?: unknown;
  error?: {
    code: SupportActionExecutionCode;
    message: string;
    details?: unknown;
  };
};
