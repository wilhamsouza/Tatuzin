CREATE TABLE "Cost" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "localUuid" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "category" TEXT,
  "amountCents" INTEGER NOT NULL,
  "referenceDate" TIMESTAMP(3) NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "isRecurring" BOOLEAN NOT NULL DEFAULT false,
  "paidAt" TIMESTAMP(3),
  "paymentMethod" TEXT,
  "notes" TEXT,
  "canceledAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "Cost_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Cost_companyId_localUuid_key"
  ON "Cost"("companyId", "localUuid");

CREATE INDEX "Cost_companyId_referenceDate_idx"
  ON "Cost"("companyId", "referenceDate");

CREATE INDEX "Cost_companyId_status_idx"
  ON "Cost"("companyId", "status");

CREATE INDEX "Cost_companyId_type_idx"
  ON "Cost"("companyId", "type");

ALTER TABLE "Cost"
  ADD CONSTRAINT "Cost_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Company"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
