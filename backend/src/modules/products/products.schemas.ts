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
    catalogType: z.enum(['simple', 'variant']).default('simple'),
    modelName: nullableTrimmedString(120),
    variantLabel: nullableTrimmedString(80),
    unitMeasure: z.string().trim().min(1).max(20).default('un'),
    costPriceCents: z.coerce.number().int().min(0).default(0),
    salePriceCents: z.coerce.number().int().min(0),
    stockMil: z.coerce.number().int().min(0).default(0),
    isActive: z.boolean().default(true),
    deletedAt: deletedAtField,
  })
  .superRefine((value, ctx) => {
    if (value.catalogType !== 'variant') {
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
  });

export type ProductUpsertInput = z.infer<typeof productUpsertSchema>;
