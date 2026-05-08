import { z } from 'zod';

import { paginationQuerySchema } from '../../shared/http/pagination';

export const billingSubscribeSchema = z.object({
  plan: z.enum(['BASIC', 'PRO', 'basic', 'pro']).transform((value) =>
    value.toUpperCase() as 'BASIC' | 'PRO',
  ),
  billingCycle: z
    .enum(['monthly'])
    .optional()
    .default('monthly'),
});

export type BillingSubscribeInput = z.infer<typeof billingSubscribeSchema>;

const optionalIsoDateSchema = z
  .string()
  .trim()
  .datetime({ offset: true })
  .optional()
  .transform((value) => (value == null ? undefined : new Date(value)));

export const billingInvoicesQuerySchema = paginationQuerySchema.extend({
  status: z
    .string()
    .trim()
    .min(1)
    .max(40)
    .optional(),
  from: optionalIsoDateSchema,
  to: optionalIsoDateSchema,
});

export const billingCancelSchema = z.object({
  reason: z
    .string()
    .trim()
    .max(1000)
    .optional(),
  effective: z.enum(['period_end', 'now']).optional().default('period_end'),
});

export const billingChangePlanSchema = z.object({
  plan: z.enum(['FREE', 'BASIC', 'PRO', 'free', 'basic', 'pro']).transform(
    (value) => value.toUpperCase() as 'FREE' | 'BASIC' | 'PRO',
  ),
});

export type BillingInvoicesQueryInput = z.infer<
  typeof billingInvoicesQuerySchema
>;
export type BillingCancelInput = z.infer<typeof billingCancelSchema>;
export type BillingChangePlanInput = z.infer<typeof billingChangePlanSchema>;
