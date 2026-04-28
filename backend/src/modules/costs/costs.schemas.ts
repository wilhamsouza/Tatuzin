import { z } from 'zod';

import { booleanQuerySchema, paginationQuerySchema } from '../../shared/http/pagination';

const nullableTrimmedString = (maxLength: number) =>
  z
    .union([z.string().trim().max(maxLength), z.null(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return null;
      }

      const trimmed = value.trim();
      return trimmed.length === 0 ? null : trimmed;
    });

const parseDate = (value: string) => {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? new Date(`${value}T00:00:00.000Z`)
    : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error('Invalid date');
  }
  return date;
};

const dateStringSchema = z.string().refine((value) => {
  try {
    parseDate(value);
    return true;
  } catch {
    return false;
  }
});

const optionalDateTime = z
  .union([dateStringSchema, z.null(), z.undefined()])
  .transform((value) => (value == null ? null : parseDate(value)));

const requiredDateTime = dateStringSchema.transform(parseDate);

const costTypeSchema = z.enum(['fixed', 'variable']);
const costStatusSchema = z.enum(['pending', 'paid', 'canceled']);
const paymentMethodSchema = z.enum([
  'cash',
  'pix',
  'card',
  'bank_transfer',
  'other',
]);

export const costListQuerySchema = paginationQuerySchema.extend({
  type: costTypeSchema.optional(),
  status: costStatusSchema.optional(),
  startDate: dateStringSchema.optional(),
  endDate: dateStringSchema.optional(),
  overdueOnly: booleanQuerySchema.default(false),
  companyId: z.never().optional(),
});

export const costSummaryQuerySchema = z.object({
  startDate: dateStringSchema.optional(),
  endDate: dateStringSchema.optional(),
  companyId: z.never().optional(),
});

export const costCreateSchema = z.object({
  localUuid: z.string().trim().min(1).max(120),
  description: z.string().trim().min(1).max(240),
  type: costTypeSchema,
  category: nullableTrimmedString(120),
  amountCents: z.coerce.number().int().positive(),
  referenceDate: requiredDateTime,
  notes: nullableTrimmedString(1000),
  isRecurring: z.boolean().default(false),
  companyId: z.never().optional(),
});

export const costUpdateSchema = z.object({
  description: z.string().trim().min(1).max(240).optional(),
  type: costTypeSchema.optional(),
  category: nullableTrimmedString(120).optional(),
  amountCents: z.coerce.number().int().positive().optional(),
  referenceDate: requiredDateTime.optional(),
  notes: nullableTrimmedString(1000).optional(),
  isRecurring: z.boolean().optional(),
  companyId: z.never().optional(),
});

export const costCancelSchema = z.object({
  notes: nullableTrimmedString(1000),
  canceledAt: optionalDateTime,
  companyId: z.never().optional(),
});

export const costPaySchema = z.object({
  paidAt: requiredDateTime,
  paymentMethod: paymentMethodSchema,
  registerInCash: z.boolean().default(false),
  notes: nullableTrimmedString(1000),
  companyId: z.never().optional(),
});

export type CostListQueryInput = z.infer<typeof costListQuerySchema>;
export type CostSummaryQueryInput = z.infer<typeof costSummaryQuerySchema>;
export type CostCreateInput = z.infer<typeof costCreateSchema>;
export type CostUpdateInput = z.infer<typeof costUpdateSchema>;
export type CostCancelInput = z.infer<typeof costCancelSchema>;
export type CostPayInput = z.infer<typeof costPaySchema>;
