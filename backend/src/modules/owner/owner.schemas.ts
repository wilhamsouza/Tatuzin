import { z } from 'zod';

import { paginationQuerySchema } from '../../shared/http/pagination';

const invoiceStatusSchema = z
  .enum([
    'pending',
    'in_process',
    'paid',
    'failed',
    'rejected',
    'cancelled',
    'canceled',
    'refunded',
    'unknown',
  ])
  .optional();

export const ownerInvoicesQuerySchema = paginationQuerySchema.extend({
  status: invoiceStatusSchema,
});

export type OwnerInvoicesQueryInput = z.infer<
  typeof ownerInvoicesQuerySchema
>;
