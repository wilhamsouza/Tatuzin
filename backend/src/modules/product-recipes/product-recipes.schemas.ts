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

const recipeItemSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  supplyId: z.string().uuid(),
  quantityUsedMil: z.coerce.number().int().positive(),
  unitType: z.string().trim().min(1).max(20),
  wasteBasisPoints: z.coerce.number().int().min(0).default(0),
  notes: nullableTrimmedString(800),
});

export const productRecipeUpsertSchema = z.object({
  productLocalUuid: z.string().trim().min(1).max(80),
  items: z.array(recipeItemSchema).default([]),
});

export type ProductRecipeUpsertInput = z.infer<typeof productRecipeUpsertSchema>;
export type ProductRecipeItemInput = z.infer<typeof recipeItemSchema>;
