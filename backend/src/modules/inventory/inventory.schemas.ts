import { z } from 'zod';

import { paginationQuerySchema } from '../../shared/http/pagination';

const nullableSearch = z
  .union([z.string().trim().max(120), z.null(), z.undefined()])
  .transform((value) => {
    if (value == null) {
      return '';
    }
    return value.trim();
  });

export const inventoryListQuerySchema = paginationQuerySchema.extend({
  query: nullableSearch,
  filter: z.enum(['all', 'active', 'zeroed', 'belowMinimum']).default('all'),
  companyId: z.never().optional(),
});

export const inventorySummaryQuerySchema = z.object({
  companyId: z.never().optional(),
});

export type InventoryListQueryInput = z.infer<typeof inventoryListQuerySchema>;

