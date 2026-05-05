-- AlterTable
ALTER TABLE "SyncEvent" ADD COLUMN "materializedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Sale" ADD COLUMN "cashSessionId" TEXT;

-- AlterTable
ALTER TABLE "SaleItem" ADD COLUMN "localUuid" TEXT;

-- AlterTable
ALTER TABLE "CashEvent" ADD COLUMN "cashSessionId" TEXT;

-- CreateTable
CREATE TABLE "CashSession" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT,
    "userId" TEXT,
    "localId" TEXT,
    "localUuid" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "openedAt" TIMESTAMP(3),
    "closedAt" TIMESTAMP(3),
    "openingBalanceCents" INTEGER NOT NULL DEFAULT 0,
    "closingBalanceCents" INTEGER,
    "expectedBalanceCents" INTEGER,
    "notes" TEXT,
    "payload" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CashSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StockReservation" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "saleId" TEXT,
    "productId" TEXT,
    "productVariantId" TEXT,
    "localUuid" TEXT NOT NULL,
    "quantityMil" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "payload" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StockReservation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StockDeduction" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "saleId" TEXT,
    "productId" TEXT,
    "productVariantId" TEXT,
    "localUuid" TEXT NOT NULL,
    "quantityMil" INTEGER NOT NULL,
    "payload" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StockDeduction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CashSession_companyId_localUuid_key" ON "CashSession"("companyId", "localUuid");

-- CreateIndex
CREATE INDEX "CashSession_companyId_localId_idx" ON "CashSession"("companyId", "localId");

-- CreateIndex
CREATE INDEX "CashSession_companyId_status_idx" ON "CashSession"("companyId", "status");

-- CreateIndex
CREATE INDEX "CashSession_companyId_deviceId_idx" ON "CashSession"("companyId", "deviceId");

-- CreateIndex
CREATE INDEX "CashSession_companyId_openedAt_idx" ON "CashSession"("companyId", "openedAt");

-- CreateIndex
CREATE INDEX "Sale_companyId_cashSessionId_idx" ON "Sale"("companyId", "cashSessionId");

-- CreateIndex
CREATE UNIQUE INDEX "SaleItem_saleId_localUuid_key" ON "SaleItem"("saleId", "localUuid");

-- CreateIndex
CREATE INDEX "CashEvent_companyId_cashSessionId_idx" ON "CashEvent"("companyId", "cashSessionId");

-- CreateIndex
CREATE UNIQUE INDEX "StockReservation_companyId_localUuid_key" ON "StockReservation"("companyId", "localUuid");

-- CreateIndex
CREATE INDEX "StockReservation_companyId_status_idx" ON "StockReservation"("companyId", "status");

-- CreateIndex
CREATE INDEX "StockReservation_companyId_saleId_idx" ON "StockReservation"("companyId", "saleId");

-- CreateIndex
CREATE INDEX "StockReservation_companyId_productVariantId_idx" ON "StockReservation"("companyId", "productVariantId");

-- CreateIndex
CREATE INDEX "StockReservation_companyId_productId_idx" ON "StockReservation"("companyId", "productId");

-- CreateIndex
CREATE UNIQUE INDEX "StockDeduction_companyId_localUuid_key" ON "StockDeduction"("companyId", "localUuid");

-- CreateIndex
CREATE INDEX "StockDeduction_companyId_saleId_idx" ON "StockDeduction"("companyId", "saleId");

-- CreateIndex
CREATE INDEX "StockDeduction_companyId_productVariantId_idx" ON "StockDeduction"("companyId", "productVariantId");

-- CreateIndex
CREATE INDEX "StockDeduction_companyId_productId_idx" ON "StockDeduction"("companyId", "productId");

-- AddForeignKey
ALTER TABLE "CashSession" ADD CONSTRAINT "CashSession_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CashSession" ADD CONSTRAINT "CashSession_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CashSession" ADD CONSTRAINT "CashSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_cashSessionId_fkey" FOREIGN KEY ("cashSessionId") REFERENCES "CashSession"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CashEvent" ADD CONSTRAINT "CashEvent_cashSessionId_fkey" FOREIGN KEY ("cashSessionId") REFERENCES "CashSession"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockReservation" ADD CONSTRAINT "StockReservation_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockReservation" ADD CONSTRAINT "StockReservation_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockReservation" ADD CONSTRAINT "StockReservation_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockReservation" ADD CONSTRAINT "StockReservation_productVariantId_fkey" FOREIGN KEY ("productVariantId") REFERENCES "ProductVariant"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockDeduction" ADD CONSTRAINT "StockDeduction_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockDeduction" ADD CONSTRAINT "StockDeduction_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockDeduction" ADD CONSTRAINT "StockDeduction_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockDeduction" ADD CONSTRAINT "StockDeduction_productVariantId_fkey" FOREIGN KEY ("productVariantId") REFERENCES "ProductVariant"("id") ON DELETE SET NULL ON UPDATE CASCADE;
