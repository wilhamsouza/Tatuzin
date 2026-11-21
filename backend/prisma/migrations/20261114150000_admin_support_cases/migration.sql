CREATE TABLE "AdminSupportCase" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "priority" TEXT NOT NULL DEFAULT 'NORMAL',
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "assigneeId" TEXT,
  "creatorId" TEXT NOT NULL,
  "revision" INTEGER NOT NULL DEFAULT 0,
  "evidenceType" TEXT,
  "evidenceId" TEXT,
  "evidenceKey" TEXT,
  "activeEvidenceKey" TEXT,
  "requestKey" TEXT NOT NULL,
  "resolution" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "AdminSupportCase_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "AdminSupportCase_status_check" CHECK ("status" IN ('OPEN','IN_PROGRESS','WAITING','RESOLVED')),
  CONSTRAINT "AdminSupportCase_priority_check" CHECK ("priority" IN ('CRITICAL','HIGH','NORMAL','LOW')),
  CONSTRAINT "AdminSupportCase_resolution_check" CHECK ("status" <> 'RESOLVED' OR ("resolution" IS NOT NULL AND length(trim("resolution")) > 0)),
  CONSTRAINT "AdminSupportCase_revision_check" CHECK ("revision" >= 0)
);
CREATE TABLE "AdminSupportCaseEvent" (
  "id" TEXT NOT NULL,
  "caseId" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "details" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminSupportCaseEvent_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AdminSupportCase_activeEvidenceKey_key" ON "AdminSupportCase"("activeEvidenceKey");
CREATE UNIQUE INDEX "AdminSupportCase_companyId_requestKey_key" ON "AdminSupportCase"("companyId", "requestKey");
CREATE UNIQUE INDEX "AdminSupportCase_id_companyId_key" ON "AdminSupportCase"("id", "companyId");
CREATE INDEX "AdminSupportCase_companyId_status_updatedAt_idx" ON "AdminSupportCase"("companyId", "status", "updatedAt");
CREATE INDEX "AdminSupportCase_assigneeId_status_updatedAt_idx" ON "AdminSupportCase"("assigneeId", "status", "updatedAt");
CREATE INDEX "AdminSupportCase_status_priority_createdAt_idx" ON "AdminSupportCase"("status", "priority", "createdAt");
CREATE INDEX "AdminSupportCaseEvent_companyId_caseId_createdAt_idx" ON "AdminSupportCaseEvent"("companyId", "caseId", "createdAt");
ALTER TABLE "AdminSupportCase" ADD CONSTRAINT "AdminSupportCase_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AdminSupportCase" ADD CONSTRAINT "AdminSupportCase_creatorId_fkey" FOREIGN KEY ("creatorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "AdminSupportCase" ADD CONSTRAINT "AdminSupportCase_assigneeId_fkey" FOREIGN KEY ("assigneeId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "AdminSupportCaseEvent" ADD CONSTRAINT "AdminSupportCaseEvent_caseId_companyId_fkey" FOREIGN KEY ("caseId", "companyId") REFERENCES "AdminSupportCase"("id", "companyId") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AdminSupportCaseEvent" ADD CONSTRAINT "AdminSupportCaseEvent_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
