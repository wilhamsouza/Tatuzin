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

const optionalNullableString = (maxLength: number) =>
  z
    .union([z.string(), z.null(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return null;
      }
      const normalized = value.trim();
      return normalized.length === 0 ? null : normalized.slice(0, maxLength);
    });

const optionalDateTimeField = z
  .union([z.string().datetime(), z.null(), z.undefined()])
  .transform((value) => {
    if (value == null) {
      return null;
    }
    return new Date(value);
  });

export const crmCustomerContextQuerySchema = z.object({
  companyId: z.string().uuid(),
});

export const crmCustomersListQuerySchema = paginationQuerySchema.extend({
  companyId: z.string().uuid(),
  search: optionalQueryString(120),
  tag: optionalQueryString(60),
  sortBy: z.enum(['name', 'updatedAt', 'createdAt']).default('updatedAt'),
  sortDirection: sortDirectionSchema,
});

export const crmCustomerTimelineQuerySchema = paginationQuerySchema.extend({
  companyId: z.string().uuid(),
});

export const crmCustomerNoteCreateSchema = z.object({
  companyId: z.string().uuid(),
  body: z.string().trim().min(1).max(2400),
});

export const crmCustomerTaskCreateSchema = z.object({
  companyId: z.string().uuid(),
  title: z.string().trim().min(1).max(160),
  description: optionalNullableString(2400),
  dueAt: optionalDateTimeField,
  assignedToUserId: z
    .union([z.string().uuid(), z.null(), z.undefined()])
    .transform((value) => value ?? null),
});

export const crmCustomerTagsApplySchema = z.object({
  companyId: z.string().uuid(),
  mode: z.enum(['replace', 'add']).default('replace'),
  tags: z
    .array(
      z.object({
        label: z.string().trim().min(1).max(40),
        color: optionalNullableString(20),
      }),
    )
    .max(20),
});

export type CrmCustomerContextQueryInput = z.infer<
  typeof crmCustomerContextQuerySchema
>;
export type CrmCustomersListQueryInput = z.infer<
  typeof crmCustomersListQuerySchema
>;
export type CrmCustomerTimelineQueryInput = z.infer<
  typeof crmCustomerTimelineQuerySchema
>;
export type CrmCustomerNoteCreateInput = z.infer<
  typeof crmCustomerNoteCreateSchema
>;
export type CrmCustomerTaskCreateInput = z.infer<
  typeof crmCustomerTaskCreateSchema
>;
export type CrmCustomerTagsApplyInput = z.infer<
  typeof crmCustomerTagsApplySchema
>;
