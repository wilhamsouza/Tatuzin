import { z } from 'zod';

const analyticsDateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const optionalAnalyticsDateQuery = z
  .union([analyticsDateSchema, z.undefined()])
  .transform((value) => value ?? undefined);

const optionalBooleanQuery = z
  .union([z.boolean(), z.enum(['true', 'false']), z.undefined()])
  .transform((value) => {
    if (value === undefined) {
      return undefined;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    return value === 'true';
  });

const optionalUuidQuery = z
  .union([z.string().uuid(), z.undefined()])
  .transform((value) => value ?? undefined);

export const tenantAnalyticsReportQuerySchema = z.object({
  companyId: z.never().optional(),
  startDate: optionalAnalyticsDateQuery,
  endDate: optionalAnalyticsDateQuery,
  topN: z.coerce.number().int().min(1).max(50).default(10),
  force: optionalBooleanQuery,
  grouping: z.enum(['day', 'week', 'month']).default('day'),
  productId: optionalUuidQuery,
  customerId: optionalUuidQuery,
  categoryId: optionalUuidQuery,
  supplierId: optionalUuidQuery,
});

export type TenantAnalyticsReportQueryInput = z.infer<
  typeof tenantAnalyticsReportQuerySchema
>;
