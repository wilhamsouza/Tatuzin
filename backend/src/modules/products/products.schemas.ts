import { z } from 'zod';

const nullableTrimmedString = (maxLength: number) =>
  z
    .union([z.string().trim().max(maxLength), z.null(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return null;
      }

      const trimmed = value.trim();
      return trimmed.length === 0 ? null : trimmed;
    });

const deletedAtField = z
  .union([z.string().datetime(), z.null(), z.undefined()])
  .transform((value) => (value == null ? null : new Date(value)));

const productVariantSchema = z.object({
  sku: z.string().trim().min(1).max(80),
  colorLabel: z.string().trim().min(1).max(80),
  sizeLabel: z.string().trim().min(1).max(80),
  priceAdditionalCents: z.coerce.number().int().min(0).default(0),
  stockMil: z.coerce.number().int().min(0).default(0),
  sortOrder: z.coerce.number().int().min(0).default(0),
  isActive: z.boolean().default(true),
});

const productModifierOptionSchema = z.object({
  name: z.string().trim().min(1).max(120),
  adjustmentType: z.enum(['add', 'remove']).default('add'),
  priceDeltaCents: z.coerce.number().int().min(0).default(0),
  linkedProductId: z
    .union([z.string().uuid(), z.null(), z.undefined()])
    .transform((value) => value ?? null),
  sortOrder: z.coerce.number().int().min(0).default(0),
  isActive: z.boolean().default(true),
});

const productModifierGroupSchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    isRequired: z.boolean().default(false),
    minSelections: z.coerce.number().int().min(0).default(0),
    maxSelections: z
      .union([z.coerce.number().int().min(0), z.null(), z.undefined()])
      .transform((value) => value ?? null),
    sortOrder: z.coerce.number().int().min(0).default(0),
    isActive: z.boolean().default(true),
    options: z.array(productModifierOptionSchema).default([]),
  })
  .superRefine((value, ctx) => {
    if (value.maxSelections != null && value.minSelections > value.maxSelections) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['maxSelections'],
        message: 'Min selections cannot exceed max selections.',
      });
    }
  });

export const productUpsertSchema = z
  .object({
    localUuid: z.string().trim().min(1).max(80),
    name: z.string().trim().min(1).max(120),
    categoryId: z.union([z.string().uuid(), z.null(), z.undefined()]).transform(
      (value) => value ?? null,
    ),
    description: nullableTrimmedString(500),
    barcode: nullableTrimmedString(60),
    productType: z.enum(['unidade', 'peso']).default('unidade'),
    niche: z.enum(['alimentacao', 'moda']).default('alimentacao'),
    catalogType: z.enum(['simple', 'variant']).default('simple'),
    modelName: nullableTrimmedString(120),
    variantLabel: nullableTrimmedString(80),
    unitMeasure: z.string().trim().min(1).max(20).default('un'),
    costPriceCents: z.coerce.number().int().min(0).default(0),
    manualCostCents: z.coerce.number().int().min(0).default(0),
    costSource: z.enum(['manual', 'recipe_snapshot']).default('manual'),
    variableCostSnapshotCents: z
      .union([z.coerce.number().int().min(0), z.null(), z.undefined()])
      .transform((value) => value ?? null),
    estimatedGrossMarginCents: z
      .union([z.coerce.number().int(), z.null(), z.undefined()])
      .transform((value) => value ?? null),
    estimatedGrossMarginPercentBasisPoints: z
      .union([z.coerce.number().int(), z.null(), z.undefined()])
      .transform((value) => value ?? null),
    lastCostUpdatedAt: z
      .union([z.string().datetime(), z.null(), z.undefined()])
      .transform((value) => (value == null ? null : new Date(value))),
    salePriceCents: z.coerce.number().int().min(0),
    stockMil: z.coerce.number().int().min(0).default(0),
    variants: z.array(productVariantSchema).default([]),
    modifierGroups: z.array(productModifierGroupSchema).default([]),
    isActive: z.boolean().default(true),
    deletedAt: deletedAtField,
  })
  .superRefine((value, ctx) => {
    const hasVariants = value.variants.length > 0;

    if (value.catalogType !== 'variant' && !hasVariants) {
      return;
    }

    if (!value.modelName) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['modelName'],
        message: 'Model name is required for variant products.',
      });
    }

    if (!value.variantLabel) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['variantLabel'],
        message: 'Variant label is required for variant products.',
      });
    }

    if (hasVariants && !value.variants.some((variant) => variant.isActive)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['variants'],
        message: 'At least one active variant is required.',
      });
    }
  });

export type ProductUpsertInput = z.infer<typeof productUpsertSchema>;
