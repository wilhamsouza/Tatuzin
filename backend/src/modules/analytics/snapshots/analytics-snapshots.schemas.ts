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

export const analyticsSnapshotsQuerySchema = z.object({
  companyId: z.string().uuid(),
  startDate: optionalAnalyticsDateQuery,
  endDate: optionalAnalyticsDateQuery,
  force: optionalBooleanQuery,
});

export const analyticsSnapshotsMaterializeSchema = z.object({
  companyId: z.string().uuid(),
  startDate: analyticsDateSchema.optional(),
  endDate: analyticsDateSchema.optional(),
  force: z.boolean().optional(),
});

export type AnalyticsSnapshotsQueryInput = z.infer<
  typeof analyticsSnapshotsQuerySchema
>;
export type AnalyticsSnapshotsMaterializeInput = z.infer<
  typeof analyticsSnapshotsMaterializeSchema
>;
