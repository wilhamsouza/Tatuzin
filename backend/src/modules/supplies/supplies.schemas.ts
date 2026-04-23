import { z } from 'zod';

import { createListQuerySchema } from '../../shared/http/pagination';

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

const nullableUuid = z
  .union([z.string().uuid(), z.null(), z.undefined()])
  .transform((value) => value ?? null);

const deletedAtField = z
  .union([z.string().datetime(), z.null(), z.undefined()])
  .transform((value) => (value == null ? null : new Date(value)));

const supplyCostHistorySchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  purchaseId: nullableUuid,
  purchaseItemLocalUuid: nullableTrimmedString(80),
  source: z.enum(['manual', 'purchase']),
  eventType: z.enum([
    'manual_edit',
    'purchase_created',
    'purchase_updated',
    'purchase_canceled',
    'conversion_changed',
  ]),
  purchaseUnitType: z.string().trim().min(1).max(20).default('un'),
  conversionFactor: z.coerce.number().int().positive(),
  lastPurchasePriceCents: z.coerce.number().int().min(0),
  averagePurchasePriceCents: z
    .union([z.coerce.number().int().min(0), z.null(), z.undefined()])
    .transform((value) => value ?? null),
  changeSummary: nullableTrimmedString(500),
  notes: nullableTrimmedString(800),
  occurredAt: z.string().datetime(),
});

export const supplyUpsertSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  defaultSupplierId: nullableUuid,
  name: z.string().trim().min(1).max(180),
  sku: nullableTrimmedString(80),
  unitType: z.string().trim().min(1).max(20),
  purchaseUnitType: z.string().trim().min(1).max(20),
  conversionFactor: z.coerce.number().int().positive(),
  lastPurchasePriceCents: z.coerce.number().int().min(0).default(0),
  averagePurchasePriceCents: z
    .union([z.coerce.number().int().min(0), z.null(), z.undefined()])
    .transform((value) => value ?? null),
  currentStockMil: z
    .union([z.coerce.number().int(), z.null(), z.undefined()])
    .transform((value) => value ?? null),
  minimumStockMil: z
    .union([z.coerce.number().int(), z.null(), z.undefined()])
    .transform((value) => value ?? null),
  isActive: z.boolean().default(true),
  deletedAt: deletedAtField,
  costHistory: z.array(supplyCostHistorySchema).default([]),
});

export const supplyListQuerySchema = createListQuerySchema({
  includeDeleted: true,
});

export type SupplyUpsertInput = z.infer<typeof supplyUpsertSchema>;
export type SupplyCostHistoryInput = z.infer<typeof supplyCostHistorySchema>;
export type SupplyListQueryInput = z.infer<typeof supplyListQuerySchema>;
