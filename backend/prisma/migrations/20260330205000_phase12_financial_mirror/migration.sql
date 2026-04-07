ALTER TABLE "Sale"
ADD COLUMN "canceledAt" TIMESTAMP(3);

CREATE TABLE "FiadoPayment" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "saleId" TEXT NOT NULL,
  "localUuid" TEXT NOT NULL,
  "amountCents" INTEGER NOT NULL,
  "paymentMethod" TEXT NOT NULL,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "FiadoPayment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "CashEvent" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "localUuid" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "amountCents" INTEGER NOT NULL,
  "paymentMethod" TEXT,
  "referenceType" TEXT,
  "referenceId" TEXT,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CashEvent_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FiadoPayment_companyId_localUuid_key"
ON "FiadoPayment"("companyId", "localUuid");

CREATE INDEX "FiadoPayment_companyId_createdAt_idx"
ON "FiadoPayment"("companyId", "createdAt");

CREATE INDEX "FiadoPayment_companyId_saleId_idx"
ON "FiadoPayment"("companyId", "saleId");

CREATE UNIQUE INDEX "CashEvent_companyId_localUuid_key"
ON "CashEvent"("companyId", "localUuid");

CREATE INDEX "CashEvent_companyId_createdAt_idx"
ON "CashEvent"("companyId", "createdAt");

CREATE INDEX "CashEvent_companyId_eventType_idx"
ON "CashEvent"("companyId", "eventType");

ALTER TABLE "FiadoPayment"
ADD CONSTRAINT "FiadoPayment_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "FiadoPayment"
ADD CONSTRAINT "FiadoPayment_saleId_fkey"
FOREIGN KEY ("saleId") REFERENCES "Sale"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "CashEvent"
ADD CONSTRAINT "CashEvent_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
