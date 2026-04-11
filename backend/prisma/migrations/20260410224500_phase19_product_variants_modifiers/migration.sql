ALTER TABLE "Product"
ADD COLUMN "niche" TEXT NOT NULL DEFAULT 'alimentacao';

CREATE TABLE "ProductVariant" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "colorLabel" TEXT NOT NULL,
    "sizeLabel" TEXT NOT NULL,
    "priceAdditionalCents" INTEGER NOT NULL DEFAULT 0,
    "stockMil" INTEGER NOT NULL DEFAULT 0,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProductVariant_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ProductModifierGroup" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "isRequired" BOOLEAN NOT NULL DEFAULT false,
    "minSelections" INTEGER NOT NULL DEFAULT 0,
    "maxSelections" INTEGER,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProductModifierGroup_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ProductModifierOption" (
    "id" TEXT NOT NULL,
    "modifierGroupId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "adjustmentType" TEXT NOT NULL DEFAULT 'add',
    "priceDeltaCents" INTEGER NOT NULL DEFAULT 0,
    "linkedProductId" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProductModifierOption_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ProductVariant_productId_sortOrder_idx"
ON "ProductVariant"("productId", "sortOrder");

CREATE INDEX "ProductVariant_sku_idx"
ON "ProductVariant"("sku");

CREATE INDEX "ProductModifierGroup_productId_sortOrder_idx"
ON "ProductModifierGroup"("productId", "sortOrder");

CREATE INDEX "ProductModifierOption_modifierGroupId_sortOrder_idx"
ON "ProductModifierOption"("modifierGroupId", "sortOrder");

CREATE INDEX "ProductModifierOption_linkedProductId_idx"
ON "ProductModifierOption"("linkedProductId");

ALTER TABLE "ProductVariant"
ADD CONSTRAINT "ProductVariant_productId_fkey"
FOREIGN KEY ("productId") REFERENCES "Product"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ProductModifierGroup"
ADD CONSTRAINT "ProductModifierGroup_productId_fkey"
FOREIGN KEY ("productId") REFERENCES "Product"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ProductModifierOption"
ADD CONSTRAINT "ProductModifierOption_modifierGroupId_fkey"
FOREIGN KEY ("modifierGroupId") REFERENCES "ProductModifierGroup"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ProductModifierOption"
ADD CONSTRAINT "ProductModifierOption_linkedProductId_fkey"
FOREIGN KEY ("linkedProductId") REFERENCES "Product"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
