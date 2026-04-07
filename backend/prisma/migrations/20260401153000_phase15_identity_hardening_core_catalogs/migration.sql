-- AlterTable
ALTER TABLE "Category" ADD COLUMN "localUuid" TEXT;

-- AlterTable
ALTER TABLE "Product" ADD COLUMN "localUuid" TEXT;

-- AlterTable
ALTER TABLE "Customer" ADD COLUMN "localUuid" TEXT;

-- Backfill legacy rows with a deterministic identity to preserve compatibility.
UPDATE "Category"
SET "localUuid" = "id"
WHERE "localUuid" IS NULL;

UPDATE "Product"
SET "localUuid" = "id"
WHERE "localUuid" IS NULL;

UPDATE "Customer"
SET "localUuid" = "id"
WHERE "localUuid" IS NULL;

-- Enforce strong remote identity from this phase forward.
ALTER TABLE "Category" ALTER COLUMN "localUuid" SET NOT NULL;
ALTER TABLE "Product" ALTER COLUMN "localUuid" SET NOT NULL;
ALTER TABLE "Customer" ALTER COLUMN "localUuid" SET NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "Category_companyId_localUuid_key" ON "Category"("companyId", "localUuid");

-- CreateIndex
CREATE UNIQUE INDEX "Product_companyId_localUuid_key" ON "Product"("companyId", "localUuid");

-- CreateIndex
CREATE UNIQUE INDEX "Customer_companyId_localUuid_key" ON "Customer"("companyId", "localUuid");
