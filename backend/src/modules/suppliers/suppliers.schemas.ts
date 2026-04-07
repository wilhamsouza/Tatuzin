import { z } from 'zod';

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

const deletedAtField = z
  .union([z.string().datetime(), z.null(), z.undefined()])
  .transform((value) => (value == null ? null : new Date(value)));

export const supplierUpsertSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  name: z.string().trim().min(1).max(160),
  tradeName: nullableTrimmedString(160),
  phone: nullableTrimmedString(40),
  email: nullableTrimmedString(120),
  address: nullableTrimmedString(240),
  document: nullableTrimmedString(40),
  contactPerson: nullableTrimmedString(120),
  notes: nullableTrimmedString(800),
  isActive: z.boolean().default(true),
  deletedAt: deletedAtField,
});

export type SupplierUpsertInput = z.infer<typeof supplierUpsertSchema>;
