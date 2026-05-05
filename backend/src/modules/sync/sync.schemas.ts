import { z } from 'zod';

const numericQuery = (defaultValue: number, maxValue?: number) =>
  z
    .preprocess((value) => {
      if (value == null || value === '') {
        return defaultValue;
      }
      if (Array.isArray(value)) {
        return value[0];
      }
      return value;
    }, z.coerce.number().int().min(0).default(defaultValue))
    .transform((value) => (maxValue == null ? value : Math.min(value, maxValue)));

const optionalTrimmedString = (maxLength: number) =>
  z.string().trim().min(1).max(maxLength).optional();

export const syncPushBatchSchema = z.object({
  lastKnownServerVersion: z.union([z.string(), z.number()]).optional(),
  events: z.array(z.unknown()),
});

export const syncPushEventSchema = z.object({
  eventId: z.string().trim().min(1).max(160),
  feature: z.string().trim().min(1).max(80),
  entity: z.string().trim().min(1).max(80),
  operation: z.string().trim().min(1).max(40),
  entityLocalId: optionalTrimmedString(160),
  entityServerId: optionalTrimmedString(160),
  occurredAt: z.string().datetime(),
  payload: z.record(z.unknown()),
});

export const syncPullQuerySchema = z.object({
  sinceVersion: numericQuery(0),
  features: z
    .preprocess((value) => {
      if (Array.isArray(value)) {
        return value.join(',');
      }
      return value;
    }, z.string().trim().optional())
    .transform((value) =>
      value == null || value.length === 0
        ? []
        : value
            .split(',')
            .map((item) => item.trim())
            .filter((item) => item.length > 0),
    ),
  limit: numericQuery(100, 500),
});

export const syncConflictQuerySchema = z.object({
  status: z.enum(['OPEN', 'RESOLVED', 'IGNORED']).optional().default('OPEN'),
  limit: numericQuery(100, 500),
});

export const syncResolveConflictSchema = z.object({
  resolution: z.record(z.unknown()).optional().default({}),
});

export const appSnapshotQuerySchema = z.object({
  features: z
    .preprocess((value) => {
      if (Array.isArray(value)) {
        return value.join(',');
      }
      return value;
    }, z.string().trim().optional())
    .transform((value) =>
      value == null || value.length === 0
        ? []
        : value
            .split(',')
            .map((item) => item.trim())
            .filter((item) => item.length > 0),
    ),
});

export type SyncPushBatchInput = z.infer<typeof syncPushBatchSchema>;
export type SyncPushEventInput = z.infer<typeof syncPushEventSchema>;
export type SyncPullQueryInput = z.infer<typeof syncPullQuerySchema>;
export type SyncConflictQueryInput = z.infer<typeof syncConflictQuerySchema>;
export type SyncResolveConflictInput = z.infer<
  typeof syncResolveConflictSchema
>;
export type AppSnapshotQueryInput = z.infer<typeof appSnapshotQuerySchema>;
