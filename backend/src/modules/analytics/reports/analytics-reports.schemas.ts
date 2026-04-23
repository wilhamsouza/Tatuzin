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

export const analyticsReportQuerySchema = z.object({
  companyId: z.string().uuid(),
  startDate: optionalAnalyticsDateQuery,
  endDate: optionalAnalyticsDateQuery,
  topN: z.coerce.number().int().min(1).max(50).default(10),
  force: optionalBooleanQuery,
});

export type AnalyticsReportQueryInput = z.infer<
  typeof analyticsReportQuerySchema
>;
