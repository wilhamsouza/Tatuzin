import { z } from 'zod';

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
