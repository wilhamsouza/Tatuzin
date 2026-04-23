import { z } from 'zod';

import { createListQuerySchema } from '../../shared/http/pagination';

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

export const categoryUpsertSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  name: z.string().trim().min(1).max(120),
  description: nullableTrimmedString(500),
  isActive: z.boolean().default(true),
  deletedAt: deletedAtField,
});

export const categoryListQuerySchema = createListQuerySchema({
  includeDeleted: true,
});

export type CategoryUpsertInput = z.infer<typeof categoryUpsertSchema>;
export type CategoryListQueryInput = z.infer<typeof categoryListQuerySchema>;
