ALTER TABLE "Product"
ADD COLUMN "catalogType" TEXT NOT NULL DEFAULT 'simple';

ALTER TABLE "Product"
ADD COLUMN "modelName" TEXT;

ALTER TABLE "Product"
ADD COLUMN "variantLabel" TEXT;

CREATE INDEX "Product_companyId_catalogType_idx"
ON "Product"("companyId", "catalogType");

CREATE INDEX "Product_companyId_modelName_idx"
ON "Product"("companyId", "modelName");

CREATE INDEX "Product_companyId_variantLabel_idx"
ON "Product"("companyId", "variantLabel");
