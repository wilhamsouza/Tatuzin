-- CreateEnum
CREATE TYPE "HybridPricePolicyMode" AS ENUM ('ADVISORY', 'GOVERNED');

-- CreateEnum
CREATE TYPE "HybridCustomerMasterMode" AS ENUM ('CLOUD_MASTER', 'HYBRID_REVIEW');

-- CreateEnum
CREATE TYPE "HybridPromotionMode" AS ENUM ('MANUAL_PREVIEW', 'SCHEDULED_REVIEW');

-- CreateTable
CREATE TABLE "HybridGovernanceProfile" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "requireCategoryForGovernedCatalog" BOOLEAN NOT NULL DEFAULT true,
    "requireVariantSku" BOOLEAN NOT NULL DEFAULT true,
    "requireRemoteImageForGovernedCatalog" BOOLEAN NOT NULL DEFAULT false,
    "allowOfflinePriceOverride" BOOLEAN NOT NULL DEFAULT true,
    "allowLocalCatalogDeactivation" BOOLEAN NOT NULL DEFAULT true,
    "minMarginBasisPoints" INTEGER NOT NULL DEFAULT 0,
    "maxOfflineDiscountBasisPoints" INTEGER NOT NULL DEFAULT 1500,
    "pricePolicyMode" "HybridPricePolicyMode" NOT NULL DEFAULT 'ADVISORY',
    "stockDivergenceAlertThresholdMil" INTEGER NOT NULL DEFAULT 5000,
    "allowOfflineStockAdjustments" BOOLEAN NOT NULL DEFAULT true,
    "requireStockReconciliationReview" BOOLEAN NOT NULL DEFAULT false,
    "customerMasterMode" "HybridCustomerMasterMode" NOT NULL DEFAULT 'CLOUD_MASTER',
    "allowOperationalCustomerNotes" BOOLEAN NOT NULL DEFAULT true,
    "allowOperationalCustomerAddressOverride" BOOLEAN NOT NULL DEFAULT true,
    "requireCustomerConflictReview" BOOLEAN NOT NULL DEFAULT false,
    "promotionMode" "HybridPromotionMode" NOT NULL DEFAULT 'MANUAL_PREVIEW',
    "allowPromotionStacking" BOOLEAN NOT NULL DEFAULT false,
    "requireGovernedPriceForPromotion" BOOLEAN NOT NULL DEFAULT true,
    "alertOnCatalogDrift" BOOLEAN NOT NULL DEFAULT true,
    "alertOnStockDivergence" BOOLEAN NOT NULL DEFAULT true,
    "alertOnCustomerConflict" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "HybridGovernanceProfile_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "HybridGovernanceProfile_companyId_key" ON "HybridGovernanceProfile"("companyId");

-- AddForeignKey
ALTER TABLE "HybridGovernanceProfile" ADD CONSTRAINT "HybridGovernanceProfile_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
