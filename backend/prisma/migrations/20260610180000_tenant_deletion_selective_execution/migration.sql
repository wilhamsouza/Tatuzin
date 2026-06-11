ALTER TYPE "CompanyDeletionRequestStatus" ADD VALUE 'EXECUTION_IN_PROGRESS';
ALTER TYPE "CompanyDeletionRequestStatus" ADD VALUE 'DELETION_EXECUTED';

ALTER TYPE "TenantDeletionAuditEventType" ADD VALUE 'EXECUTION_STARTED';
ALTER TYPE "TenantDeletionAuditEventType" ADD VALUE 'EXECUTION_CATEGORY_COMPLETED';
ALTER TYPE "TenantDeletionAuditEventType" ADD VALUE 'EXECUTION_FAILED';
ALTER TYPE "TenantDeletionAuditEventType" ADD VALUE 'EXECUTION_COMPLETED';

ALTER TABLE "TenantDeletionRequest"
  ADD COLUMN "executionPlanJson" JSONB,
  ADD COLUMN "executionProgressJson" JSONB,
  ADD COLUMN "executionReceiptJson" JSONB,
  ADD COLUMN "executionStartedAt" TIMESTAMP(3),
  ADD COLUMN "executionCompletedAt" TIMESTAMP(3),
  ADD COLUMN "executionAttemptId" TEXT,
  ADD COLUMN "executionLockedAt" TIMESTAMP(3),
  ADD COLUMN "executedByAdminUserId" TEXT;

ALTER TABLE "TenantDeletionRequest"
  ADD CONSTRAINT "TenantDeletionRequest_executedByAdminUserId_fkey"
  FOREIGN KEY ("executedByAdminUserId") REFERENCES "User"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
