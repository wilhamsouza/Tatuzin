-- Additive V3 employee cash coordinator. Legacy rows retain workspaceVersion=1.
ALTER TABLE "CashSession" ADD COLUMN "workspaceVersion" INTEGER NOT NULL DEFAULT 1,
 ADD COLUMN "workspaceRevision" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "workspaceClosureGeneration" INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX "CashSession_one_active_employee_workspace" ON "CashSession"("companyId","userId") WHERE "workspaceVersion"=3 AND "status"='open';
CREATE TABLE "CashWorkspaceParticipant" (
 "id" TEXT PRIMARY KEY,"companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
 "sessionId" TEXT NOT NULL REFERENCES "CashSession"("id") ON DELETE CASCADE,
 "userId" TEXT NOT NULL REFERENCES "User"("id") ON DELETE RESTRICT,
 "deviceId" TEXT NOT NULL REFERENCES "CompanyDevice"("id") ON DELETE RESTRICT,
 "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"lastAckGeneration" INTEGER);
CREATE UNIQUE INDEX "CashWorkspaceParticipant_sessionId_deviceId_key" ON "CashWorkspaceParticipant"("sessionId","deviceId");
CREATE INDEX "CashWorkspaceParticipant_companyId_userId_idx" ON "CashWorkspaceParticipant"("companyId","userId");
CREATE TABLE "CashClosureRequest" (
 "id" TEXT PRIMARY KEY,"companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
 "sessionId" TEXT NOT NULL REFERENCES "CashSession"("id") ON DELETE CASCADE,
 "userId" TEXT NOT NULL REFERENCES "User"("id") ON DELETE RESTRICT,"requestId" TEXT NOT NULL,
 "generation" INTEGER NOT NULL,"ledgerRevision" INTEGER NOT NULL,"status" TEXT NOT NULL,
 "countedBalanceCents" INTEGER NOT NULL,"localExpectedBalanceCents" INTEGER NOT NULL,
 "expectedBalanceCents" INTEGER NOT NULL,"differenceCents" INTEGER NOT NULL,
 "reason" TEXT,"notes" TEXT,"originalCount" JSONB NOT NULL,"requestFingerprint" TEXT NOT NULL,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "CashClosureRequest_status_check" CHECK ("status" IN ('PENDING_SYNC','REVIEW_REQUIRED','CLOSED','SUPERSEDED')));
CREATE UNIQUE INDEX "CashClosureRequest_companyId_requestId_key" ON "CashClosureRequest"("companyId","requestId");
CREATE UNIQUE INDEX "CashClosureRequest_sessionId_generation_key" ON "CashClosureRequest"("sessionId","generation");
CREATE INDEX "CashClosureRequest_companyId_status_idx" ON "CashClosureRequest"("companyId","status");
CREATE TABLE "CashClosureAck" (
 "id" TEXT PRIMARY KEY,"closureId" TEXT NOT NULL REFERENCES "CashClosureRequest"("id") ON DELETE CASCADE,
 "deviceId" TEXT NOT NULL REFERENCES "CompanyDevice"("id") ON DELETE RESTRICT,
 "generation" INTEGER NOT NULL,"ledgerRevision" INTEGER NOT NULL,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE UNIQUE INDEX "CashClosureAck_closureId_deviceId_generation_key" ON "CashClosureAck"("closureId","deviceId","generation");
