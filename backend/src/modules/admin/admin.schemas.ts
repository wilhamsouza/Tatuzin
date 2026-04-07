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

export const adminSyncQuerySchema = paginationQuerySchema.extend({
  search: optionalQueryString(120),
  licenseStatus: companyLicenseStatusFilterSchema,
  syncEnabled: optionalBooleanQuery,
  sortBy: z
    .enum(['companyName', 'remoteRecordCount', 'licenseStatus'])
    .default('companyName'),
  sortDirection: sortDirectionSchema.default('asc'),
});

export type AdminLicensePatchInput = z.infer<typeof adminLicensePatchSchema>;
export type AdminCompaniesQueryInput = z.infer<typeof adminCompaniesQuerySchema>;
export type AdminLicensesQueryInput = z.infer<typeof adminLicensesQuerySchema>;
export type AdminAuditQueryInput = z.infer<typeof adminAuditQuerySchema>;
export type AdminSyncQueryInput = z.infer<typeof adminSyncQuerySchema>;
