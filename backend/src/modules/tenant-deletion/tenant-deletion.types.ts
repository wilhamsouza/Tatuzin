import type { Prisma } from "@prisma/client";

import type { TenantDeletionPermissionKey } from "../admin-permissions/admin-permissions.types";

export const tenantDeletionStatuses = [
  "REQUESTED",
  "IDENTITY_PENDING",
  "VERIFIED",
  "DRY_RUN_READY",
  "PENDING_DELETION",
  "CANCELLED",
  "EXECUTION_PENDING",
  "COMPLETED",
  "REJECTED",
] as const;

export type TenantDeletionStatus = (typeof tenantDeletionStatuses)[number];

export type TenantDeletionAction =
  | "tenant.deletion.requested"
  | "tenant.deletion.identity_pending"
  | "tenant.deletion.verified"
  | "tenant.deletion.dry_run"
  | "tenant.deletion.cancelled"
  | "tenant.deletion.rejected";

export type TenantDeletionOperationCode =
  | "TENANT_DELETION_REQUEST_LISTED"
  | "TENANT_DELETION_REQUEST_RECORDED"
  | "TENANT_DELETION_IDENTITY_PENDING_RECORDED"
  | "TENANT_DELETION_IDENTITY_VERIFIED"
  | "TENANT_DELETION_DRY_RUN_READY"
  | "TENANT_DELETION_CANCELLED"
  | "TENANT_DELETION_REJECTED"
  | "TENANT_DELETION_ACTOR_REQUIRED"
  | "TENANT_DELETION_PERMISSION_REQUIRED"
  | "TENANT_DELETION_REASON_REQUIRED"
  | "TENANT_DELETION_COMPANY_REQUIRED"
  | "TENANT_DELETION_REQUEST_REQUIRED"
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
  persistenceMode: "admin_audit_log_foundation";
  categories: TenantDeletionInventoryCategory[];
  blockers: TenantDeletionBlocker[];
  notes: string[];
};

export type TenantDeletionRequestSummary = {
  requestId: string;
  company: TenantDeletionCompanySummary | null;
  status: TenantDeletionStatus;
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

export type TenantDeletionAdminAuditEvent = {
  id: string;
  action: string;
  createdAt: Date;
  targetCompanyId: string | null;
  details: Prisma.JsonValue | null;
  targetCompany?: {
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
  } | null;
};
