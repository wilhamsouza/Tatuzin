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

const ownerDateStringSchema = z
  .string()
  .trim()
  .min(1)
  .max(40)
  .refine((value) => parseOwnerDate(value) != null, {
    message: 'Data invalida.',
  });

const ownerDateRangeFields = {
  startDate: ownerDateStringSchema.optional(),
  endDate: ownerDateStringSchema.optional(),
};
const MAX_OWNER_EMPLOYEE_RANGE_DAYS = 93;

const ownerTopListQuerySchema = withValidDateRange(
  z.object({
    ...ownerDateRangeFields,
    limit: z.coerce.number().int().min(1).max(25).default(10),
  }),
);

export const ownerSalesSummaryQuerySchema = withValidDateRange(
  paginationQuerySchema.extend({
    ...ownerDateRangeFields,
    limit: z.coerce.number().int().min(1).max(25).default(10),
    groupBy: z.enum(['day', 'week', 'month']).default('day'),
  }),
);

export const ownerProductsReportQuerySchema = ownerTopListQuerySchema;

export const ownerStockSummaryQuerySchema = paginationQuerySchema.extend({
  limit: z.coerce.number().int().min(1).max(50).default(10),
});

export const ownerCrmSummaryQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(25).default(10),
});

export const ownerCrmCustomersQuerySchema = paginationQuerySchema.extend({
  search: z.string().trim().max(120).default(''),
  status: z
    .enum(['all', 'active', 'inactive', 'with_receivables'])
    .default('all'),
});

export const ownerReceivablesQuerySchema = paginationQuerySchema.extend({
  status: z.enum(['all', 'open', 'overdue', 'paid']).default('open'),
});

export const ownerEmployeesReportQuerySchema = ownerTopListQuerySchema;

export const ownerCashSessionsQuerySchema = withValidDateRange(
  paginationQuerySchema.extend({
    ...ownerDateRangeFields,
    employeeId: z.string().trim().max(120).optional(),
    search: z.string().trim().max(120).default(''),
    status: z
      .enum(['all', 'open', 'closed', 'with_difference'])
      .default('all'),
  }),
);

export const ownerSaleReturnSchema = z.object({
  reason: z.string().trim().min(3).max(500),
  returnToStock: z.coerce.boolean().default(false),
  items: z
    .array(
      z.object({
        saleItemId: z.string().trim().min(1).max(120),
        quantityMil: z.coerce.number().int().positive(),
      }),
    )
    .min(1),
});

export const ownerSaleCancelSchema = z.object({
  reason: z.string().trim().min(3).max(500),
});

export const ownerCommissionsQuerySchema = withMaxDateRangeDays(
  withValidDateRange(z.object(ownerDateRangeFields)),
  MAX_OWNER_EMPLOYEE_RANGE_DAYS,
);

export const ownerEmployeeActivityQuerySchema = withMaxDateRangeDays(
  withValidDateRange(z.object(ownerDateRangeFields)),
  MAX_OWNER_EMPLOYEE_RANGE_DAYS,
);

export const ownerIdParamSchema = z.object({
  id: z
    .string()
    .trim()
    .min(1)
    .max(120)
    .regex(/^[A-Za-z0-9_-]+$/, 'Identificador invalido.'),
});

export type OwnerInvoicesQueryInput = z.infer<
  typeof ownerInvoicesQuerySchema
>;

export type OwnerSalesSummaryQueryInput = z.infer<
  typeof ownerSalesSummaryQuerySchema
>;
export type OwnerProductsReportQueryInput = z.infer<
  typeof ownerProductsReportQuerySchema
>;
export type OwnerStockSummaryQueryInput = z.infer<
  typeof ownerStockSummaryQuerySchema
>;
export type OwnerCrmSummaryQueryInput = z.infer<
  typeof ownerCrmSummaryQuerySchema
>;
export type OwnerCrmCustomersQueryInput = z.infer<
  typeof ownerCrmCustomersQuerySchema
>;
export type OwnerReceivablesQueryInput = z.infer<
  typeof ownerReceivablesQuerySchema
>;
export type OwnerEmployeesReportQueryInput = z.infer<
  typeof ownerEmployeesReportQuerySchema
>;
export type OwnerCashSessionsQueryInput = z.infer<
  typeof ownerCashSessionsQuerySchema
>;
export type OwnerSaleReturnInput = z.infer<typeof ownerSaleReturnSchema>;
export type OwnerSaleCancelInput = z.infer<typeof ownerSaleCancelSchema>;
export type OwnerCommissionsQueryInput = z.infer<
  typeof ownerCommissionsQuerySchema
>;
export type OwnerEmployeeActivityQueryInput = z.infer<
  typeof ownerEmployeeActivityQuerySchema
>;

function withValidDateRange<TSchema extends z.ZodObject<z.ZodRawShape>>(
  schema: TSchema,
) {
  return schema.superRefine((value, context) => {
    const range = value as { startDate?: string; endDate?: string };
    const startDate =
      range.startDate == null ? null : parseOwnerDate(range.startDate);
    const endDate = range.endDate == null ? null : parseOwnerDate(range.endDate);
    if (startDate != null && endDate != null && startDate > endDate) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'startDate deve ser menor ou igual a endDate.',
        path: ['startDate'],
      });
    }
  });
}

function withMaxDateRangeDays<TSchema extends z.ZodTypeAny>(
  schema: TSchema,
  maxDays: number,
) {
  return schema.superRefine((value, context) => {
    const range = value as { startDate?: string; endDate?: string };
    if (range.startDate == null || range.endDate == null) {
      return;
    }
    const startDate = parseOwnerDate(range.startDate);
    const endDate = parseOwnerDate(range.endDate);
    if (startDate == null || endDate == null) {
      return;
    }
    const days =
      Math.floor((endDate.getTime() - startDate.getTime()) / 86_400_000) + 1;
    if (days > maxDays) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: `Escolha um periodo de ate ${maxDays} dias.`,
        path: ['endDate'],
      });
    }
  });
}

function parseOwnerDate(value: string) {
  const normalized = value.trim();
  const dateOnlyMatch = /^\d{4}-\d{2}-\d{2}$/.test(normalized);
  const parsed = new Date(
    dateOnlyMatch ? `${normalized}T00:00:00.000Z` : normalized,
  );
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}
