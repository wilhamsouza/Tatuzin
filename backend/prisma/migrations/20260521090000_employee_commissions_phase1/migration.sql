-- Fase 1: employee commission settings for sales/lucro reporting.
ALTER TABLE "EmployeeProfile"
  ADD COLUMN "commissionEnabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "commissionType" TEXT,
  ADD COLUMN "commissionBase" TEXT,
  ADD COLUMN "commissionRateBps" INTEGER,
  ADD COLUMN "commissionFixedCents" INTEGER,
  ADD COLUMN "commissionUpdatedAt" TIMESTAMP(3);

CREATE INDEX "EmployeeProfile_companyId_commissionEnabled_idx"
  ON "EmployeeProfile"("companyId", "commissionEnabled");
