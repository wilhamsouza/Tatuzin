import { z } from 'zod';

const hybridPricePolicyModeSchema = z.enum(['advisory', 'governed']);
const hybridCustomerMasterModeSchema = z.enum([
  'cloud_master',
  'hybrid_review',
]);
const hybridPromotionModeSchema = z.enum([
  'manual_preview',
  'scheduled_review',
]);

export const hybridGovernanceQuerySchema = z.object({
  companyId: z.string().uuid(),
});

export const hybridGovernanceProfileUpdateSchema = z.object({
  companyId: z.string().uuid(),
  requireCategoryForGovernedCatalog: z.boolean().optional(),
  requireVariantSku: z.boolean().optional(),
  requireRemoteImageForGovernedCatalog: z.boolean().optional(),
  allowOfflinePriceOverride: z.boolean().optional(),
  allowLocalCatalogDeactivation: z.boolean().optional(),
  minMarginBasisPoints: z.coerce.number().int().min(-10000).max(10000).optional(),
  maxOfflineDiscountBasisPoints: z.coerce
    .number()
    .int()
    .min(0)
    .max(10000)
    .optional(),
  pricePolicyMode: hybridPricePolicyModeSchema.optional(),
  stockDivergenceAlertThresholdMil: z.coerce
    .number()
    .int()
    .min(0)
    .max(100000000)
    .optional(),
  allowOfflineStockAdjustments: z.boolean().optional(),
  requireStockReconciliationReview: z.boolean().optional(),
  customerMasterMode: hybridCustomerMasterModeSchema.optional(),
  allowOperationalCustomerNotes: z.boolean().optional(),
  allowOperationalCustomerAddressOverride: z.boolean().optional(),
  requireCustomerConflictReview: z.boolean().optional(),
  promotionMode: hybridPromotionModeSchema.optional(),
  allowPromotionStacking: z.boolean().optional(),
  requireGovernedPriceForPromotion: z.boolean().optional(),
  alertOnCatalogDrift: z.boolean().optional(),
  alertOnStockDivergence: z.boolean().optional(),
  alertOnCustomerConflict: z.boolean().optional(),
});

export type HybridGovernanceQueryInput = z.infer<
  typeof hybridGovernanceQuerySchema
>;
export type HybridGovernanceProfileUpdateInput = z.infer<
  typeof hybridGovernanceProfileUpdateSchema
>;
