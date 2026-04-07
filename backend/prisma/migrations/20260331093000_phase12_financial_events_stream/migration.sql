-- CreateTable
CREATE TABLE "FinancialEvent" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "saleId" TEXT,
    "fiadoId" TEXT,
    "eventType" TEXT NOT NULL,
    "localUuid" TEXT NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "paymentType" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FinancialEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "FinancialEvent_companyId_localUuid_key" ON "FinancialEvent"("companyId", "localUuid");

-- CreateIndex
CREATE INDEX "FinancialEvent_companyId_createdAt_idx" ON "FinancialEvent"("companyId", "createdAt");

-- CreateIndex
CREATE INDEX "FinancialEvent_companyId_eventType_idx" ON "FinancialEvent"("companyId", "eventType");

-- CreateIndex
CREATE INDEX "FinancialEvent_companyId_saleId_idx" ON "FinancialEvent"("companyId", "saleId");

-- AddForeignKey
ALTER TABLE "FinancialEvent" ADD CONSTRAINT "FinancialEvent_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FinancialEvent" ADD CONSTRAINT "FinancialEvent_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE SET NULL ON UPDATE CASCADE;
