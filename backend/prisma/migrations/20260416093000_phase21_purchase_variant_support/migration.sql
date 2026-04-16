ALTER TABLE "PurchaseItem"
ADD COLUMN "productVariantId" TEXT,
ADD COLUMN "variantSkuSnapshot" TEXT,
ADD COLUMN "variantColorLabelSnapshot" TEXT,
ADD COLUMN "variantSizeLabelSnapshot" TEXT;

CREATE INDEX "PurchaseItem_productVariantId_idx"
ON "PurchaseItem"("productVariantId");

ALTER TABLE "PurchaseItem"
ADD CONSTRAINT "PurchaseItem_productVariantId_fkey"
FOREIGN KEY ("productVariantId") REFERENCES "ProductVariant"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
