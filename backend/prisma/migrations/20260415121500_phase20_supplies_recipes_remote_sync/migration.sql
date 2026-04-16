ALTER TABLE "Product"
ADD COLUMN "manualCostCents" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "costSource" TEXT NOT NULL DEFAULT 'manual',
ADD COLUMN "variableCostSnapshotCents" INTEGER,
ADD COLUMN "estimatedGrossMarginCents" INTEGER,
ADD COLUMN "estimatedGrossMarginPercentBasisPoints" INTEGER,
ADD COLUMN "lastCostUpdatedAt" TIMESTAMP(3);

UPDATE "Product"
SET "manualCostCents" = "costPriceCents"
WHERE "manualCostCents" = 0;

CREATE TABLE "Supply" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "localUuid" TEXT NOT NULL,
    "defaultSupplierId" TEXT,
    "name" TEXT NOT NULL,
    "sku" TEXT,
    "unitType" TEXT NOT NULL,
    "purchaseUnitType" TEXT NOT NULL,
    "conversionFactor" INTEGER NOT NULL,
    "lastPurchasePriceCents" INTEGER NOT NULL DEFAULT 0,
    "averagePurchasePriceCents" INTEGER,
    "currentStockMil" INTEGER,
    "minimumStockMil" INTEGER,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Supply_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ProductRecipeItem" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "localUuid" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "supplyId" TEXT NOT NULL,
    "quantityUsedMil" INTEGER NOT NULL,
    "unitType" TEXT NOT NULL,
    "wasteBasisPoints" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProductRecipeItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SupplyCostHistory" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "localUuid" TEXT NOT NULL,
    "supplyId" TEXT NOT NULL,
    "purchaseId" TEXT,
    "purchaseItemId" TEXT,
    "source" TEXT NOT NULL,
    "eventType" TEXT NOT NULL,
    "purchaseUnitType" TEXT NOT NULL,
    "conversionFactor" INTEGER NOT NULL,
    "lastPurchasePriceCents" INTEGER NOT NULL,
    "averagePurchasePriceCents" INTEGER,
    "changeSummary" TEXT,
    "notes" TEXT,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SupplyCostHistory_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "PurchaseItem"
ADD COLUMN "itemType" TEXT NOT NULL DEFAULT 'product',
ADD COLUMN "supplyId" TEXT;

CREATE UNIQUE INDEX "Supply_companyId_localUuid_key"
ON "Supply"("companyId", "localUuid");

CREATE INDEX "Supply_companyId_updatedAt_idx"
ON "Supply"("companyId", "updatedAt");

CREATE INDEX "Supply_companyId_name_idx"
ON "Supply"("companyId", "name");

CREATE INDEX "Supply_companyId_defaultSupplierId_idx"
ON "Supply"("companyId", "defaultSupplierId");

CREATE UNIQUE INDEX "ProductRecipeItem_companyId_localUuid_key"
ON "ProductRecipeItem"("companyId", "localUuid");

CREATE INDEX "ProductRecipeItem_companyId_productId_idx"
ON "ProductRecipeItem"("companyId", "productId");

CREATE INDEX "ProductRecipeItem_companyId_supplyId_idx"
ON "ProductRecipeItem"("companyId", "supplyId");

CREATE INDEX "ProductRecipeItem_productId_idx"
ON "ProductRecipeItem"("productId");

CREATE INDEX "ProductRecipeItem_supplyId_idx"
ON "ProductRecipeItem"("supplyId");

CREATE UNIQUE INDEX "SupplyCostHistory_companyId_localUuid_key"
ON "SupplyCostHistory"("companyId", "localUuid");

CREATE INDEX "SupplyCostHistory_companyId_supplyId_occurredAt_idx"
ON "SupplyCostHistory"("companyId", "supplyId", "occurredAt");

CREATE INDEX "SupplyCostHistory_companyId_eventType_occurredAt_idx"
ON "SupplyCostHistory"("companyId", "eventType", "occurredAt");

CREATE INDEX "SupplyCostHistory_purchaseId_idx"
ON "SupplyCostHistory"("purchaseId");

CREATE INDEX "SupplyCostHistory_purchaseItemId_idx"
ON "SupplyCostHistory"("purchaseItemId");

CREATE INDEX "PurchaseItem_supplyId_idx"
ON "PurchaseItem"("supplyId");

ALTER TABLE "Supply"
ADD CONSTRAINT "Supply_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Supply"
ADD CONSTRAINT "Supply_defaultSupplierId_fkey"
FOREIGN KEY ("defaultSupplierId") REFERENCES "Supplier"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "ProductRecipeItem"
ADD CONSTRAINT "ProductRecipeItem_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ProductRecipeItem"
ADD CONSTRAINT "ProductRecipeItem_productId_fkey"
FOREIGN KEY ("productId") REFERENCES "Product"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ProductRecipeItem"
ADD CONSTRAINT "ProductRecipeItem_supplyId_fkey"
FOREIGN KEY ("supplyId") REFERENCES "Supply"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "PurchaseItem"
ADD CONSTRAINT "PurchaseItem_supplyId_fkey"
FOREIGN KEY ("supplyId") REFERENCES "Supply"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "SupplyCostHistory"
ADD CONSTRAINT "SupplyCostHistory_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SupplyCostHistory"
ADD CONSTRAINT "SupplyCostHistory_supplyId_fkey"
FOREIGN KEY ("supplyId") REFERENCES "Supply"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SupplyCostHistory"
ADD CONSTRAINT "SupplyCostHistory_purchaseId_fkey"
FOREIGN KEY ("purchaseId") REFERENCES "Purchase"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "SupplyCostHistory"
ADD CONSTRAINT "SupplyCostHistory_purchaseItemId_fkey"
FOREIGN KEY ("purchaseItemId") REFERENCES "PurchaseItem"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
