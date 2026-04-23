import { z } from 'zod';

const analyticsDateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const optionalAnalyticsDateQuery = z
  .union([analyticsDateSchema, z.undefined()])
  .transform((value) => value ?? undefined);

export const analyticsDashboardQuerySchema = z.object({
  companyId: z.string().uuid(),
  startDate: optionalAnalyticsDateQuery,
  endDate: optionalAnalyticsDateQuery,
  topN: z.coerce.number().int().min(3).max(20).default(8),
  force: z
    .union([z.boolean(), z.enum(['true', 'false']), z.undefined()])
    .transform((value) => {
      if (value === undefined) {
        return undefined;
      }
      if (typeof value === 'boolean') {
        return value;
      }
      return value === 'true';
    }),
});

export type AnalyticsDashboardQueryInput = z.infer<
  typeof analyticsDashboardQuerySchema
>;
