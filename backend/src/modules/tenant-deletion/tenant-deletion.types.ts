import type { Prisma } from "@prisma/client";

import type { TenantDeletionPermissionKey } from "../admin-permissions/admin-permissions.types";

export const tenantDeletionStatuses = [
  "REQUESTED",
  "IDENTITY_PENDING",
  "VERIFIED",
  "DRY_RUN_READY",
  "CANCELLED",
  "REJECTED",
  "FUTURE_PENDING_DELETION",
  "EXECUTION_IN_PROGRESS",
  "DELETION_EXECUTED",
] as const;

export type TenantDeletionStatus = (typeof tenantDeletionStatuses)[number];

export type TenantDeletionAction =
  | "tenant.deletion.requested"
  | "tenant.deletion.identity_pending"
  | "tenant.deletion.verified"
  | "tenant.deletion.dry_run"
  | "tenant.deletion.quarantined"
  | "tenant.deletion.quarantine_cancelled"
  | "tenant.deletion.cancelled"
  | "tenant.deletion.rejected"
  | "tenant.deletion.execution_started"
  | "tenant.deletion.execution_category_completed"
  | "tenant.deletion.execution_failed"
  | "tenant.deletion.execution_completed";

export type TenantDeletionOperationCode =
  | "TENANT_DELETION_REQUEST_LISTED"
  | "TENANT_DELETION_REQUEST_FOUND"
  | "TENANT_DELETION_REQUEST_RECORDED"
  | "TENANT_DELETION_IDENTITY_PENDING_RECORDED"
  | "TENANT_DELETION_IDENTITY_VERIFIED"
  | "TENANT_DELETION_DRY_RUN_READY"
  | "TENANT_DELETION_QUARANTINED"
  | "TENANT_DELETION_CANCELLED"
  | "TENANT_DELETION_REJECTED"
  | "TENANT_DELETION_EXECUTED"
  | "TENANT_DELETION_EXECUTION_DISABLED"
  | "TENANT_DELETION_ACTOR_REQUIRED"
  | "TENANT_DELETION_PERMISSION_REQUIRED"
  | "TENANT_DELETION_REASON_REQUIRED"
  | "TENANT_DELETION_COMPANY_REQUIRED"
  | "TENANT_DELETION_REQUEST_REQUIRED"
  | "TENANT_DELETION_REQUEST_NOT_FOUND"
  | "TENANT_DELETION_STATE_CONFLICT"
  | "TENANT_DELETION_COMPANY_NOT_FOUND"
  | "TENANT_DELETION_VALIDATION_ERROR";

export type TenantDeletionCompanySummary = {
  id: string;
  name: string;
  legalName: string;
  slug: string;
  documentNumber: string | null;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  license: {
    status: string;
    plan: string;
    syncEnabled: boolean;
    billingProvider: string | null;
    hasProviderSubscription: boolean;
    cancelAtPeriodEnd: boolean;
    cancelRequestedAt: string | null;
    canceledAt: string | null;
    billingSubscriptionStatus: string | null;
  } | null;
};

export type TenantDeletionInventoryCategory = {
  key: string;
  label: string;
  count: number;
  recommendedHandling:
    | "delete_eligible"
    | "anonymize"
    | "deactivate"
    | "retain_justified"
    | "review_required";
  retentionReason: string | null;
};

export type TenantDeletionBlocker = {
  key: string;
  severity: "info" | "warning" | "blocking";
  message: string;
  count?: number;
};

export type TenantDeletionDryRun = {
  company: TenantDeletionCompanySummary;
  generatedAt: string;
  dryRun: true;
  persistenceMode: "tenant_deletion_request";
  categories: TenantDeletionInventoryCategory[];
  blockers: TenantDeletionBlocker[];
  notes: string[];
};

export type TenantDeletionRequestSummary = {
  requestId: string;
  company: TenantDeletionCompanySummary | null;
  status: TenantDeletionStatus;
  identityStatus: "NOT_STARTED" | "PENDING" | "VERIFIED" | "FAILED";
  source: string;
  createdAt: string;
  updatedAt: string;
  latestAuditEventId: string;
  latestAction: TenantDeletionAction | string;
  reason: string | null;
  requester: {
    name: string | null;
    email: string | null;
    channel: string | null;
  };
  dryRunSummary: {
    categories: number;
    blockers: number;
  } | null;
  executionSummary: {
    completedCategories: string[];
    failedCategory: string | null;
    startedAt: string | null;
    completedAt: string | null;
  } | null;
};

export type TenantDeletionOperationResult = {
  ok: boolean;
  code: TenantDeletionOperationCode;
  message: string;
  auditEventId: string | null;
  requiredPermission?: TenantDeletionPermissionKey;
  request?: TenantDeletionRequestSummary;
  requests?: TenantDeletionRequestSummary[];
  dryRun?: TenantDeletionDryRun;
  details?: unknown;
};

export type TenantDeletionAuditDetails = {
  requestId: string;
  status: TenantDeletionStatus;
  reason: string;
  requester?: {
    name?: string | null;
    email?: string | null;
    channel?: string | null;
  };
  metadata?: Record<string, unknown>;
  dryRun?: {
    categories: number;
    blockers: number;
    blockerKeys: string[];
  };
};

export type TenantDeletionPersistedRequest = {
  id: string;
  companyId: string;
  activeCompanyGuard: string | null;
  status: TenantDeletionStatus;
  requestedByAdminUserId: string | null;
  requestedByEmail: string | null;
  requestedCompanyNameSnapshot: string;
  source: string;
  reason: string;
  identityStatus: "NOT_STARTED" | "PENDING" | "VERIFIED" | "FAILED";
  identityVerifiedByAdminUserId: string | null;
  identityVerifiedAt: Date | null;
  identityVerificationNotes: string | null;
  dryRunSnapshotJson: Prisma.JsonValue | null;
  dryRunGeneratedAt: Date | null;
  cancelledByAdminUserId: string | null;
  cancelledAt: Date | null;
  cancellationReason: string | null;
  rejectedByAdminUserId: string | null;
  rejectedAt: Date | null;
  rejectionReason: string | null;
  executionPlanJson: Prisma.JsonValue | null;
  executionProgressJson: Prisma.JsonValue | null;
  executionReceiptJson: Prisma.JsonValue | null;
  executionStartedAt: Date | null;
  executionCompletedAt: Date | null;
  executionAttemptId: string | null;
  executionLockedAt: Date | null;
  executedByAdminUserId: string | null;
  createdAt: Date;
  updatedAt: Date;
  company: {
    id: string;
    name: string;
    legalName: string;
    documentNumber: string | null;
    slug: string;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
    license: {
      status: string;
      plan: string;
      syncEnabled: boolean;
      billingProvider: string | null;
      providerSubscriptionId: string | null;
      cancelAtPeriodEnd: boolean;
      cancelRequestedAt: Date | null;
      canceledAt: Date | null;
      billingSubscriptionStatus: string | null;
    } | null;
  };
  auditEvents: Array<{
    id: string;
    eventType: string;
    reason: string | null;
    createdAt: Date;
  }>;
};
