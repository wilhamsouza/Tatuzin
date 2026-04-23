-- CreateTable
CREATE TABLE "AnalyticsCompanyDailySnapshot" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "snapshotDate" TIMESTAMP(3) NOT NULL,
    "salesCount" INTEGER NOT NULL DEFAULT 0,
    "customersServedCount" INTEGER NOT NULL DEFAULT 0,
    "salesAmountCents" INTEGER NOT NULL DEFAULT 0,
    "salesCostCents" INTEGER NOT NULL DEFAULT 0,
    "salesProfitCents" INTEGER NOT NULL DEFAULT 0,
    "fiadoSalesCount" INTEGER NOT NULL DEFAULT 0,
    "fiadoPaymentsCount" INTEGER NOT NULL DEFAULT 0,
    "fiadoPaymentsAmountCents" INTEGER NOT NULL DEFAULT 0,
    "purchasesCount" INTEGER NOT NULL DEFAULT 0,
    "purchasesAmountCents" INTEGER NOT NULL DEFAULT 0,
    "cashInflowCents" INTEGER NOT NULL DEFAULT 0,
    "cashOutflowCents" INTEGER NOT NULL DEFAULT 0,
    "cashNetCents" INTEGER NOT NULL DEFAULT 0,
    "financialAdjustmentsCents" INTEGER NOT NULL DEFAULT 0,
    "materializedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AnalyticsCompanyDailySnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AnalyticsProductDailySnapshot" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "snapshotDate" TIMESTAMP(3) NOT NULL,
    "productKey" TEXT NOT NULL,
    "productId" TEXT,
    "productNameSnapshot" TEXT NOT NULL,
    "quantityMil" INTEGER NOT NULL DEFAULT 0,
    "salesCount" INTEGER NOT NULL DEFAULT 0,
    "revenueCents" INTEGER NOT NULL DEFAULT 0,
    "costCents" INTEGER NOT NULL DEFAULT 0,
    "profitCents" INTEGER NOT NULL DEFAULT 0,
    "materializedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AnalyticsProductDailySnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AnalyticsCustomerDailySnapshot" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "snapshotDate" TIMESTAMP(3) NOT NULL,
    "customerKey" TEXT NOT NULL,
    "customerId" TEXT,
    "customerNameSnapshot" TEXT NOT NULL,
    "salesCount" INTEGER NOT NULL DEFAULT 0,
    "revenueCents" INTEGER NOT NULL DEFAULT 0,
    "costCents" INTEGER NOT NULL DEFAULT 0,
    "profitCents" INTEGER NOT NULL DEFAULT 0,
    "fiadoPaymentsCents" INTEGER NOT NULL DEFAULT 0,
    "materializedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AnalyticsCustomerDailySnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "AnalyticsCompanyDailySnapshot_companyId_snapshotDate_key" ON "AnalyticsCompanyDailySnapshot"("companyId", "snapshotDate");

-- CreateIndex
CREATE INDEX "AnalyticsCompanyDailySnapshot_companyId_snapshotDate_idx" ON "AnalyticsCompanyDailySnapshot"("companyId", "snapshotDate");

-- CreateIndex
CREATE UNIQUE INDEX "AnalyticsProductDailySnapshot_companyId_snapshotDate_productKey_key" ON "AnalyticsProductDailySnapshot"("companyId", "snapshotDate", "productKey");

-- CreateIndex
CREATE INDEX "AnalyticsProductDailySnapshot_companyId_snapshotDate_idx" ON "AnalyticsProductDailySnapshot"("companyId", "snapshotDate");

-- CreateIndex
CREATE INDEX "AnalyticsProductDailySnapshot_companyId_productId_idx" ON "AnalyticsProductDailySnapshot"("companyId", "productId");

-- CreateIndex
CREATE UNIQUE INDEX "AnalyticsCustomerDailySnapshot_companyId_snapshotDate_customerKey_key" ON "AnalyticsCustomerDailySnapshot"("companyId", "snapshotDate", "customerKey");

-- CreateIndex
CREATE INDEX "AnalyticsCustomerDailySnapshot_companyId_snapshotDate_idx" ON "AnalyticsCustomerDailySnapshot"("companyId", "snapshotDate");

-- CreateIndex
CREATE INDEX "AnalyticsCustomerDailySnapshot_companyId_customerId_idx" ON "AnalyticsCustomerDailySnapshot"("companyId", "customerId");

-- AddForeignKey
ALTER TABLE "AnalyticsCompanyDailySnapshot" ADD CONSTRAINT "AnalyticsCompanyDailySnapshot_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AnalyticsProductDailySnapshot" ADD CONSTRAINT "AnalyticsProductDailySnapshot_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AnalyticsCustomerDailySnapshot" ADD CONSTRAINT "AnalyticsCustomerDailySnapshot_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
