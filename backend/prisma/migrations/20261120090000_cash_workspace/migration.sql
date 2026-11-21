-- Additive only. Rollback: disable policy and roll back clients; retain audit history.
ALTER TABLE "Company" ADD COLUMN "cashBlindClosureEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "cashPolicyRevision" INTEGER NOT NULL DEFAULT 0;
CREATE TABLE "CashDivergenceReviewEvent" (
"id" TEXT NOT NULL PRIMARY KEY, "companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
"sessionId" TEXT NOT NULL REFERENCES "CashSession"("id") ON DELETE CASCADE,
"requestId" TEXT NOT NULL, "revision" INTEGER NOT NULL, "status" TEXT NOT NULL,
"justification" TEXT NOT NULL, "authorId" TEXT NOT NULL REFERENCES "User"("id") ON DELETE RESTRICT,
"authorName" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT "CashDivergenceReviewEvent_status_check" CHECK ("status" IN ('PENDING','REVIEWED')),
CONSTRAINT "CashDivergenceReviewEvent_revision_check" CHECK ("revision" > 0));
CREATE UNIQUE INDEX "CashDivergenceReviewEvent_companyId_sessionId_revision_key" ON "CashDivergenceReviewEvent"("companyId","sessionId","revision");
CREATE UNIQUE INDEX "CashDivergenceReviewEvent_companyId_requestId_key" ON "CashDivergenceReviewEvent"("companyId","requestId");
CREATE INDEX "CashDivergenceReviewEvent_companyId_sessionId_createdAt_idx" ON "CashDivergenceReviewEvent"("companyId","sessionId","createdAt");
