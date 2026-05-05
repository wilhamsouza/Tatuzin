-- CreateTable
CREATE TABLE "OperationalOrder" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "localUuid" TEXT NOT NULL,
    "cashSessionId" TEXT,
    "customerId" TEXT,
    "sellerUserId" TEXT,
    "deviceId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'open',
    "subtotalCents" INTEGER NOT NULL DEFAULT 0,
    "discountCents" INTEGER NOT NULL DEFAULT 0,
    "totalCents" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "closedAt" TIMESTAMP(3),
    "cancelledAt" TIMESTAMP(3),
    "convertedSaleId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OperationalOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OperationalOrderItem" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "operationalOrderId" TEXT NOT NULL,
    "localUuid" TEXT NOT NULL,
    "productId" TEXT,
    "productVariantId" TEXT,
    "description" TEXT NOT NULL,
    "quantityMil" INTEGER NOT NULL,
    "unitPriceCents" INTEGER NOT NULL DEFAULT 0,
    "totalCents" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OperationalOrderItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "OperationalOrder_convertedSaleId_key" ON "OperationalOrder"("convertedSaleId");

-- CreateIndex
CREATE UNIQUE INDEX "OperationalOrder_companyId_localUuid_key" ON "OperationalOrder"("companyId", "localUuid");

-- CreateIndex
CREATE INDEX "OperationalOrder_companyId_idx" ON "OperationalOrder"("companyId");

-- CreateIndex
CREATE INDEX "OperationalOrder_companyId_status_idx" ON "OperationalOrder"("companyId", "status");

-- CreateIndex
CREATE INDEX "OperationalOrder_companyId_cashSessionId_idx" ON "OperationalOrder"("companyId", "cashSessionId");

-- CreateIndex
CREATE INDEX "OperationalOrder_companyId_convertedSaleId_idx" ON "OperationalOrder"("companyId", "convertedSaleId");

-- CreateIndex
CREATE UNIQUE INDEX "OperationalOrderItem_companyId_localUuid_key" ON "OperationalOrderItem"("companyId", "localUuid");

-- CreateIndex
CREATE INDEX "OperationalOrderItem_companyId_idx" ON "OperationalOrderItem"("companyId");

-- CreateIndex
CREATE INDEX "OperationalOrderItem_companyId_operationalOrderId_idx" ON "OperationalOrderItem"("companyId", "operationalOrderId");

-- CreateIndex
CREATE INDEX "OperationalOrderItem_companyId_productVariantId_idx" ON "OperationalOrderItem"("companyId", "productVariantId");

-- AddForeignKey
ALTER TABLE "OperationalOrder" ADD CONSTRAINT "OperationalOrder_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrder" ADD CONSTRAINT "OperationalOrder_cashSessionId_fkey" FOREIGN KEY ("cashSessionId") REFERENCES "CashSession"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrder" ADD CONSTRAINT "OperationalOrder_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrder" ADD CONSTRAINT "OperationalOrder_sellerUserId_fkey" FOREIGN KEY ("sellerUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrder" ADD CONSTRAINT "OperationalOrder_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrder" ADD CONSTRAINT "OperationalOrder_convertedSaleId_fkey" FOREIGN KEY ("convertedSaleId") REFERENCES "Sale"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrderItem" ADD CONSTRAINT "OperationalOrderItem_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrderItem" ADD CONSTRAINT "OperationalOrderItem_operationalOrderId_fkey" FOREIGN KEY ("operationalOrderId") REFERENCES "OperationalOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrderItem" ADD CONSTRAINT "OperationalOrderItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OperationalOrderItem" ADD CONSTRAINT "OperationalOrderItem_productVariantId_fkey" FOREIGN KEY ("productVariantId") REFERENCES "ProductVariant"("id") ON DELETE SET NULL ON UPDATE CASCADE;
