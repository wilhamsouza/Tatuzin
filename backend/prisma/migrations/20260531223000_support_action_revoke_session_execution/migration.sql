-- Add an idempotent execution receipt for the first explicitly allowlisted
-- support-action pilot. This does not enable any action by itself.

CREATE TYPE "SupportActionExecutionStatus" AS ENUM ('PENDING', 'SUCCEEDED', 'FAILED');

CREATE TABLE "SupportActionExecution" (
    "id" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "requestFingerprint" TEXT NOT NULL,
    "dryRunAuditEventId" TEXT NOT NULL,
    "actionType" TEXT NOT NULL,
    "targetCompanyId" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "actorUserId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "status" "SupportActionExecutionStatus" NOT NULL DEFAULT 'PENDING',
    "beforeAuditEventId" TEXT,
    "afterAuditEventId" TEXT,
    "result" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "executedAt" TIMESTAMP(3),

    CONSTRAINT "SupportActionExecution_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SupportActionExecution_idempotencyKey_key"
    ON "SupportActionExecution"("idempotencyKey");

CREATE INDEX "SupportActionExecution_dryRunAuditEventId_idx"
    ON "SupportActionExecution"("dryRunAuditEventId");

CREATE INDEX "SupportActionExecution_actionType_targetCompanyId_targetType_targetId_idx"
    ON "SupportActionExecution"("actionType", "targetCompanyId", "targetType", "targetId");

CREATE INDEX "SupportActionExecution_actorUserId_createdAt_idx"
    ON "SupportActionExecution"("actorUserId", "createdAt");

CREATE INDEX "SupportActionExecution_status_createdAt_idx"
    ON "SupportActionExecution"("status", "createdAt");
