-- CreateEnum
CREATE TYPE "CompanyDeletionRequestStatus" AS ENUM (
  'REQUESTED',
  'IDENTITY_PENDING',
  'VERIFIED',
  'DRY_RUN_READY',
  'CANCELLED',
  'REJECTED',
  'FUTURE_PENDING_DELETION'
);

-- CreateEnum
CREATE TYPE "IdentityVerificationStatus" AS ENUM (
  'NOT_STARTED',
  'PENDING',
  'VERIFIED',
  'FAILED'
);

-- CreateEnum
CREATE TYPE "TenantDeletionAuditEventType" AS ENUM (
  'REQUEST_CREATED',
  'IDENTITY_PENDING_SET',
  'IDENTITY_VERIFIED',
  'DRY_RUN_GENERATED',
  'REQUEST_CANCELLED',
  'REQUEST_REJECTED',
  'REQUEST_VIEWED'
);

-- CreateTable
CREATE TABLE "TenantDeletionRequest" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "activeCompanyGuard" TEXT,
  "status" "CompanyDeletionRequestStatus" NOT NULL DEFAULT 'REQUESTED',
  "requestedByAdminUserId" TEXT,
  "requestedByEmail" TEXT,
  "requestedCompanyNameSnapshot" TEXT NOT NULL,
  "source" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "identityStatus" "IdentityVerificationStatus" NOT NULL DEFAULT 'NOT_STARTED',
  "identityVerifiedByAdminUserId" TEXT,
  "identityVerifiedAt" TIMESTAMP(3),
  "identityVerificationNotes" TEXT,
  "dryRunSnapshotJson" JSONB,
  "dryRunGeneratedAt" TIMESTAMP(3),
  "cancelledByAdminUserId" TEXT,
  "cancelledAt" TIMESTAMP(3),
  "cancellationReason" TEXT,
  "rejectedByAdminUserId" TEXT,
  "rejectedAt" TIMESTAMP(3),
  "rejectionReason" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "TenantDeletionRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TenantDeletionAuditEvent" (
  "id" TEXT NOT NULL,
  "requestId" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "actorAdminUserId" TEXT,
  "eventType" "TenantDeletionAuditEventType" NOT NULL,
  "reason" TEXT,
  "beforeJson" JSONB,
  "afterJson" JSONB,
  "metadataJson" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "TenantDeletionAuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "TenantDeletionRequest_activeCompanyGuard_key"
ON "TenantDeletionRequest"("activeCompanyGuard");

-- CreateIndex
CREATE INDEX "TenantDeletionRequest_companyId_status_updatedAt_idx"
ON "TenantDeletionRequest"("companyId", "status", "updatedAt");

-- CreateIndex
CREATE INDEX "TenantDeletionRequest_status_createdAt_idx"
ON "TenantDeletionRequest"("status", "createdAt");

-- CreateIndex
CREATE INDEX "TenantDeletionRequest_requestedByAdminUserId_createdAt_idx"
ON "TenantDeletionRequest"("requestedByAdminUserId", "createdAt");

-- CreateIndex
CREATE INDEX "TenantDeletionAuditEvent_requestId_createdAt_idx"
ON "TenantDeletionAuditEvent"("requestId", "createdAt");

-- CreateIndex
CREATE INDEX "TenantDeletionAuditEvent_companyId_createdAt_idx"
ON "TenantDeletionAuditEvent"("companyId", "createdAt");

-- CreateIndex
CREATE INDEX "TenantDeletionAuditEvent_eventType_createdAt_idx"
ON "TenantDeletionAuditEvent"("eventType", "createdAt");

-- CreateIndex
CREATE INDEX "TenantDeletionAuditEvent_actorAdminUserId_createdAt_idx"
ON "TenantDeletionAuditEvent"("actorAdminUserId", "createdAt");

-- AddForeignKey
ALTER TABLE "TenantDeletionRequest"
ADD CONSTRAINT "TenantDeletionRequest_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionRequest"
ADD CONSTRAINT "TenantDeletionRequest_requestedByAdminUserId_fkey"
FOREIGN KEY ("requestedByAdminUserId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionRequest"
ADD CONSTRAINT "TenantDeletionRequest_identityVerifiedByAdminUserId_fkey"
FOREIGN KEY ("identityVerifiedByAdminUserId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionRequest"
ADD CONSTRAINT "TenantDeletionRequest_cancelledByAdminUserId_fkey"
FOREIGN KEY ("cancelledByAdminUserId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionRequest"
ADD CONSTRAINT "TenantDeletionRequest_rejectedByAdminUserId_fkey"
FOREIGN KEY ("rejectedByAdminUserId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionAuditEvent"
ADD CONSTRAINT "TenantDeletionAuditEvent_requestId_fkey"
FOREIGN KEY ("requestId") REFERENCES "TenantDeletionRequest"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionAuditEvent"
ADD CONSTRAINT "TenantDeletionAuditEvent_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenantDeletionAuditEvent"
ADD CONSTRAINT "TenantDeletionAuditEvent_actorAdminUserId_fkey"
FOREIGN KEY ("actorAdminUserId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;
