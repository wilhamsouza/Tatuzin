import { z } from 'zod';

import {
  paginationQuerySchema,
  sortDirectionSchema,
} from '../../shared/http/pagination';

const optionalQueryString = (maxLength: number) =>
  z
    .union([z.string(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return undefined;
      }
      const normalized = value.trim();
      return normalized.length === 0 ? undefined : normalized.slice(0, maxLength);
    });

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

const nullableDateField = z
  .union([z.string().datetime(), z.null(), z.undefined()])
  .transform((value) => {
    if (value === undefined) {
      return undefined;
    }
    if (value === null) {
      return null;
    }
    return new Date(value);
  });

const nullableIntField = z
  .union([z.coerce.number().int().min(1), z.null(), z.undefined()])
  .transform((value) => {
    if (value === undefined) {
      return undefined;
    }
    return value;
  });

const adminSyncListQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const optionalDateQuery = z
  .union([z.string(), z.undefined()])
  .transform((value) => {
    if (value == null) {
      return undefined;
    }

    const normalized = value.trim();
    return normalized.length === 0 ? undefined : normalized;
  })
  .refine(
    (value) => value === undefined || !Number.isNaN(new Date(value).getTime()),
    { message: 'Data invalida para filtro administrativo de sync.' },
  )
  .transform((value) => (value === undefined ? undefined : new Date(value)));

const syncEventStatusQuerySchema = z
  .enum([
    'pending',
    'accepted',
    'duplicate',
    'rejected',
    'conflict',
    'failed',
    'PENDING',
    'ACCEPTED',
    'DUPLICATE',
    'REJECTED',
    'CONFLICT',
    'FAILED',
  ])
  .transform((value) => value.toUpperCase())
  .optional();

const syncConflictStatusQuerySchema = z
  .enum(['open', 'resolved', 'ignored', 'OPEN', 'RESOLVED', 'IGNORED'])
  .transform((value) => value.toUpperCase())
  .optional();

const adminSyncCenterStatusSchema = z
  .enum(['all', 'requires_review', 'failed', 'conflict', 'healthy'])
  .default('requires_review');

const requiredBodyString = (field: string, maxLength = 1000) =>
  z
    .string({ required_error: `${field} obrigatorio.` })
    .trim()
    .min(1, `${field} obrigatorio.`)
    .max(maxLength);

export const adminLicensePatchSchema = z
  .object({
    plan: z.string().trim().min(1).max(60).optional(),
    status: z
      .enum(['trial', 'active', 'suspended', 'expired'])
      .transform((value) => value.toUpperCase())
      .optional(),
    startsAt: nullableDateField,
    expiresAt: nullableDateField,
    maxDevices: nullableIntField,
    syncEnabled: z.boolean().optional(),
  })
  .refine(
    (value) =>
      value.plan !== undefined ||
      value.status !== undefined ||
      value.startsAt !== undefined ||
      value.expiresAt !== undefined ||
      value.maxDevices !== undefined ||
      value.syncEnabled !== undefined,
    {
      message: 'Informe ao menos um campo para atualizar a licenca.',
    },
  );

const companyLicenseStatusFilterSchema = z
  .enum(['trial', 'active', 'suspended', 'expired', 'without_license'])
  .optional();

export const adminCompaniesQuerySchema = paginationQuerySchema.extend({
  search: optionalQueryString(120),
  isActive: optionalBooleanQuery,
  licenseStatus: companyLicenseStatusFilterSchema,
  syncEnabled: optionalBooleanQuery,
  sortBy: z.enum(['createdAt', 'updatedAt', 'name']).default('createdAt'),
  sortDirection: sortDirectionSchema,
});

export const adminLicensesQuerySchema = paginationQuerySchema.extend({
  search: optionalQueryString(120),
  status: z.enum(['trial', 'active', 'suspended', 'expired']).optional(),
  syncEnabled: optionalBooleanQuery,
  sortBy: z
    .enum(['updatedAt', 'expiresAt', 'companyName', 'status'])
    .default('updatedAt'),
  sortDirection: sortDirectionSchema,
});

export const adminAuditQuerySchema = paginationQuerySchema.extend({
  action: optionalQueryString(80),
  actorUserId: optionalQueryString(80),
  companyId: optionalQueryString(80),
});

export const adminDevicesQuerySchema = paginationQuerySchema.extend({
  companyId: optionalQueryString(80),
  search: optionalQueryString(120),
  clientType: z
    .enum(["all", "MOBILE_APP", "ADMIN_WEB", "OWNER_WEB", "UNKNOWN"])
    .default("all"),
  status: z
    .enum(["all", "active", "pending", "blocked", "revoked"])
    .default("all"),
  attention: optionalBooleanQuery,
});

const adminAccessTargetTypeSchema = z
  .enum(["USER", "MEMBERSHIP", "EMPLOYEE", "user", "membership", "employee"])
  .transform(
    (value) => value.toUpperCase() as "USER" | "MEMBERSHIP" | "EMPLOYEE",
  )
  .default("EMPLOYEE");

export const adminAccessActionDryRunSchema = z.object({
  targetType: adminAccessTargetTypeSchema,
  reason: requiredBodyString("Motivo", 1000),
  note: z.string().trim().max(1000).optional(),
});

export const adminAccessActionSchema = adminAccessActionDryRunSchema.extend({
  confirmationText: requiredBodyString("Texto de confirmacao", 40),
});

export type AdminAccessActionDryRunInput = z.infer<
  typeof adminAccessActionDryRunSchema
>;

export type AdminAccessActionInput = z.infer<typeof adminAccessActionSchema>;

export type AdminDevicesQueryInput = z.infer<typeof adminDevicesQuerySchema>;

export const adminSyncQuerySchema = paginationQuerySchema.extend({
  search: optionalQueryString(120),
  licenseStatus: companyLicenseStatusFilterSchema,
  syncEnabled: optionalBooleanQuery,
  sortBy: z
    .enum(["companyName", "remoteRecordCount", "licenseStatus"])
    .default("companyName"),
  sortDirection: sortDirectionSchema.default("asc"),
});

export const adminSyncOperationalQuerySchema = adminSyncQuerySchema;

export const adminCompanySyncEventsQuerySchema =
  adminSyncListQuerySchema.extend({
    deviceId: optionalQueryString(80),
    status: syncEventStatusQuerySchema,
    entity: optionalQueryString(80),
    feature: optionalQueryString(80),
    from: optionalDateQuery,
    to: optionalDateQuery,
  });

export const adminCompanySyncConflictsQuerySchema =
  adminSyncListQuerySchema.extend({
    status: syncConflictStatusQuerySchema,
  });

export const adminCompanySyncIncidentsQuerySchema =
  adminSyncListQuerySchema.extend({
    severity: optionalQueryString(40),
    from: optionalDateQuery,
    to: optionalDateQuery,
  });

export const adminSyncCenterCompaniesQuerySchema =
  paginationQuerySchema.extend({
    search: optionalQueryString(120),
    status: adminSyncCenterStatusSchema,
  });

export const adminSyncCenterEventsQuerySchema = paginationQuerySchema.extend({
  status: syncEventStatusQuerySchema,
  entity: optionalQueryString(80),
  operation: optionalQueryString(40),
  feature: optionalQueryString(80),
  startDate: optionalDateQuery,
  endDate: optionalDateQuery,
});

export const adminSyncCenterConflictsQuerySchema =
  paginationQuerySchema.extend({
    status: syncConflictStatusQuerySchema,
    code: optionalQueryString(120),
    entity: optionalQueryString(80),
  });

export const adminSyncCenterDetailQuerySchema = z.object({
  companyId: requiredBodyString('companyId', 80),
});

export const adminSyncCenterDryRunBodySchema = z.object({
  companyId: requiredBodyString('companyId', 80),
  reason: requiredBodyString('reason'),
});

export const adminSyncCenterReprocessBodySchema =
  adminSyncCenterDryRunBodySchema.extend({
    confirmationText: z.literal('REPROCESSAR', {
      errorMap: () => ({
        message: 'confirmationText precisa ser REPROCESSAR.',
      }),
    }),
  });

export const adminSyncCenterArchiveBodySchema =
  adminSyncCenterDryRunBodySchema.extend({
    confirmationText: requiredBodyString('confirmationText', 80),
    note: optionalQueryString(1000),
  });

export const adminSyncCenterManualStockAdjustmentBodySchema =
  adminSyncCenterDryRunBodySchema.extend({
    confirmationText: z.literal('AJUSTAR_ESTOQUE', {
      errorMap: () => ({
        message: 'confirmationText precisa ser AJUSTAR_ESTOQUE.',
      }),
    }),
    productId: requiredBodyString('productId', 80),
    productVariantId: optionalQueryString(80),
    quantityDeltaMil: z.coerce.number().int(),
  });

export const adminSyncSupportCommandSchema = z.enum([
  'RETRY_FAILED_SYNC_EVENTS',
  'REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS',
  'CLEAR_RESOLVED_CONFLICT_CACHE',
  'FORCE_SYNC_PULL',
  'REFRESH_SYNC_STATUS',
]);

export const adminSyncSupportDryRunSchema = z.object({
  command: adminSyncSupportCommandSchema,
  reason: requiredBodyString('reason'),
});

export const adminSyncSupportActionSchema = adminSyncSupportDryRunSchema.extend({
  confirmationText: requiredBodyString('confirmationText', 80),
  payload: z.record(z.unknown()).optional().default({}),
});

export type AdminLicensePatchInput = z.infer<typeof adminLicensePatchSchema>;
export type AdminCompaniesQueryInput = z.infer<typeof adminCompaniesQuerySchema>;
export type AdminLicensesQueryInput = z.infer<typeof adminLicensesQuerySchema>;
export type AdminAuditQueryInput = z.infer<typeof adminAuditQuerySchema>;
export type AdminSyncQueryInput = z.infer<typeof adminSyncQuerySchema>;
export type AdminSyncOperationalQueryInput = z.infer<
  typeof adminSyncOperationalQuerySchema
>;
export type AdminCompanySyncEventsQueryInput = z.infer<
  typeof adminCompanySyncEventsQuerySchema
>;
export type AdminCompanySyncConflictsQueryInput = z.infer<
  typeof adminCompanySyncConflictsQuerySchema
>;
export type AdminCompanySyncIncidentsQueryInput = z.infer<
  typeof adminCompanySyncIncidentsQuerySchema
>;
export type AdminSyncCenterCompaniesQueryInput = z.infer<
  typeof adminSyncCenterCompaniesQuerySchema
>;
export type AdminSyncCenterEventsQueryInput = z.infer<
  typeof adminSyncCenterEventsQuerySchema
>;
export type AdminSyncCenterConflictsQueryInput = z.infer<
  typeof adminSyncCenterConflictsQuerySchema
>;
export type AdminSyncCenterDetailQueryInput = z.infer<
  typeof adminSyncCenterDetailQuerySchema
>;
export type AdminSyncCenterDryRunBodyInput = z.infer<
  typeof adminSyncCenterDryRunBodySchema
>;
export type AdminSyncCenterReprocessBodyInput = z.infer<
  typeof adminSyncCenterReprocessBodySchema
>;
export type AdminSyncCenterArchiveBodyInput = z.infer<
  typeof adminSyncCenterArchiveBodySchema
>;
export type AdminSyncCenterManualStockAdjustmentBodyInput = z.infer<
  typeof adminSyncCenterManualStockAdjustmentBodySchema
>;
export type AdminSyncSupportDryRunInput = z.infer<
  typeof adminSyncSupportDryRunSchema
>;
export type AdminSyncSupportActionInput = z.infer<
  typeof adminSyncSupportActionSchema
>;
