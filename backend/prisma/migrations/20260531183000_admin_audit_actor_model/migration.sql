-- Add explicit audit actor metadata without changing existing log semantics.
-- Existing rows remain USER-authored through the default value and their current actorUserId.

CREATE TYPE "AdminAuditActorType" AS ENUM ('USER', 'SYSTEM', 'BOOTSTRAP', 'SERVICE');

ALTER TABLE "AdminAuditLog"
  ADD COLUMN "actorType" "AdminAuditActorType" NOT NULL DEFAULT 'USER',
  ADD COLUMN "actorLabel" TEXT;

ALTER TABLE "AdminAuditLog"
  ALTER COLUMN "actorUserId" DROP NOT NULL;

CREATE INDEX "AdminAuditLog_actorType_idx" ON "AdminAuditLog"("actorType");
CREATE INDEX "AdminAuditLog_actorUserId_idx" ON "AdminAuditLog"("actorUserId");
